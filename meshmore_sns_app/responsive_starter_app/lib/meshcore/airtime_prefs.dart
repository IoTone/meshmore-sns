// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'airtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which airtime policy this radio meters itself under
/// (`meshmore-sns-architecture.md` §5.5b).
///
/// Default **1 % duty cycle**, because that is the legal limit where a duty
/// cycle exists and a deliberate margin everywhere else. The other mode is a
/// claim about the channel, not about the law: it says nobody else is on this
/// frequency, so the margin costs responsiveness for no one's benefit. The radio
/// keeps its own regulatory limit either way.
///
/// Stored by name, so an older build that does not know a value falls back to
/// the safe one instead of guessing.
abstract final class AirtimePolicyPrefs {
  static const String _kPolicy = 'mm.airtime.policy';

  static const AirtimePolicy fallback = AirtimePolicy.onePercentDutyCycle;

  static Future<AirtimePolicy> policy() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(_kPolicy);
    if (raw == null) return fallback;
    for (final AirtimePolicy v in AirtimePolicy.values) {
      if (v.name == raw) return v;
    }
    return fallback;
  }

  static Future<void> setPolicy(AirtimePolicy value) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_kPolicy, value.name);
  }
}
