// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/airtime.dart';

SelfInfo _radio({required double bw, required int sf, required int cr}) {
  return SelfInfo(
    advType: 1,
    txPowerDbm: 20,
    maxTxPowerDbm: 22,
    publicKey: Uint8List(32),
    latitude: 0,
    longitude: 0,
    multiAcks: 0,
    advertLocPolicy: 0,
    telemetryModeRaw: 0,
    manualAddContacts: false,
    frequencyMhz: 910.525,
    bandwidthKhz: bw,
    spreadingFactor: sf,
    codingRate: cr,
    name: 'x',
  );
}

void main() {
  test('the default policy is 36 s of airtime per hour', () {
    expect(AirtimePolicy.onePercentDutyCycle.hourlyBudget,
        const Duration(seconds: 36));
    expect(AirtimePolicy.onePercentDutyCycle.isUnlimited, isFalse);
  });

  test('the owned-channel policy has no voluntary cap', () {
    expect(AirtimePolicy.ownedChannel.hourlyBudget, isNull);
    expect(AirtimePolicy.ownedChannel.isUnlimited, isTrue);
  });

  test('a slower radio is estimated slower (not the flat 4 ms/B default)', () {
    final Duration usa =
        estimatorFor(_radio(bw: 62.5, sf: 7, cr: 5)).forBytes(160);
    final Duration eu =
        estimatorFor(_radio(bw: 62.5, sf: 8, cr: 8)).forBytes(160);
    expect(eu, greaterThan(usa * 2));
  });

  test('unknown radio uses the slowest preset, never less than any', () {
    final Duration unknown = estimatorFor(null).forBytes(172);
    final Duration usa =
        estimatorFor(_radio(bw: 62.5, sf: 7, cr: 5)).forBytes(172);
    expect(unknown, greaterThanOrEqualTo(usa));
    expect(unknown, greaterThan(const Duration(milliseconds: 1500)));
  });
}
