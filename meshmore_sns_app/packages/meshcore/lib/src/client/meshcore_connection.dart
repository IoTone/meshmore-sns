// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';

/// Lifecycle of the companion link.
enum MeshcoreConnectionState {
  /// No transport / link down.
  disconnected,

  /// Transport is up; APP_START sent, awaiting SELF_INFO.
  handshaking,

  /// Handshake complete; [MeshcoreConnection.selfInfo] populated.
  ready,

  /// Link dropped after having been up; awaiting transport recovery.
  reconnecting,

  /// Handshake failed (e.g. no SELF_INFO before timeout).
  failed,
}

/// Hardware-free companion-link state machine.
///
/// Depends only on the abstract [MeshcoreTransport] and the pure-Dart
/// codec, so it is fully unit-testable with a fake transport — no BLE,
/// no device. The concrete [BleMeshcoreTransport] is validated on real
/// hardware in M6.
///
/// Responsibilities: drive the APP_START → SELF_INFO handshake, decode
/// every inbound frame, expose link state, and surface decoded frames
/// to the app. Reconnection policy is intentionally left to the owner
/// (the controller) — this class only reports state.
class MeshcoreConnection {
  MeshcoreConnection({
    this.appName = 'Meshmore SNS',
    this.handshakeTimeout = const Duration(seconds: 8),
  });

  final String appName;
  final Duration handshakeTimeout;

  MeshcoreTransport? _transport;
  StreamSubscription<Uint8List>? _incomingSub;
  StreamSubscription<bool>? _connectedSub;
  Timer? _handshakeTimer;

  final StreamController<MeshcoreConnectionState> _states =
      StreamController<MeshcoreConnectionState>.broadcast();
  final StreamController<MeshcoreInbound> _inbound =
      StreamController<MeshcoreInbound>.broadcast();
  final StreamController<Uint8List> _rawInbound =
      StreamController<Uint8List>.broadcast();

  MeshcoreConnectionState _state = MeshcoreConnectionState.disconnected;
  SelfInfo? _selfInfo;

  int _truncatedFrames = 0;
  int _trailingBytesFrames = 0;

  /// Current link state.
  MeshcoreConnectionState get state => _state;

  /// Notifications that ended before the frame they started.
  ///
  /// A notification is one frame by contract, so a partial one means the
  /// boundary moved: the link is below [MeshcoreBle.requiredMtu], or the
  /// radio truncated. Counted so a short-frame-only link says so instead of
  /// looking like packets that vanish.
  int get truncatedFrames => _truncatedFrames;

  /// Frames that decoded and then had bytes left over.
  ///
  /// Either two frames arrived in one notification (a transport boundary
  /// error) or the radio sent a longer layout than this codec models. Both
  /// used to be dropped in silence, which is how a coalesced pair lost its
  /// second frame.
  int get trailingBytesFrames => _trailingBytesFrames;

  /// The negotiated ATT MTU when the transport has one; `null` for a
  /// transport that does not negotiate (in-memory, socket).
  int? get mtu => _transport?.mtu;

  /// SELF_INFO captured during the handshake (null until [ready]).
  SelfInfo? get selfInfo => _selfInfo;

  /// Link-state transitions (broadcast).
  Stream<MeshcoreConnectionState> get states => _states.stream;

  /// Every decoded device→app frame (broadcast), including the
  /// SELF_INFO consumed by the handshake.
  Stream<MeshcoreInbound> get inbound => _inbound.stream;

  /// Raw device→app frame bytes (broadcast), pre-decode. Used by the
  /// M6 interop capture (the exact `0x88` hex must be preserved).
  Stream<Uint8List> get rawInbound => _rawInbound.stream;

  void _setState(MeshcoreConnectionState s) {
    if (s == _state) return;
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  /// Bind to [transport]. If the transport is already connected the
  /// handshake starts immediately.
  void attach(MeshcoreTransport transport) {
    _detachSubs();
    _transport = transport;
    _selfInfo = null;
    _incomingSub = transport.incoming.listen(_onFrame, onError: (_) {});
    _connectedSub = transport.connected.listen(_onConnectedChanged);
    if (transport.isConnected) _beginHandshake();
  }

  void _onConnectedChanged(bool connected) {
    if (connected) {
      if (_state == MeshcoreConnectionState.disconnected ||
          _state == MeshcoreConnectionState.reconnecting ||
          _state == MeshcoreConnectionState.failed) {
        _beginHandshake();
      }
    } else {
      _handshakeTimer?.cancel();
      _selfInfo = null;
      _setState(_state == MeshcoreConnectionState.ready
          ? MeshcoreConnectionState.reconnecting
          : MeshcoreConnectionState.disconnected);
    }
  }

  void _beginHandshake() {
    final MeshcoreTransport? t = _transport;
    if (t == null) return;
    _setState(MeshcoreConnectionState.handshaking);
    _handshakeTimer?.cancel();
    _handshakeTimer = Timer(handshakeTimeout, () {
      if (_state == MeshcoreConnectionState.handshaking) {
        _setState(MeshcoreConnectionState.failed);
      }
    });
    // Fire-and-forget; a send failure surfaces as a handshake timeout.
    unawaited(_safeSend(t, MeshcoreFrameCodec.appStart(appName: appName)));
  }

  Future<void> _safeSend(MeshcoreTransport t, Uint8List frame) async {
    try {
      await t.send(frame);
    } catch (_) {
      // Swallowed: handshake timeout / state stays as-is.
    }
  }

  void _onFrame(Uint8List bytes) {
    if (!_rawInbound.isClosed) _rawInbound.add(Uint8List.fromList(bytes));
    final MeshcoreInbound frame = MeshcoreFrameCodec.decode(bytes);
    if (frame case DecodeFailure(:final MeshcoreDecodeError error)) {
      switch (error.kind) {
        case DecodeErrorKind.truncated:
          _truncatedFrames++;
        case DecodeErrorKind.trailingBytes:
          _trailingBytesFrames++;
        case DecodeErrorKind.empty:
          break;
      }
    }
    if (frame is SelfInfoFrame) {
      // Always cache the latest SelfInfo — the device can update us
      // post-handshake (e.g. when it eventually acquires a GPS fix
      // while the link is live), and downstream getters
      // (`MeshcoreController.ownLocation`) want the freshest copy.
      _selfInfo = frame.selfInfo;
    }
    if (_state == MeshcoreConnectionState.handshaking &&
        frame is SelfInfoFrame) {
      _handshakeTimer?.cancel();
      _setState(MeshcoreConnectionState.ready);
    }
    if (!_inbound.isClosed) _inbound.add(frame);
  }

  /// Send a raw command frame. Throws [StateError] if the link is not
  /// connected, and [FrameLengthException] if the frame is larger than one
  /// frame may be.
  ///
  /// The cap is the firmware's frame ceiling ([ChannelTextLimits.maxFrameBytes],
  /// `MAX_FRAME_SIZE` 176). Writing one byte more does not fail here: it fails
  /// inside the platform's GATT write, which surfaces as a generic send error
  /// indistinguishable from a lost packet. Refusing first keeps the reason.
  Future<void> sendCommand(Uint8List frame) {
    final MeshcoreTransport? t = _transport;
    if (t == null || !t.isConnected) {
      throw StateError('Meshcore link is not connected');
    }
    if (frame.length > ChannelTextLimits.maxFrameBytes) {
      throw FrameLengthException(
        actual: frame.length,
        maximum: ChannelTextLimits.maxFrameBytes,
      );
    }
    return t.send(frame);
  }

  void _detachSubs() {
    _incomingSub?.cancel();
    _connectedSub?.cancel();
    _incomingSub = null;
    _connectedSub = null;
    _handshakeTimer?.cancel();
  }

  /// Tear down. Does not close the transport (the owner does that).
  Future<void> dispose() async {
    _detachSubs();
    await _states.close();
    await _inbound.close();
    await _rawInbound.close();
  }
}
