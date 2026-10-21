// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/ble_connector.dart';
import 'package:meshmore_sns_app/meshcore/paired_device_store.dart';

/// Real-radio finding (motorola edge 2024 + Heltec V4.3, 2026-10-21): after
/// every app start the pairing read "F8:5B:1B:BE:C5:3D" instead of
/// "MeshCore-HELTEC-BASE". The direct reconnect has no scan result, so the
/// device object carries no name, and the MAC overwrote the stored name.
void main() {
  const String mac = 'F8:5B:1B:BE:C5:3D';
  const PairedDevice saved = PairedDevice(mac, 'MeshCore-HELTEC-BASE');

  test('a direct reconnect (no names) keeps the name already stored', () {
    expect(
        BleConnector.pairedNameFor(
            platformName: '', advName: '', remoteId: mac, stored: saved),
        'MeshCore-HELTEC-BASE');
  });

  test('a scan result still wins: platformName, then advName', () {
    expect(
        BleConnector.pairedNameFor(
            platformName: 'Renamed', advName: 'Adv', remoteId: mac, stored: saved),
        'Renamed');
    expect(
        BleConnector.pairedNameFor(
            platformName: '', advName: 'Adv', remoteId: mac, stored: saved),
        'Adv');
  });

  test("another radio's stored name is never borrowed", () {
    expect(
        BleConnector.pairedNameFor(
            platformName: '',
            advName: '',
            remoteId: 'AA:BB:CC:DD:EE:FF',
            stored: saved),
        'AA:BB:CC:DD:EE:FF');
  });

  test('nothing known at all falls back to the address', () {
    expect(
        BleConnector.pairedNameFor(platformName: '', advName: '', remoteId: mac),
        mac);
  });
}
