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

  group('whether a failed open is a bond problem', () {
    test('a bond that could not be used is repaired even though the link died',
        () {
      // The regression. A keyless bond makes Android start encryption at
      // connect, SMP never leaves idle, and the link dies on the supervision
      // timeout. The previous rule also demanded `device.isConnected`, which is
      // already false by then, so the repair was unreachable for the one failure
      // it was written for.
      expect(
          BleConnector.shouldRepairBond(
              hadBond: true, identityFailure: false),
          isTrue);
    });

    test('a stranger answering the scan is never re-paired', () {
      // The Nordic UART UUID is cloned by unrelated gadgets. Re-pairing one of
      // those would remove a working bond over a device that was never a radio.
      expect(
          BleConnector.shouldRepairBond(
              hadBond: true, identityFailure: true),
          isFalse);
    });

    test('no bond before the attempt means there is nothing to repair', () {
      expect(
          BleConnector.shouldRepairBond(
              hadBond: false, identityFailure: false),
          isFalse);
    });

    test('one repair per run, because a radio that cannot hold a bond fails '
        'the same way every time', () {
      // A second repair would be another PIN prompt for the user and no new
      // information: the failure that follows it is identical. Meshtastic's
      // own connections guide draws the same line, telling the user to
      // power-cycle the radio once retries stop being productive.
      expect(
          BleConnector.shouldRepairBond(
              hadBond: true, identityFailure: false, alreadyRepaired: true),
          isFalse);
      expect(
          BleConnector.shouldRepairBond(
              hadBond: true, identityFailure: false, alreadyRepaired: false),
          isTrue);
    });
  });
}
