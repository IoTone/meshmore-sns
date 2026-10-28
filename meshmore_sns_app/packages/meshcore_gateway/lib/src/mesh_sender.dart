// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'constants.dart';

/// The gateway's view of the radio.
///
/// The app implements this over its BLE companion link. This package
/// implements no transport, so the service layer stays device-free and
/// testable under `dart test`.
///
/// Everything here carries bytes. Nothing parses a record: the gateway is a
/// blind carrier (`meshmore-sns-architecture.md` §2.4).
abstract interface class MeshSender {
  /// Largest uplink record the bound peer's path allows: `174 - path_len`,
  /// capped at [GatewayLimits.recordMax]. A path that leaves less than
  /// [GatewayLimits.recordFloor] is refused by [bindPeer] rather than
  /// advertised. Before a bind it is the floor. Advertised to the client in `BIND_OK` so
  /// a session sizes to real capacity instead of the absolute ceiling.
  int get uplinkRecordMax;

  /// Whether [pubKey] (32 bytes) is an existing MeshCore contact.
  ///
  /// `BIND` to a non-contact is refused. Adding a contact is a user-visible
  /// action, never a gateway write.
  Future<bool> isContact(List<int> pubKey);

  /// Select the peer subsequent [sendRecord] calls address, after
  /// [isContact] has succeeded and before `BIND_OK` is sent.
  ///
  /// A direct raw-data packet needs the peer's path, which the radio holds in
  /// its contact record, so the bridge must know who it is sending to.
  /// Returns null on success, or the reason the bind must be refused
  /// ([BindError.noPath] when the contact has no usable direct path yet).
  /// [uplinkRecordMax] is read after this returns, so it may depend on the
  /// peer's path length.
  Future<BindError?> bindPeer(Uint8List pubKey);

  /// Send one record as a direct raw-data packet to the bound peer.
  ///
  /// [seq] is the caller's sequence number: echoed in `SEND_RESULT`, not used
  /// by the radio. The return is the radio's own send outcome and is **never**
  /// a delivery acknowledgement.
  Future<SendOutcome> sendRecord(Uint8List record, {required int seq});

  /// Records the radio heard, one per event. Must be a broadcast stream.
  Stream<Uint8List> get inbound;

  /// Radio state, reported in `STATUS`.
  RadioState get radioState;

  /// Radio-state changes, so `STATUS` can be pushed rather than polled.
  /// A getter alone cannot detect a transition.
  Stream<RadioState> get radioStateChanges;

  /// Received signal strength in dBm, reported in `STATUS`.
  int get rssiDbm;

  /// Battery percent, reported in `STATUS`.
  int get batteryPercent;
}

/// A [MeshSender] that records what it was asked to do.
///
/// For tests and for the in-app debug screen before a radio is attached.
class NoopMeshSender implements MeshSender {
  NoopMeshSender({
    int uplinkRecordMax = GatewayLimits.recordFloor,
    this.sendOutcome = SendOutcome.sentDirect,
    RadioState radioState = RadioState.connected,
    Set<String>? contacts,
    this.bindError,
    this.rssiDbm = -60,
    this.batteryPercent = 100,
  })  : _uplinkRecordMax = uplinkRecordMax,
        _radioState = radioState,
        contacts = contacts ?? <String>{};

  /// Public keys, hex-encoded. Seed with [meshKeyHex].
  final Set<String> contacts;

  /// When non-null, [bindPeer] refuses with this.
  BindError? bindError;

  /// The peer last accepted by [bindPeer].
  Uint8List? boundPeer;

  /// Every record handed to [sendRecord], in order.
  final List<({int seq, Uint8List record})> sent =
      <({int seq, Uint8List record})>[];

  final StreamController<Uint8List> _inbound =
      StreamController<Uint8List>.broadcast();
  final StreamController<RadioState> _radio =
      StreamController<RadioState>.broadcast();

  int _uplinkRecordMax;
  SendOutcome sendOutcome;
  RadioState _radioState;
  bool _disposed = false;

  @override
  final int rssiDbm;

  @override
  final int batteryPercent;

  @override
  int get uplinkRecordMax => _uplinkRecordMax;

  set uplinkRecordMax(int value) => _uplinkRecordMax = value;

  @override
  Stream<Uint8List> get inbound => _inbound.stream;

  @override
  Stream<RadioState> get radioStateChanges => _radio.stream;

  @override
  RadioState get radioState => _radioState;

  set radioState(RadioState value) {
    if (value == _radioState) return;
    _radioState = value;
    if (!_radio.isClosed) _radio.add(value);
  }

  @override
  Future<bool> isContact(List<int> pubKey) async =>
      contacts.contains(meshKeyHex(pubKey));

  @override
  Future<BindError?> bindPeer(Uint8List pubKey) async {
    if (bindError != null) return bindError;
    boundPeer = Uint8List.fromList(pubKey);
    return null;
  }

  @override
  Future<SendOutcome> sendRecord(Uint8List record, {required int seq}) async {
    sent.add((seq: seq, record: record));
    return sendOutcome;
  }

  /// Feed a record as if the radio had heard it.
  void receive(List<int> record) {
    if (!_inbound.isClosed) _inbound.add(Uint8List.fromList(record));
  }

  /// Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _inbound.close();
    await _radio.close();
  }
}

/// Lowercase hex of a public key, for contact sets and log lines.
String meshKeyHex(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
