// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/ble_connector.dart';

/// Real-radio finding (motorola edge 2024 + Seeed Wio Tracker L1, 2026-10-30):
/// pairing the radio from the phone's own Bluetooth menu left the app reading
/// "no device paired" while Android listed the radio as bonded — two states
/// for one pairing. The fix adopts the OS bond; these are the rules it must
/// follow when doing so.
void main() {
  test('no OS bond means nothing to adopt, even with a history', () {
    expect(
        BleConnector.adoptBondId(
            bondedIds: const <String>[], historyIds: const <String>['A']),
        isNull);
  });

  test('a bonded radio the app has used before is preferred', () {
    // The phone keeps the old radio's bond after the radio is replaced, so
    // the OS list holds both. Picking the first entry of an unordered set
    // would as often as not reconnect to the radio that is no longer here.
    expect(
        BleConnector.adoptBondId(
            bondedIds: const <String>['old-radio', 'new-radio'],
            historyIds: const <String>['new-radio', 'old-radio']),
        'new-radio');
  });

  test('history order decides, not bonded-list order', () {
    expect(
        BleConnector.adoptBondId(
            bondedIds: const <String>['B', 'A'],
            historyIds: const <String>['A']),
        'A');
  });

  test('an unused bond is still adopted when no history entry matches', () {
    // Pairing in the Bluetooth menu and opening the app for the first time:
    // the radio is bonded and has never been used from the app.
    expect(
        BleConnector.adoptBondId(
            bondedIds: const <String>['only-radio'],
            historyIds: const <String>['forgotten-radio']),
        'only-radio');
  });

  test('a history entry for a radio that is no longer bonded is skipped', () {
    expect(
        BleConnector.adoptBondId(
            bondedIds: const <String>['still-here'],
            historyIds: const <String>['gone', 'still-here']),
        'still-here');
  });
}
