// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'prefs.dart';

/// How this reader wants distances written.
enum DistanceUnits {
  /// Metres and kilometres. The default, and what every MeshCore tool reports.
  metric,

  /// Feet and miles, converted on the way out.
  imperial,
}

/// The reader's units and clock, in one place.
///
/// The app had no such setting at all: distances were metres and kilometres in
/// half a dozen formatting sites, temperatures were Celsius, and every timestamp
/// followed the phone's locale through `MaterialLocalizations`. That is a
/// defensible default and a bad only answer — a reader who thinks in miles reads
/// "≈ 0.8 km" and converts it in their head, and a reader whose phone is set to a
/// 12-hour locale gets 12-hour times in one place and 24-hour in another.
///
/// One store, one formatter ([MmFormat]), so a change here cannot leave half the
/// app saying a different thing.
class FormatPrefs extends ChangeNotifier {
  FormatPrefs({
    DistanceUnits units = DistanceUnits.metric,
    bool clock24 = true,
    bool celsius = true,
  })  : _units = units,
        _clock24 = clock24,
        _celsius = celsius;

  static const String _kUnits = 'mm.format.units';
  static const String _kClock24 = 'mm.format.clock24';
  static const String _kCelsius = 'mm.format.celsius';

  DistanceUnits _units;
  bool _clock24;
  bool _celsius;
  bool _loaded = false;

  bool get loaded => _loaded;
  DistanceUnits get units => _units;
  bool get clock24 => _clock24;
  bool get celsius => _celsius;

  Future<void> load() async {
    if (_loaded) return;
    final SharedPreferences p = await SharedPreferences.getInstance();
    _units = Prefs.readBool(p, _kUnits, fallback: true)
        ? DistanceUnits.metric
        : DistanceUnits.imperial;
    _clock24 = Prefs.readBool(p, _kClock24, fallback: true);
    _celsius = Prefs.readBool(p, _kCelsius, fallback: true);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setUnits(DistanceUnits v) async {
    if (v == _units) return;
    _units = v;
    notifyListeners();
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setBool(p, _kUnits, v == DistanceUnits.metric);
  }

  Future<void> setClock24(bool v) async {
    if (v == _clock24) return;
    _clock24 = v;
    notifyListeners();
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setBool(p, _kClock24, v);
  }

  Future<void> setCelsius(bool v) async {
    if (v == _celsius) return;
    _celsius = v;
    notifyListeners();
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setBool(p, _kCelsius, v);
  }
}

/// The reader's units, as one formatter every screen can call.
///
/// Deliberately not a singleton: the prefs are a `ChangeNotifier` above the
/// tree, and a formatter that read a global would keep saying kilometres after
/// the reader changed their mind. [of] returns the neutral default when nothing
/// is provided, so a test or an isolated widget still formats.
abstract final class MmFormat {
  /// The number of decimal places a distance keeps.
  static String distance(double? metres, {FormatPrefs? prefs}) {
    if (metres == null || metres.isNaN || metres.isInfinite) return '—';
    final bool imperial = prefs?.units == DistanceUnits.imperial;
    if (imperial) {
      final double feet = metres * 3.280839895;
      if (feet < 1000) return '${(feet / 10).round() * 10} ft';
      final double miles = metres / 1609.344;
      return miles < 10
          ? '${miles.toStringAsFixed(1)} mi'
          : '${miles.round()} mi';
    }
    if (metres < 1000) return '${(metres / 10).round() * 10} m';
    final double km = metres / 1000.0;
    return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
  }

  /// A distance without the rounding-to-ten step, for a dial's ring labels
  /// where the number is already a round step.
  static String step(double metres, {FormatPrefs? prefs}) {
    if (prefs?.units == DistanceUnits.imperial) {
      final double feet = metres * 3.280839895;
      if (feet < 1000) return '${feet.round()} ft';
      final double miles = metres / 1609.344;
      return miles < 10
          ? '${miles.toStringAsFixed(1)} mi'
          : '${miles.round()} mi';
    }
    if (metres < 1000) return '${metres.round()} m';
    return '${metres.round() ~/ 1000} km';
  }

  /// A temperature, in the reader's scale.
  static String temperature(double? celsius, {FormatPrefs? prefs}) {
    if (celsius == null || celsius.isNaN) return '—';
    if (prefs != null && !prefs.celsius) {
      return '${(celsius * 9 / 5 + 32).round()} °F';
    }
    return '${celsius.round()} °C';
  }

  /// A temperature range, for a summary that reports a low and a high.
  static String range(double lo, double hi, {FormatPrefs? prefs}) {
    final bool f = prefs != null && !prefs.celsius;
    final String unit = f ? '°F' : '°C';
    final int a = f ? (lo * 9 / 5 + 32).round() : lo.round();
    final int b = f ? (hi * 9 / 5 + 32).round() : hi.round();
    return a == b ? '$a$unit' : '$a–$b$unit';
  }

  /// A time of day, in the reader's clock.
  ///
  /// 24-hour is the default here rather than the locale's, because this app's
  /// timestamps are evidence — a message's time, an alarm's deadline — and
  /// "2:32" without a marker is ambiguous in a way "14:32" is not. A reader who
  /// wants the phone's own format turns it off.
  static String clock(DateTime at,
      {FormatPrefs? prefs, BuildContext? context, bool? clock24}) {
    final bool use24 = clock24 ?? prefs?.clock24 ?? true;
    if (use24) {
      return '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}';
    }
    if (context != null) {
      return MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(at),
        alwaysUse24HourFormat: false,
      );
    }
    final int h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    return '$h:${at.minute.toString().padLeft(2, '0')} '
        '${at.hour < 12 ? 'AM' : 'PM'}';
  }
}

/// The format prefs above the tree, or null when there are none.
///
/// Both registrations are tried: the app provides a non-nullable instance, and a
/// harness that wants to vary the units provides a nullable one. Getting this
/// wrong is silent — `Provider.of<FormatPrefs?>` does not match a non-nullable
/// registration, so the app would have formatted kilometres for ever while the
/// setting said miles.
extension FormatScope on BuildContext {
  FormatPrefs? get formatPrefs => _lookup(listen: false);

  /// Watches, so a screen reformats when the reader changes units.
  FormatPrefs? get watchFormatPrefs => _lookup(listen: true);

  FormatPrefs? _lookup({required bool listen}) {
    try {
      return Provider.of<FormatPrefs>(this, listen: listen);
    } catch (_) {
      // Not registered non-nullably.
    }
    try {
      return Provider.of<FormatPrefs?>(this, listen: listen);
    } catch (_) {
      return null;
    }
  }
}
