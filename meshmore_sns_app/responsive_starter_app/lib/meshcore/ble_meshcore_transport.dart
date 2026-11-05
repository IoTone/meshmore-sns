// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:meshcore/meshcore.dart';

/// [MeshcoreTransport] over BLE using the MeshCore companion service
/// (Nordic-UART-style): write command frames to the RX characteristic,
/// receive response/push frames as TX notifications. Per the pinned
/// protocol, **one notification / one write == exactly one frame**, so
/// no reassembly is needed at this layer — provided the link's MTU can
/// carry a frame whole ([MeshcoreBle.requiredMtu]); [BleConnector] refuses
/// a link that cannot, and the negotiated value is reported through
/// [mtu] so a reader can see it.
///
/// Construction is separated from connection orchestration (see
/// [BleConnector]) so this class stays a thin, device-validated
/// adapter; the testable logic lives in [MeshcoreConnection].
class BleMeshcoreTransport implements MeshcoreTransport {
  BleMeshcoreTransport({
    required BluetoothDevice device,
    required BluetoothCharacteristic rx,
    required BluetoothCharacteristic tx,
    bool writeWithoutResponse = false,
    int? mtu,
  })  : _device = device,
        _rx = rx,
        _tx = tx,
        _writeWithoutResponse = writeWithoutResponse,
        _mtu = mtu {
    _incomingSub = _tx.onValueReceived.listen((List<int> v) {
      if (!_incoming.isClosed) {
        _incoming.add(Uint8List.fromList(v));
      }
    });
    _connSub = _device.connectionState.listen((BluetoothConnectionState s) {
      _isConnected = s == BluetoothConnectionState.connected;
      if (!_connected.isClosed) _connected.add(_isConnected);
    });
    // Keep the negotiated size current rather than trusting the open-time
    // reading: a stack that renegotiates downward would otherwise turn every
    // full-size frame into an unexplained platform error.
    try {
      _mtuSub = _device.mtu.listen((int v) {
        if (v > 0) _mtu = v;
      });
    } catch (_) {
      // A platform without an MTU stream keeps the open-time value.
    }
  }

  final BluetoothDevice _device;
  final BluetoothCharacteristic _rx;
  final BluetoothCharacteristic _tx;
  final bool _writeWithoutResponse;

  /// Negotiated ATT MTU, kept current.
  ///
  /// Android can renegotiate the ATT MTU after the link is up, so a value read
  /// once at open goes stale: a later, smaller MTU turns a full-size frame into
  /// a generic GATT error with no explanation. The platform's own stream is
  /// followed for the life of the transport.
  int? _mtu;

  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  final StreamController<bool> _connected =
      StreamController<bool>.broadcast();

  StreamSubscription<List<int>>? _incomingSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<int>? _mtuSub;
  bool _isConnected = true;

  @override
  int? get mtu => _mtu;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Stream<bool> get connected => _connected.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> send(Uint8List frame) {
    if (!_isConnected) {
      throw StateError('BLE link not connected');
    }
    return _rx.write(frame, withoutResponse: _writeWithoutResponse);
  }

  @override
  Future<void> close() async {
    await _incomingSub?.cancel();
    await _connSub?.cancel();
    await _mtuSub?.cancel();
    _isConnected = false;
    try {
      await _device.disconnect();
    } catch (_) {
      // Best-effort.
    }
    await _incoming.close();
    await _connected.close();
  }
}
