// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_connection.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// R62 — the 60 s position-bearing self-advert is opt-in.
///
/// The poll cadence is injected (30 ms here, 60 s in the app) so the
/// timer is exercised for real, with no hardware.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Duration tick = Duration(milliseconds: 30);

  Future<({MeshcoreController mc, FakeMeshcoreTransport fake})> ready(
      Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      selfInfoPollInterval: tick,
    );
    await mc.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return (mc: mc, fake: fake);
  }

  int count(FakeMeshcoreTransport f, int op) =>
      f.sent.where((List<int> b) => b.isNotEmpty && b[0] == op).length;

  test('default is off, and the poll sends appStart but never an advert',
      () async {
    final r = await ready(<String, Object>{});
    expect(r.mc.periodicAdvertEnabled, isFalse);
    r.fake.sent.clear();
    await Future<void>.delayed(tick * 5);
    expect(count(r.fake, 0x01), greaterThan(0),
        reason: 'the quiet poll still pulls SelfInfo (BLE only)');
    expect(count(r.fake, 0x07), 0,
        reason: 'no self-advert goes over the air by default');
    expect(count(r.fake, 0x26), 0,
        reason: 'the quiet poll is appStart only');
    r.mc.dispose();
  });

  test('enabled: every tick sends a zero-hop self-advert', () async {
    final r = await ready(<String, Object>{'mm.advert.periodicBeacon': true});
    expect(r.mc.periodicAdvertEnabled, isTrue,
        reason: 'the persisted choice is restored on construction');
    r.fake.sent.clear();
    await Future<void>.delayed(tick * 5);
    final List<List<int>> adverts = r.fake.sent
        .where((List<int> b) => b.isNotEmpty && b[0] == 0x07)
        .toList();
    expect(adverts, isNotEmpty);
    expect(adverts.every((List<int> b) => b[1] == 0), isTrue,
        reason: 'zero-hop, never flood');
    r.mc.dispose();
  });

  test('turning it on and off takes effect without reconnecting and '
      'persists', () async {
    final r = await ready(<String, Object>{});
    await r.mc.setPeriodicAdvertEnabled(true);
    r.fake.sent.clear();
    await Future<void>.delayed(tick * 4);
    expect(count(r.fake, 0x07), greaterThan(0));

    await r.mc.setPeriodicAdvertEnabled(false);
    await Future<void>.delayed(tick * 2); // let an in-flight tick finish
    r.fake.sent.clear();
    await Future<void>.delayed(tick * 4);
    expect(count(r.fake, 0x07), 0);

    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(p.getBool('mm.advert.periodicBeacon'), isFalse);
    r.mc.dispose();
  });

  test('the connect-time appStart is not gated by the beacon setting',
      () async {
    final r = await ready(<String, Object>{});
    // Connect sent APP_START before any poll tick could run.
    expect(count(r.fake, 0x01), greaterThan(0));
    r.mc.dispose();
  });
}
