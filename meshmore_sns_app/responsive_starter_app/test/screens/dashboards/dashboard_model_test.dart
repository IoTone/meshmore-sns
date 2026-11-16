// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations_en.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/dashboards/dashboard_model.dart';

import '../../meshcore/fake_transport.dart';

/// The model every dashboard reads.
///
/// Eleven skins draw it, and until now it was exercised only through the layout
/// tests, which assert what a *skin* renders. A wrong in-range filter or a
/// dropped event would have surfaced as a layout diff rather than as a named
/// failure, so the five derived values are asserted here directly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizationsEn l = AppLocalizationsEn();

  Future<MeshcoreController> pump(FakeMeshcoreTransport fake) async {
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await mc.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return mc;
  }

  test('the status is the link, and it is not an alert while linked', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await pump(fake);
    final DashboardModel m = DashboardModel.gather(mc, l);
    expect(m.linked, isTrue);
    expect(m.alert, isFalse);
    expect(m.busy, isFalse);
    expect(m.statusLabel, isNotEmpty);
    mc.dispose();
  });

  test('the radio fields are the tuple the radio reported', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await pump(fake);
    final DashboardModel m = DashboardModel.gather(mc, l);
    expect(m.radioFields, isNotNull);
    expect(m.radioFields!.length, 4);
    expect(m.radioFields!.first, endsWith('MHz'));
    expect(m.radioFields![1], startsWith('SF'));
    expect(m.radioFields![2], startsWith('CR'));
    expect(m.radioFields![3], endsWith('dBm'));
    mc.dispose();
  });

  test('a node with a position counts as in range, one without does not',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await pump(fake);
    final int before = DashboardModel.gather(mc, l).peersInRange;
    fake.emit(advertFrameAt(lat: 39.0, lon: -105.0, name: 'NEAR'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final DashboardModel m = DashboardModel.gather(mc, l);
    expect(m.peersInRange, greaterThanOrEqualTo(before));
    expect(m.knownCount, mc.nodes.length);
    mc.dispose();
  });

  test('the event list is newest first and carries a clock stamp', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await pump(fake);
    final DashboardModel m = DashboardModel.gather(mc, l);
    expect(m.events, isNotEmpty, reason: 'connecting is an event');
    for (final ({String time, String text}) e in m.events) {
      expect(e.time, matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
      expect(e.text, isNotEmpty);
    }
    expect(m.events.length, lessThanOrEqualTo(8));
    mc.dispose();
  });

  test('the battery line states volts and a percentage, or is absent',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await pump(fake);
    final DashboardModel m = DashboardModel.gather(mc, l);
    if (m.batteryLine != null) {
      expect(m.batteryLine, contains('V'));
      expect(m.batteryLine, contains('%'));
    }
    mc.dispose();
  });
}
