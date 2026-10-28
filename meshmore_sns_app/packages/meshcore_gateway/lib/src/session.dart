// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'constants.dart';
import 'frame.dart';
import 'governor.dart';
import 'messages.dart';
import 'mesh_sender.dart';
import 'pairing_store.dart';

/// Where a connection is in the handshake.
enum GatewaySessionState { disconnected, helloDone, paired, bound }

/// [GatewayCapability.statusPush] as a bit mask, in a form usable as a
/// default argument: an extension-type getter is not a constant expression.
const int _statusPushMask = 1 << 1;

/// One client connection.
///
/// Transport-free: frames come in through [handleFrame] and go out through
/// the [send] callback, so this class is unit-testable without a socket.
///
/// Frames are handled one at a time and in order. A caller reading a socket
/// must await [handleFrame] before feeding the next frame; otherwise a BIND
/// awaiting `isContact` could interleave with the RECORD that follows it.
class GatewaySession {
  GatewaySession({
    required PairingStore pairing,
    required MeshSender mesh,
    required Governor governor,
    required void Function(Frame frame) send,
    required void Function() onClosed,
    void Function(Uint8List peer)? onBound,
    Duration preAuthTimeout = GatewayLimits.preAuthTimeout,
    AirtimeEstimator estimator = const AirtimeEstimator(),
    int capabilities = _statusPushMask,
  })  : _pairing = pairing,
        _mesh = mesh,
        _governor = governor,
        _send = send,
        _onClosed = onClosed,
        _onBound = onBound,
        _preAuthTimeout = preAuthTimeout,
        _estimator = estimator,
        _capabilities = capabilities;

  final PairingStore _pairing;
  final MeshSender _mesh;
  final Governor _governor;
  final void Function(Frame frame) _send;
  final void Function() _onClosed;
  final void Function(Uint8List peer)? _onBound;
  final Duration _preAuthTimeout;
  final AirtimeEstimator _estimator;
  final int _capabilities;

  GatewaySessionState _state = GatewaySessionState.disconnected;
  Timer? _preAuth;
  StreamSubscription<Uint8List>? _inboundSub;
  StreamSubscription<RadioState>? _radioSub;
  RadioState _lastRadioState = RadioState.disconnected;
  int _clientCapabilities = 0;
  Uint8List? _peer;
  bool _open = false;
  bool _started = false;

  GatewaySessionState get state => _state;

  /// The peer bound in this session, if any.
  Uint8List? get peer => _peer == null ? null : Uint8List.fromList(_peer!);

  bool get isOpen => _open;

  /// Begin the connection: arm the pre-auth deadline and listen for radio
  /// events. Call once, immediately after the socket is accepted.
  void start() {
    if (_started) return;
    _started = true;
    _open = true;
    _lastRadioState = _mesh.radioState;
    _preAuth = Timer(_preAuthTimeout, _onPreAuthTimeout);
    _inboundSub = _mesh.inbound.listen(_onInbound);
    _radioSub = _mesh.radioStateChanges.listen(_onRadioState);
  }

  /// Feed one decoded frame. Await before feeding the next.
  Future<void> handleFrame(Frame frame) async {
    if (!_open) return;
    switch (_state) {
      case GatewaySessionState.disconnected:
        await _onHello(frame);
      case GatewaySessionState.helloDone:
        await _onPair(frame);
      case GatewaySessionState.paired:
        await _onBind(frame);
      case GatewaySessionState.bound:
        await _onBoundFrame(frame);
    }
  }

  /// Server-initiated close.
  void shutdown() => _terminate(CloseReason.shutdown);

  /// The byte stream desynchronised: close, but keep the reason distinct.
  void protocolError() => _terminate(CloseReason.protocol);

  /// Release resources without sending anything. Idempotent.
  void dispose() => _teardown();

  // ---------------------------------------------------------------------
  // States
  // ---------------------------------------------------------------------

  Future<void> _onHello(Frame frame) async {
    if (frame.type != FrameType.hello) return; // ignore out-of-state
    final ({int version, int capabilities})? hello =
        GatewayMessages.readHello(frame);
    if (hello == null) {
      _terminate(CloseReason.protocol);
      return;
    }
    if (hello.version != GatewayLimits.version) {
      _sendSafe(GatewayMessages.helloErr(HelloError.versionMismatch));
      _terminate(CloseReason.version);
      return;
    }
    _clientCapabilities = hello.capabilities;
    _state = GatewaySessionState.helloDone;
    _sendSafe(GatewayMessages.helloOk(
      radioState: _mesh.radioState,
      capabilities: _capabilities,
    ));
  }

  Future<void> _onPair(Frame frame) async {
    if (frame.type != FrameType.pair) return;
    final Uint8List? token = GatewayMessages.readPair(frame);
    if (token == null) {
      _terminate(CloseReason.protocol);
      return;
    }
    if (!_pairing.verify(token)) {
      _sendSafe(GatewayMessages.pairErr(PairError.badToken));
      _terminate(CloseReason.protocol);
      return;
    }
    _preAuth?.cancel();
    _preAuth = null;
    _state = GatewaySessionState.paired;
    _sendSafe(GatewayMessages.pairOk());
  }

  Future<void> _onBind(Frame frame) async {
    if (frame.type != FrameType.bind) return;
    final Uint8List? key = GatewayMessages.readBind(frame);
    if (key == null) {
      _terminate(CloseReason.protocol);
      return;
    }
    bool contact;
    try {
      contact = await _mesh.isContact(key);
    } catch (_) {
      // The radio bridge failed. Say so and close rather than letting the
      // exception end the connection with no frame at all.
      _terminate(CloseReason.shutdown);
      return;
    }
    if (!_open) return; // closed while awaiting the radio
    if (!contact) {
      _sendSafe(GatewayMessages.bindErr(BindError.notAContact));
      _terminate(CloseReason.protocol);
      return;
    }
    BindError? refused;
    try {
      refused = await _mesh.bindPeer(key);
    } catch (_) {
      refused = BindError.noPath;
    }
    if (!_open) return;
    if (refused != null) {
      _sendSafe(GatewayMessages.bindErr(refused));
      _terminate(CloseReason.protocol);
      return;
    }
    _peer = key;
    _state = GatewaySessionState.bound;
    _onBound?.call(key);
    _sendSafe(GatewayMessages.bindOk(
      capabilities: _capabilities,
      uplinkRecordMax: _advertisedCapacity(),
    ));
    _maybePushStatus();
  }

  Future<void> _onBoundFrame(Frame frame) async {
    if (frame.type != FrameType.record) return;
    final ({int seq, Uint8List record})? r = GatewayMessages.readRecord(frame);
    if (r == null) {
      _terminate(CloseReason.protocol);
      return;
    }
    if (r.record.length > _mesh.uplinkRecordMax) {
      _sendSafe(GatewayMessages.sendResult(
        seq: r.seq,
        outcome: SendOutcome.errTooLong,
      ));
      return;
    }
    final Duration estimate = _estimator.forBytes(r.record.length);
    if (!_governor.canSend(estimate)) {
      _sendSafe(GatewayMessages.sendResult(
        seq: r.seq,
        outcome: SendOutcome.errBusy,
      ));
      return;
    }
    SendOutcome outcome;
    try {
      outcome = await _mesh.sendRecord(r.record, seq: r.seq);
    } catch (_) {
      // A throwing bridge transmitted nothing we can account for. Report the
      // record as refused (attributable by seq) instead of dropping the
      // connection silently. `errBusy` is the closest outcome in the v1 set.
      if (_open) {
        _sendSafe(GatewayMessages.sendResult(
          seq: r.seq,
          outcome: SendOutcome.errBusy,
        ));
      }
      return;
    }
    // Charge BEFORE the open check: the radio transmitted even if the client
    // went away while we awaited it, and an unmetered transmission is a
    // governor bypass. Only transmissions spend airtime; a refusal did not.
    if (outcome == SendOutcome.sentDirect ||
        outcome == SendOutcome.sentFlood ||
        outcome == SendOutcome.localTimeout) {
      _governor.charge(estimate);
    }
    if (!_open) return;
    _sendSafe(GatewayMessages.sendResult(seq: r.seq, outcome: outcome));
    // The budget just changed, and a client showing "operations left" has no
    // other way to learn it. No-op unless STATUS push was negotiated.
    _maybePushStatus();
  }

  // ---------------------------------------------------------------------
  // Radio events
  // ---------------------------------------------------------------------

  void _onInbound(Uint8List record) {
    if (_state != GatewaySessionState.bound) return;
    if (record.length > GatewayLimits.recordMax) return;
    _sendSafe(GatewayMessages.recv(record));
  }

  void _onRadioState(RadioState state) {
    if (state == _lastRadioState) return;
    _lastRadioState = state;
    _maybePushStatus();
  }

  void _maybePushStatus() {
    if (_state != GatewaySessionState.bound) return;
    if ((_clientCapabilities & _statusPushMask) == 0) return;
    int airtime = _governor.usedTenthsThisHour;
    if (airtime > 0xFFFF) airtime = 0xFFFF;
    _sendSafe(GatewayMessages.status(
      radioState: _mesh.radioState,
      rssi: _mesh.rssiDbm,
      batteryPercent: _mesh.batteryPercent,
      txAirtimeTenthsThisHour: airtime,
      opsLeftThisHour: _governor.opsLeft(
        _estimator.forBytes(_advertisedCapacity()),
      ),
    ));
  }

  // ---------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------

  /// `BIND_OK` cannot carry more than the absolute ceiling, and zero is
  /// meaningless. Clamp rather than let the frame builder throw on a radio
  /// that reports something odd.
  int _advertisedCapacity() {
    int capacity = _mesh.uplinkRecordMax;
    if (capacity > GatewayLimits.recordMax) capacity = GatewayLimits.recordMax;
    if (capacity < 1) capacity = 1;
    return capacity;
  }

  void _onPreAuthTimeout() {
    if (_state == GatewaySessionState.paired ||
        _state == GatewaySessionState.bound) {
      return;
    }
    _terminate(CloseReason.preAuthTimeout);
  }

  void _sendSafe(Frame frame) {
    try {
      _send(frame);
    } catch (_) {
      // The socket went away mid-write. The read loop will notice.
    }
  }

  void _terminate(CloseReason reason) {
    if (!_open) return;
    _sendSafe(GatewayMessages.close(reason));
    _teardown();
    try {
      _onClosed();
    } catch (_) {
      // Nothing useful to do; the caller owns the socket.
    }
  }

  void _teardown() {
    if (!_open) return;
    _open = false;
    _preAuth?.cancel();
    _preAuth = null;
    final StreamSubscription<Uint8List>? inbound = _inboundSub;
    final StreamSubscription<RadioState>? radio = _radioSub;
    _inboundSub = null;
    _radioSub = null;
    if (inbound != null) unawaited(inbound.cancel());
    if (radio != null) unawaited(radio.cancel());
  }
}
