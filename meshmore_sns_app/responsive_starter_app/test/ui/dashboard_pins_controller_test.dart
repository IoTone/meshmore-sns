// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/ui/dashboard_pins_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a fresh install has no pins and the dashboard is unchanged', () async {
    final DashboardPinsController c = DashboardPinsController();
    await c.load();
    expect(c.isEmpty, isTrue);
    expect(c.pins, isEmpty);
  });

  test('pinning appends, keeps the order the user made, and survives a '
      'restart', () async {
    final DashboardPinsController c = DashboardPinsController();
    await c.load();
    await c.pin(MmPinIds.sos);
    await c.pin(MmPinIds.places);
    await c.move(MmPinIds.places, 0);
    expect(c.pins, <String>[MmPinIds.places, MmPinIds.sos]);

    final DashboardPinsController again = DashboardPinsController();
    await again.load();
    expect(again.pins, <String>[MmPinIds.places, MmPinIds.sos]);
  });

  test('pinning twice keeps the first position, so a second tap cannot move '
      'a card', () async {
    final DashboardPinsController c = DashboardPinsController();
    await c.load();
    await c.pin(MmPinIds.sos);
    await c.pin(MmPinIds.places);
    await c.pin(MmPinIds.sos);
    expect(c.pins, <String>[MmPinIds.sos, MmPinIds.places]);
  });

  test('move clamps instead of throwing, and unpin removes the expansion '
      'state with the card', () async {
    final DashboardPinsController c = DashboardPinsController();
    await c.load();
    await c.pin(MmPinIds.sos);
    await c.pin(MmPinIds.coverage);
    await c.setOpen(MmPinIds.coverage, true);
    expect(c.isOpen(MmPinIds.coverage), isTrue);

    await c.move(MmPinIds.sos, 99);
    expect(c.pins.last, MmPinIds.sos);

    await c.unpin(MmPinIds.coverage);
    expect(c.contains(MmPinIds.coverage), isFalse);
    expect(c.isOpen(MmPinIds.coverage), isFalse);
  });

  test('expansion is only stored for a card that is pinned', () async {
    final DashboardPinsController c = DashboardPinsController();
    await c.load();
    await c.setOpen(MmPinIds.places, true);
    expect(c.isOpen(MmPinIds.places), isFalse);
  });

  test('a stored id that no longer exists is dropped on load, and a '
      'duplicate is ignored', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      DashboardPinsController.prefsKey: jsonEncode(<String, Object>{
        'pins': <String>[
          MmPinIds.sos,
          'pin.removedFeature',
          MmPinIds.sos,
          MmPinIds.coverage,
        ],
        'open': <String>[MmPinIds.sos, 'pin.removedFeature'],
      }),
    });
    final DashboardPinsController c = DashboardPinsController();
    await c.load();
    expect(c.pins, <String>[MmPinIds.sos, MmPinIds.coverage]);
    expect(c.isOpen(MmPinIds.sos), isTrue);
    expect(c.isOpen('pin.removedFeature'), isFalse);
  });

  test('corrupt or non-list state loads as no pins rather than throwing',
      () async {
    for (final String raw in <String>[
      'not json',
      '[]',
      '{"pins": "pin.sos"}',
      '{"pins": [1, 2, 3]}',
    ]) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        DashboardPinsController.prefsKey: raw,
      });
      final DashboardPinsController c = DashboardPinsController();
      await c.load();
      expect(c.pins, isEmpty, reason: raw);
    }
  });

  test('every id in the menu is a known id, so the menu cannot offer a card '
      'the store would drop', () {
    expect(MmPinIds.menu.toSet(), MmPinIds.all);
  });
}
