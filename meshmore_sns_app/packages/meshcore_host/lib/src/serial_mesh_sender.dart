// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';

import 'companion_link.dart';

/// A [MeshSender] over a USB-serial companion radio.
///
/// This is the host-side twin of the app's `MeshcoreMeshSender`: same
/// contract, same L1 codec, different transport. It adds one thing the BLE
/// adapter did not need, because serial introduces it: an explicit
/// serialisation queue. The firmware has no correlation tag for `OK`/`ERR`
/// on a raw-data send (`MyMesh.cpp` writes a bare `writeOKFrame`), so two
/// sends in flight cannot be told apart. Everything that expects a reply
/// runs one at a time.
class SerialMeshSender implements MeshSender {
  SerialMeshSender({
    required CompanionLink link,
    this.linkTimeout = const Duration(seconds: 20),
  }) : _link = link;

  final CompanionLink _link;

  /// How long to wait for the reply the firmware promises to send.
  /// Raw data is answered immediately after `sendDirect` returns, so this
  /// is a link-failure deadline, not an airtime estimate.
  final Duration linkTimeout;

  final StreamController<Uint8List> _inbound =
      StreamController<Uint8List>.broadcast();
  final StreamController<RadioState> _radioStates =
      StreamController<RadioState>.broadcast();
  final Map<String, Contact> _contacts = <String, Contact>{};

  StreamSubscription<MeshcoreInbound>? _sub;
  StreamSubscription<MeshcoreConnectionState>? _stateSub;

  Completer<void>? _awaitingContacts;
  Completer<bool>? _awaitingReply;
  Uint8List? _boundPath;
  Uint8List? _boundKey;
  int _uplinkMax = GatewayLimits.recordFloor;
  int _lastRssi = GatewayLimits.unknownRssi;

  Future<void> _tail = Future<void>.value();
  bool _started = false;

  // -------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------

  /// Subscribe to the link. Called once, after the link is ready.
  void start() {
    if (_started) return;
    _started = true;
    _sub = _link.inbound.listen(_onInbound);
    _stateSub = _link.states.listen((MeshcoreConnectionState s) {
      _emitRadioState(_mapState(s));
      if (s != MeshcoreConnectionState.ready) {
        // A dropped link loses the bound path's validity: the radio may have
        // a new contact table after a reboot. Keep the key, drop the path so
        // the next bind re-resolves it rather than sending into a stale hop
        // chain.
        _boundPath = null;
        _uplinkMax = GatewayLimits.recordFloor;
      }
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _stateSub?.cancel();
    _completeReply(false);
    _awaitingContacts?.complete();
    _awaitingContacts = null;
    await _inbound.close();
    await _radioStates.close();
  }

  // -------------------------------------------------------------------
  // MeshSender
  // -------------------------------------------------------------------

  @override
  int get uplinkRecordMax => _uplinkMax;

  @override
  int get airtimeOverheadBytes => 2 + (_boundPath?.length ?? 0);

  @override
  Future<bool> isContact(List<int> pubKey) {
    return _serialise(() async {
      final String key = meshKeyHex(pubKey);
      if (_contacts.containsKey(key)) return true;
      await _syncContactsLocked();
      return _contacts.containsKey(key);
    });
  }

  @override
  Future<BindError?> bindPeer(Uint8List pubKey) {
    return _serialise(() async {
      final String key = meshKeyHex(pubKey);
      Contact? contact = _contacts[key];
      if (contact == null) {
        await _syncContactsLocked();
        contact = _contacts[key];
      }
      if (contact == null) return BindError.notAContact;

      final Uint8List path = contact.activePath;
      if (path.isEmpty) return BindError.noPath;

      final int capacity = MeshCarryLimits.rawDataPayloadMax(path.length);
      if (capacity < GatewayLimits.recordFloor) return BindError.noPath;

      _boundPath = path;
      _boundKey = Uint8List.fromList(pubKey);
      _uplinkMax = capacity > GatewayLimits.recordMax
          ? GatewayLimits.recordMax
          : capacity;
      _emitRadioState(radioState);
      // The radio was told to send to this peer, so its last-RSSI reading is
      // the one worth showing. Best effort: a missing stats reply must not
      // fail a bind that already has a valid path.
      unawaited(pollStats());
      return null;
    });
  }

  @override
  Future<SendOutcome> sendRecord(Uint8List record, {required int seq}) {
    return _serialise(() async {
      final Uint8List? path = _boundPath;
      if (path == null) return SendOutcome.errNotFound;
      if (record.length > _uplinkMax) return SendOutcome.errTooLong;

      final Uint8List frame;
      try {
        frame = MeshCarryCodec.sendRawData(path: path, payload: record);
      } on MeshCarryLengthError {
        return SendOutcome.errTooLong;
      } on ArgumentError {
        return SendOutcome.errTooLong;
      }

      _awaitingReply = Completer<bool>();
      try {
        await _link.sendCommand(frame);
      } catch (_) {
        _completeReply(false);
        // The link refused the write. Attributable to this seq, so report it
        // here rather than dropping the connection silently.
        return SendOutcome.errBusy;
      }

      final bool ok;
      try {
        ok = await _awaitingReply!.future.timeout(linkTimeout);
      } on TimeoutException {
        _awaitingReply = null;
        return SendOutcome.localTimeout;
      }
      _awaitingReply = null;
      return ok ? SendOutcome.sentDirect : _lastErrorOutcome;
    });
  }

  @override
  Stream<Uint8List> get inbound => _inbound.stream;

  @override
  RadioState get radioState => _mapState(_link.state);

  @override
  Stream<RadioState> get radioStateChanges => _radioStates.stream;

  @override
  int get rssiDbm => _lastRssi;

  @override
  int get batteryPercent => GatewayLimits.unknownBattery;

  // -------------------------------------------------------------------
  // Diagnostics the host binary exposes
  // -------------------------------------------------------------------

  /// The self info the handshake captured (name, key, radio parameters).
  SelfInfo? get selfInfo => _link.selfInfo;

  /// The peer currently bound, if any.
  Uint8List? get boundPeer => _boundKey;

  /// How many contacts the cached table holds.
  int get contactCount => _contacts.length;

  /// Ask the radio for its counters and cache its last RSSI.
  ///
  /// Called on bind, and by the host binary on a timer. Failures are
  /// swallowed: a missing reading is reported as [GatewayLimits.unknownRssi],
  /// which clients are required to render as "no reading", never as 0.
  Future<void> pollStats() {
    return _serialise(() async {
      try {
        await _link
            .sendCommand(MeshcoreFrameCodec.getStats(kStatsTypeRadio));
      } catch (_) {
        return;
      }
    });
  }

  /// Reload the whole contact table. Public because the host binary may want
  /// to refresh after adding a contact in MeshMore on another device.
  Future<void> syncContacts() => _serialise(_syncContactsLocked);

  // -------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------

  SendOutcome _lastErrorOutcome = SendOutcome.errBusy;

  void _onInbound(MeshcoreInbound frame) {
    switch (frame) {
      case RawDataFrame():
        if (!_inbound.isClosed) _inbound.add(frame.payload);
      case ContactFrame(contact: final Contact c):
        _contacts[meshKeyHex(c.publicKey)] = c;
      case NewAdvertFrame(contact: final Contact c):
        _contacts[meshKeyHex(c.publicKey)] = c;
      case ContactDeletedFrame(publicKey: final Uint8List key):
        _contacts.remove(meshKeyHex(key));
      case EndOfContactsFrame():
        _awaitingContacts?.complete();
      case OkFrame():
        _completeReply(true);
      case ErrorFrame(code: final int? code):
        _lastErrorOutcome = _outcomeForError(code);
        _completeReply(false);
      case StatsFrame(radio: final RadioStats? radio):
        if (radio != null) _lastRssi = radio.lastRssi;
      default:
        break;
    }
  }

  void _completeReply(bool ok) {
    final Completer<bool>? waiting = _awaitingReply;
    if (waiting != null && !waiting.isCompleted) waiting.complete(ok);
  }

  /// Raw data is answered with `OK` or `ERR`. Only `not_found` has a distinct
  /// meaning at this layer ("the radio holds no path to that peer"). Table
  /// full means the radio is momentarily out of packet slots. Every other
  /// code collapses to `errBusy`, which is the honest statement that this
  /// layer cannot attribute it further (recorded in the audit as an open
  /// limitation, not an oversight).
  static SendOutcome _outcomeForError(int? code) {
    // Extension-type getters are not const, so this cannot be a switch
    // pattern over `.code`.
    if (code == MeshcoreErrorCode.notFound.code ||
        code == MeshcoreErrorCode.unsupportedCmd.code) {
      return SendOutcome.errNotFound;
    }
    return SendOutcome.errBusy;
  }

  Future<void> _syncContactsLocked() async {
    if (_link.state != MeshcoreConnectionState.ready) {
      return;
    }
    _awaitingContacts = Completer<void>();
    try {
      await _link.sendCommand(MeshcoreFrameCodec.getContacts());
    } catch (_) {
      _awaitingContacts = null;
      return;
    }
    try {
      await _awaitingContacts!.future.timeout(linkTimeout);
    } on TimeoutException {
      // Partial lists are still useful: keep whatever arrived.
    } finally {
      _awaitingContacts = null;
    }
  }

  RadioState _mapState(MeshcoreConnectionState s) {
    switch (s) {
      case MeshcoreConnectionState.ready:
        return _boundPath == null ? RadioState.noContact : RadioState.connected;
      case MeshcoreConnectionState.reconnecting:
        return RadioState.radioLost;
      case MeshcoreConnectionState.failed:
      case MeshcoreConnectionState.disconnected:
      case MeshcoreConnectionState.handshaking:
        return RadioState.disconnected;
    }
  }

  void _emitRadioState(RadioState state) {
    if (!_radioStates.isClosed) _radioStates.add(state);
  }

  /// Runs [action] after every previously queued action. One outstanding
  /// request at a time is a protocol requirement here, not a simplification.
  Future<T> _serialise<T>(Future<T> Function() action) {
    final Future<void> previous = _tail;
    final Completer<void> done = Completer<void>();
    _tail = done.future;
    return previous.then((_) => action()).whenComplete(done.complete);
  }
}
