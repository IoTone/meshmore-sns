// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meshcore/meshcore.dart';

import 'package:meshmore_sns_app/meshcore/airtime.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';

/// The cutoff the owner asked for: a switch that refuses a send past the hourly
/// budget, with the time left in the hour stated under it.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<MeshcoreController> up() async {
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    addTearDown(mc.dispose);
    return mc;
  }

  test('the cutoff is on until a reader turns it off, and the choice survives',
      () async {
    final MeshcoreController mc = await up();
    expect(mc.airtimeCutoff, isTrue,
        reason: 'a meter that only counts leaves the arithmetic for later');
    await mc.setAirtimeCutoff(false);
    expect(mc.airtimeCutoff, isFalse);

    // A restart reads the same preference.
    final MeshcoreController again = await up();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(again.airtimeCutoff, isFalse);
  });

  test('the countdown states what is left of the budget', () async {
    final MeshcoreController mc = await up();
    final Duration? budget = mc.airtimeBudget;
    expect(budget, isNotNull);
    final Duration? left = mc.airtimeLeft;
    expect(left, isNotNull);
    expect(left! <= budget!, isTrue,
        reason: 'a fresh meter cannot have less than nothing left');

    // Spending moves it, and it never goes negative.
    final Duration cost = mc.airtimeEstimator.forBytes(160);
    mc.airtimeMeterForTest.charge(cost);
    expect(mc.airtimeLeft! <= left, isTrue);
    mc.airtimeMeterForTest.charge(budget * 3);
    expect(mc.airtimeLeft, Duration.zero,
        reason: 'a negative figure is not a countdown');
  });

  test('an unlimited policy has no countdown to state', () async {
    final MeshcoreController mc = await up();
    await mc.setAirtimePolicy(AirtimePolicy.ownedChannel);
    expect(mc.airtimeBudget, isNull);
    expect(mc.airtimeLeft, isNull);
    expect(mc.airtimeCutoff, isTrue, reason: 'the switch is policy-agnostic');
  });
}
