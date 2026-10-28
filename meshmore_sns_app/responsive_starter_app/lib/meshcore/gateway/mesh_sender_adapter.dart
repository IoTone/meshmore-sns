// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';

import '../meshcore_controller.dart';
import '../region_presets.dart';

/// [MeshSender] over the app's own [MeshcoreController].
///
/// Carries opaque records as direct raw-data packets
/// (`CMD_SEND_RAW_DATA`, `MyMesh.cpp` `cmd_frame[0] == CMD_SEND_RAW_DATA`).
/// Facts that shape this class, all from that handler:
///  * The firmware answers a raw-data send with a bare **OK** or **ERR**,
///    never `RESP_CODE_SENT`, so the outcome is read from those two frames
///    (registered through [MeshcoreController.sendRawCommand] so neither is
///    credited to a chat message).
///  * `path_len` is a byte count and must be >= 0; the packet is always
///    direct. A contact with no known path cannot be sent to.
///  * A contact's `out_path_len` byte packs the hash size in its top two
///    bits (`Packet.cpp:20-30`), so the byte count is [PathLen.byteLength],
///    not the raw byte, and 0xFF means "no path".
///  * Raw data heard by the radio is pushed as `PUSH_CODE_RAW_DATA` only
///    while an app is connected, and carries no sender
///    (`MyMesh.cpp:801-818`). [inbound] is therefore lossy by firmware
///    design, and a record cannot be attributed to a peer here.
///
/// Sends are serialised: the firmware's OK/ERR carries no correlation tag, so
/// two in flight could not be told apart.
class MeshcoreMeshSender implements MeshSender {
  MeshcoreMeshSender(
    this._mc, {
    this.answerTimeout = const Duration(seconds: 5),
  }) {
    _frames = _mc.inboundFrames.listen(_onFrame);
    _mc.addListener(_onControllerChanged);
    _lastState = radioState;
  }

  final MeshcoreController _mc;

  /// How long to wait for the radio's OK/ERR before reporting
  /// [SendOutcome.localTimeout].
  final Duration answerTimeout;

  late final StreamSubscription<MeshcoreInbound> _frames;
  final StreamController<Uint8List> _inbound =
      StreamController<Uint8List>.broadcast();
  final StreamController<RadioState> _states =
      StreamController<RadioState>.broadcast();
  late RadioState _lastState;
  String? _peerHex;
  int _rssi = _unknownRssi;
  Future<void> _tail = Future<void>.value();
  Completer<MeshcoreInbound>? _awaiting;
  bool _disposed = false;

  /// "No signal reading yet", from the gateway contract rather than a local
  /// magic number: STATUS must always carry a byte, so the contract reserves
  /// one.
  static const int _unknownRssi = GatewayLimits.unknownRssi;

  static String _hex(List<int> b) =>
      b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

  Contact? get _peer {
    final String? hex = _peerHex;
    return hex == null ? null : _mc.contactRecordFor(hex);
  }

  /// The contact's path as raw bytes, or null when it has none the radio can
  /// route on.
  static Uint8List? pathOf(Contact c) {
    if (c.outPathLen == 0xFF) return null; // OUT_PATH_UNKNOWN
    final PathLen p = PathLen(c.outPathLen);
    if (!p.isValid) return null;
    return Uint8List.fromList(c.outPath.sublist(0, p.byteLength));
  }

  @override
  int get uplinkRecordMax {
    final Contact? c = _peer;
    final Uint8List? path = c == null ? null : pathOf(c);
    if (path == null) return GatewayLimits.recordFloor;
    final int room = MeshCarryLimits.rawDataPayloadMax(path.length);
    return room > GatewayLimits.recordMax ? GatewayLimits.recordMax : room;
  }

  @override
  int get airtimeOverheadBytes {
    // MeshCore packet header (1) + the path length byte (1) + the path
    // itself. The record the client sent does not include any of it, but the
    // radio transmits it, so the governor must meter it.
    final Contact? c = _peer;
    final Uint8List? path = c == null ? null : pathOf(c);
    return 2 + (path?.length ?? 0);
  }

  @override
  Future<bool> isContact(List<int> pubKey) async =>
      _mc.contactRecordFor(_hex(pubKey)) != null;

  @override
  Future<BindError?> bindPeer(Uint8List pubKey) async {
    final Contact? c = _mc.contactRecordFor(_hex(pubKey));
    if (c == null) return BindError.notAContact;
    final Uint8List? path = pathOf(c);
    // A path longer than 14 bytes leaves less than the 160 B floor the
    // profile needs (174 - path_len). Refuse rather than advertise a size
    // the radio would reject.
    if (path == null ||
        MeshCarryLimits.rawDataPayloadMax(path.length) <
            GatewayLimits.recordFloor) {
      return BindError.noPath;
    }
    _peerHex = _hex(pubKey);
    return null;
  }

  @override
  Future<SendOutcome> sendRecord(Uint8List record, {required int seq}) {
    final Future<SendOutcome> result = _tail.then((_) => _send(record));
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<SendOutcome> _send(Uint8List record) async {
    final Contact? c = _peer; // re-read: the radio may have learned a path
    if (c == null) return SendOutcome.errNotFound;
    final Uint8List? path = pathOf(c);
    if (path == null) return SendOutcome.errNotFound;
    final Uint8List frame;
    try {
      frame = MeshCarryCodec.sendRawData(path: path, payload: record);
    } on MeshCarryLengthError {
      return SendOutcome.errTooLong;
    } on ArgumentError {
      return SendOutcome.errTooLong; // under the 4-byte raw-data minimum
    }
    final Completer<MeshcoreInbound> answer = Completer<MeshcoreInbound>();
    _awaiting = answer;
    try {
      await _mc.sendRawCommand(frame);
      final MeshcoreInbound reply =
          await answer.future.timeout(answerTimeout);
      if (reply is OkFrame) return SendOutcome.sentDirect;
      final int? code = (reply as ErrorFrame).code;
      if (code == MeshcoreErrorCode.notFound.code) {
        return SendOutcome.errNotFound;
      }
      // table_full is "no free packet". Every other refusal is also
      // "the radio did not transmit"; errBusy is the closest v1 outcome.
      return SendOutcome.errBusy;
    } on TimeoutException {
      _mc.abandonRawSend();
      // The frame was written, so the radio may have transmitted. The
      // governor charges localTimeout for that reason.
      return SendOutcome.localTimeout;
    } finally {
      if (identical(_awaiting, answer)) _awaiting = null;
    }
  }

  void _onFrame(MeshcoreInbound f) {
    if (f is RawDataFrame) {
      _rssi = f.rssi;
      if (!_inbound.isClosed) _inbound.add(f.payload);
      return;
    }
    if (f is OkFrame || f is ErrorFrame) {
      final Completer<MeshcoreInbound>? a = _awaiting;
      if (a != null && !a.isCompleted) a.complete(f);
    }
  }

  void _onControllerChanged() {
    final RadioState now = radioState;
    if (now == _lastState) return;
    _lastState = now;
    if (!_states.isClosed) _states.add(now);
  }

  @override
  Stream<Uint8List> get inbound => _inbound.stream;

  @override
  RadioState get radioState => switch (_mc.state) {
        MeshcoreConnectionState.ready => RadioState.connected,
        MeshcoreConnectionState.reconnecting => RadioState.radioLost,
        _ => RadioState.disconnected,
      };

  @override
  Stream<RadioState> get radioStateChanges => _states.stream;

  @override
  int get rssiDbm => _rssi;

  /// An unread battery is the contract's explicit "unknown" byte, not a
  /// plausible-looking 0.
  @override
  int get batteryPercent =>
      _mc.batteryPercent ?? GatewayLimits.unknownBattery;

  /// Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _mc.removeListener(_onControllerChanged);
    await _frames.cancel();
    await _inbound.close();
    await _states.close();
  }
}

/// The time-on-air estimator for the radio's CURRENT parameters.
///
/// A raw-data packet carries 1 header byte, 1 path-length byte and the path
/// ahead of the record (`Packet.cpp` writeTo), so [overheadBytes] is added.
/// The default 16 is 2 plus the 14-byte path the 160 B floor tolerates: an
/// upper bound, so the governor errs on counting too much.
///
/// With no radio parameters yet (before SelfInfo), the slowest preset in
/// [kRegionPresets] is used, because an under-count would let the gateway
/// exceed its budget on a slow radio.
AirtimeEstimator estimatorFor(SelfInfo? radio, {int overheadBytes = 16}) {
  if (radio != null) {
    return AirtimeEstimator.lora(
      bandwidthHz: (radio.bandwidthKhz * 1000).round(),
      spreadingFactor: radio.spreadingFactor,
      codingRate: radio.codingRate,
      overheadBytes: overheadBytes,
    );
  }
  AirtimeEstimator worst = AirtimeEstimator.lora(
    bandwidthHz: (kRegionPresets.first.bandwidthKhz * 1000).round(),
    spreadingFactor: kRegionPresets.first.spreadingFactor,
    codingRate: kRegionPresets.first.codingRate,
    overheadBytes: overheadBytes,
  );
  for (final RegionPreset p in kRegionPresets) {
    final AirtimeEstimator e = AirtimeEstimator.lora(
      bandwidthHz: (p.bandwidthKhz * 1000).round(),
      spreadingFactor: p.spreadingFactor,
      codingRate: p.codingRate,
      overheadBytes: overheadBytes,
    );
    if (e.forBytes(GatewayLimits.recordMax) >
        worst.forBytes(GatewayLimits.recordMax)) {
      worst = e;
    }
  }
  return worst;
}
