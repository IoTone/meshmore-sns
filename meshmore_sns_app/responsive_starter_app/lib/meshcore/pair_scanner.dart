// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_connector.dart';

/// One radio the phone can hear, reduced to what the picker shows.
///
/// Deliberately not flutter_blue_plus' `ScanResult`: the pairing flow has to
/// be provable without a Bluetooth stack, and a `ScanResult` cannot be built
/// in a test.
class PairHit {
  const PairHit({
    required this.remoteId,
    required this.name,
    required this.rssi,
  });

  final String remoteId;
  final String name;
  final int rssi;
}

/// The Bluetooth adapter, as the flow cares about it.
enum AdapterState {
  /// Powered and usable.
  on,

  /// Present but switched off by the user (or the OS).
  off,

  /// No usable adapter: a platform without one, or a permission model that
  /// hides it.
  unsupported,
}

/// What the pairing flow needs from the platform, behind one seam.
///
/// The screen never touches flutter_blue_plus, so its five failure paths —
/// permission refused, adapter off, nothing in range, open failure, leaving
/// mid-scan — are ordinary tests instead of hardware runs.
abstract interface class PairScanner {
  /// The adapter now, without waiting for a change.
  Future<AdapterState> adapterNow();

  /// Adapter changes. A user who walks to the OS and switches Bluetooth on is
  /// back in the flow without re-entering it.
  Stream<AdapterState> get adapter;

  /// Every hit seen so far, re-sent as the set grows (the same shape
  /// [BleConnector.scanForDevices] produces). The stream closes when the scan
  /// window ends.
  Stream<List<PairHit>> scan({Duration timeout});

  /// Stop an in-flight scan. Idempotent.
  Future<void> stopScan();
}

/// The real scanner: flutter_blue_plus through [BleConnector].
class BlePairScanner implements PairScanner {
  const BlePairScanner();

  static AdapterState _map(BluetoothAdapterState s) => switch (s) {
        BluetoothAdapterState.on => AdapterState.on,
        BluetoothAdapterState.off => AdapterState.off,
        _ => AdapterState.unsupported,
      };

  @override
  Future<AdapterState> adapterNow() async {
    try {
      return _map(await FlutterBluePlus.adapterState
          .first
          .timeout(const Duration(seconds: 3)));
    } catch (_) {
      return AdapterState.unsupported;
    }
  }

  @override
  Stream<AdapterState> get adapter =>
      FlutterBluePlus.adapterState.map(_map);

  @override
  Stream<List<PairHit>> scan({Duration timeout = const Duration(seconds: 12)}) async* {
    // The scan filters on the Nordic UART service the firmware advertises, and
    // the name that proves a hit is a radio rather than a gadget that cloned
    // the UUID (`MeshCore-<node>`, `SerialBLEInterface.cpp`). An unnamed hit is
    // still offered: a radio whose scan response was missed must not read as
    // absent, and the open path proves the service before anything bonds.
    yield* BleConnector.scanForDevices(timeout: timeout).map(
      (List<ScanResult> snapshot) => <PairHit>[
        for (final ScanResult r in snapshot)
          PairHit(
            remoteId: r.device.remoteId.str,
            name: _nameOf(r),
            rssi: r.rssi,
          ),
      ],
    );
  }

  static String _nameOf(ScanResult r) {
    if (r.device.platformName.isNotEmpty) return r.device.platformName;
    if (r.device.advName.isNotEmpty) return r.device.advName;
    return r.device.remoteId.str;
  }

  @override
  Future<void> stopScan() => BleConnector.stopScan();
}
