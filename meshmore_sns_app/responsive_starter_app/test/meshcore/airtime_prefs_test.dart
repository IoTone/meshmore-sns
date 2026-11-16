// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/meshcore/airtime.dart';
import 'package:meshmore_sns_app/meshcore/airtime_prefs.dart';

/// What the app meters itself under, and what the last process spent.
///
/// Two facts are load-bearing. A policy the user chose is theirs and is never
/// re-derived, while a default this build picked follows the band the radio
/// reports. And the rolling hour is written down, because a restart that forgot
/// what the last launch spent handed out a fresh hour over a band whose rule it
/// was already refusing to honour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('with no choice, the band decides', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    expect(AirtimePolicyPrefs.hasChoice(), completion(isFalse));
    expect(await AirtimePolicyPrefs.policy(frequencyMhz: 910.525),
        AirtimePolicy.ownedChannel);
    expect(await AirtimePolicyPrefs.policy(frequencyMhz: 868.1),
        AirtimePolicy.onePercentDutyCycle);
    // Before any radio has reported, the stricter answer stands.
    expect(await AirtimePolicyPrefs.policy(),
        AirtimePolicy.onePercentDutyCycle);
  });

  test('a chosen policy outranks the band, in both directions', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mm.airtime.policy': 'onePercentDutyCycle',
    });
    expect(await AirtimePolicyPrefs.hasChoice(), isTrue);
    expect(await AirtimePolicyPrefs.policy(frequencyMhz: 910.525),
        AirtimePolicy.onePercentDutyCycle,
        reason: 'a user who chose the cap keeps it on a band with none');

    SharedPreferences.setMockInitialValues(<String, Object>{
      'mm.airtime.policy': 'ownedChannel',
    });
    expect(await AirtimePolicyPrefs.policy(frequencyMhz: 868.1),
        AirtimePolicy.ownedChannel,
        reason: 'and a user who chose no cap keeps it on a band that has one');
  });

  test('an unknown stored name is not a choice and falls back to the band',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mm.airtime.policy': 'courtesyTenPercent',
    });
    expect(await AirtimePolicyPrefs.policy(frequencyMhz: 910.525),
        AirtimePolicy.ownedChannel);
    expect(await AirtimePolicyPrefs.policy(frequencyMhz: 868.1),
        AirtimePolicy.onePercentDutyCycle);
  });

  test('the spend snapshot round trips through preferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    expect(await AirtimePolicyPrefs.spend(), isNull);
    await AirtimePolicyPrefs.setSpend('29241360:1500');
    expect(await AirtimePolicyPrefs.spend(), '29241360:1500');
    await AirtimePolicyPrefs.setSpend('');
    expect(await AirtimePolicyPrefs.spend(), isEmpty);
  });

  test('choosing a policy writes the name, not the index', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AirtimePolicyPrefs.setPolicy(AirtimePolicy.ownedChannel);
    final SharedPreferences p = await SharedPreferences.getInstance();
    // By name, so an older build that does not know a value falls back to the
    // safe one rather than to whatever sat at that index.
    expect(p.getString('mm.airtime.policy'), 'ownedChannel');
  });
}
