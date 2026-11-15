// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'airtime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../util/prefs.dart';

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

  /// What the rolling hour has spent, as [AirtimeMeter.snapshot] writes it.
  ///
  /// Without this a restart hands out a fresh hour: the other radio project
  /// measured an afternoon of app restarts reaching **61.4 s against a 36 s
  /// budget** every time, because each launch forgot what the last had spent
  /// (`ldmux`, `docs/AIRTIME.md`, 2026-11-07). The window is the meter's own
  /// rolling hour, not a wall-clock one.
  static const String _kSpend = 'mm.airtime.spend';

  /// Whether the meter refuses a send past the budget, or only counts it.
  ///
  /// The owner asked for a cutoff a reader can switch on, with the time left in
  /// the hour stated under it (2026-11-06). It is separate from the policy on
  /// purpose: the policy says what the channel's budget is, and the cutoff says
  /// whether this app enforces it.
  static const String _kCutoff = 'mm.airtime.cutoff';

  static const AirtimePolicy fallback = AirtimePolicy.onePercentDutyCycle;

  /// The user's policy, or the band's own rule when they never chose.
  ///
  /// [frequencyMhz] is the radio's reported preset. Null keeps [fallback].
  static Future<AirtimePolicy> policy({double? frequencyMhz}) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(_kPolicy);
    if (raw == null) return AirtimePolicy.defaultForBand(frequencyMhz);
    for (final AirtimePolicy v in AirtimePolicy.values) {
      if (v.name == raw) return v;
    }
    return AirtimePolicy.defaultForBand(frequencyMhz);
  }

  /// True when the user picked a policy themselves. A derived default is not a
  /// choice and may be re-derived when the radio reports a different band.
  static Future<bool> hasChoice() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return p.getString(_kPolicy) != null;
  }

  static Future<String?> spend() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return Prefs.readString(p, _kSpend);
  }

  static Future<void> setSpend(String snapshot) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setString(p, _kSpend, snapshot);
  }

  /// Default on, because a meter that only counts leaves the reader to do the
  /// arithmetic an hour later.
  static Future<bool> cutoff() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return p.getBool(_kCutoff) ?? true;
  }

  static Future<void> setCutoff(bool value) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setBool(_kCutoff, value);
  }

  static Future<void> setPolicy(AirtimePolicy value) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setString(p, _kPolicy, value.name);
  }
}
