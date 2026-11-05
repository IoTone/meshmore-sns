// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/radio_config_transaction.dart';
import 'package:meshmore_sns_app/meshcore/radio_safety_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const RadioOperatingPoint _previous = RadioOperatingPoint(
  frequencyMhz: 910.525,
  bandwidthKhz: 62.5,
  spreadingFactor: 7,
  codingRate: 5,
  txPowerDbm: 22,
  pathHashMode: 2,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('the previous point is written before the first frame, and read back',
      () async {
    await RadioSafetyStore.arm('keyA', _previous);
    expect(await RadioSafetyStore.armed('keyA'), _previous);
    expect(await RadioSafetyStore.armed('keyB'), isNull,
        reason: 'a different radio must not inherit another one\'s revert');
  });

  test('a revert is single use: the record is gone before it is returned',
      () async {
    await RadioSafetyStore.arm('keyA', _previous);
    expect(await RadioSafetyStore.consume('keyA'), _previous);
    expect(await RadioSafetyStore.consume('keyA'), isNull,
        reason: 'a second revert would rewrite the radio with stale values');
    expect(await RadioSafetyStore.armed('keyA'), isNull);
  });

  test('clearing forgets the point and its radio', () async {
    await RadioSafetyStore.arm('keyA', _previous);
    await RadioSafetyStore.clear();
    expect(await RadioSafetyStore.armed('keyA'), isNull);
  });
}
