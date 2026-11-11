// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// Microclimate / "wx" — weather conditions recognised in chat (P1).
///
/// The device's environment telemetry is shelved (most field firmware
/// reports none), so we mine weather from what people *say* on channel.
/// This file is the pure, offline, per-language lexicon + temperature
/// parser the [WeatherInferenceEngine] runs over message text. No UI
/// strings here — these are matcher inputs (see `weather_inference.dart`).
library;

enum WxCondition { clear, clouds, fog, rain, snow, wind, storm, heat, cold }

/// A glanceable glyph per condition (locale-independent).
String wxGlyph(WxCondition c) => switch (c) {
      WxCondition.clear => '☀',
      WxCondition.clouds => '☁',
      WxCondition.fog => '🌫',
      WxCondition.rain => '🌧',
      WxCondition.snow => '❄',
      WxCondition.wind => '🌬',
      WxCondition.storm => '⛈',
      WxCondition.heat => '🔥',
      WxCondition.cold => '🧊',
    };

/// Per-language surface terms + negators. EN matches on word boundaries
/// (so "sun" ≠ "sunday"); JA matches on substring (no word spacing).
class WxLexicon {
  const WxLexicon({
    required this.terms,
    this.negatorsBefore = const <String>[],
    this.negatorsAfter = const <String>[],
  });

  /// condition → lowercased surface terms.
  final Map<WxCondition, List<String>> terms;

  /// Tokens that negate a match when they sit just *before* it (EN).
  final List<String> negatorsBefore;

  /// Tokens that negate a match when they sit just *after* it (JA).
  final List<String> negatorsAfter;
}

/// Emoji → condition, matched regardless of locale.
const Map<String, WxCondition> kWxEmoji = <String, WxCondition>{
  '☀': WxCondition.clear,
  '🌞': WxCondition.clear,
  '🌤': WxCondition.clear,
  '☁': WxCondition.clouds,
  '⛅': WxCondition.clouds,
  '🌥': WxCondition.clouds,
  '🌫': WxCondition.fog,
  '🌧': WxCondition.rain,
  '🌦': WxCondition.rain,
  '☔': WxCondition.rain,
  '❄': WxCondition.snow,
  '🌨': WxCondition.snow,
  '☃': WxCondition.snow,
  '💨': WxCondition.wind,
  '🌬': WxCondition.wind,
  '⛈': WxCondition.storm,
  '🌩': WxCondition.storm,
  '🌪': WxCondition.storm,
};

const WxLexicon _enLexicon = WxLexicon(
  terms: <WxCondition, List<String>>{
    WxCondition.clear: <String>['sun', 'sunny', 'sunshine', 'clear', 'blue sky', 'bluebird'],
    WxCondition.clouds: <String>['cloud', 'clouds', 'cloudy', 'overcast', 'grey sky', 'gray sky'],
    WxCondition.fog: <String>['fog', 'foggy', 'mist', 'misty', 'haze', 'hazy'],
    WxCondition.rain: <String>['rain', 'raining', 'rainy', 'drizzle', 'downpour', 'shower', 'showers', 'wet'],
    WxCondition.snow: <String>['snow', 'snowing', 'snowy', 'sleet', 'hail', 'flurries', 'blizzard'],
    WxCondition.wind: <String>['wind', 'windy', 'gusty', 'breezy', 'gale', 'blustery'],
    WxCondition.storm: <String>['storm', 'stormy', 'thunder', 'thunderstorm', 'lightning', 'typhoon', 'hurricane', 'cyclone'],
    WxCondition.heat: <String>['hot', 'scorching', 'sweltering', 'muggy', 'humid', 'heatwave', 'baking'],
    WxCondition.cold: <String>['cold', 'freezing', 'frigid', 'chilly', 'frosty', 'frost', 'icy'],
  },
  negatorsBefore: <String>['no', 'not', 'without', "n't", 'never', 'hardly'],
);

const WxLexicon _jaLexicon = WxLexicon(
  terms: <WxCondition, List<String>>{
    WxCondition.clear: <String>['晴れ', '快晴', '日差し', '青空', 'はれ'],
    WxCondition.clouds: <String>['曇り', 'くもり', '雲', '曇'],
    WxCondition.fog: <String>['霧', 'もや', 'かすみ', 'きり'],
    WxCondition.rain: <String>['雨', '小雨', '大雨', 'にわか雨', '土砂降り', 'あめ'],
    WxCondition.snow: <String>['雪', 'みぞれ', 'あられ', 'ゆき', '吹雪'],
    WxCondition.wind: <String>['風', '強風', '突風', 'かぜ'],
    WxCondition.storm: <String>['嵐', '雷', '台風', 'かみなり'],
    WxCondition.heat: <String>['暑い', '蒸し暑い', '猛暑', 'あつい', '暑'],
    WxCondition.cold: <String>['寒い', '冷える', '凍える', 'さむい', '寒'],
  },
  negatorsAfter: <String>['ない', 'ません', 'じゃない', 'ではない'],
);

/// Active lexicon for [languageCode] (falls back to English).
WxLexicon wxLexiconFor(String languageCode) =>
    languageCode == 'ja' ? _jaLexicon : _enLexicon;

// ---------------------------------------------------------------- temps

/// Number(s) with a degree/unit marker — the marker is REQUIRED so bare
/// integers ("see you at 28") aren't read as temperatures. Captures an
/// optional range second number ("18–22°C").
final RegExp _tempRe = RegExp(
  r'(-?\d{1,3})\s*(?:[-–~]\s*(-?\d{1,3}))?\s*'
  r'(°c|℃|°f|℉|degrees?\s*fahrenheit|degrees?\s*celsius|degrees?\s*f\b|degrees?\s*c\b|degrees?|celsius|fahrenheit|°|度)',
  caseSensitive: false,
);

/// Parse all temperatures in [text], normalised to °C. A marker
/// containing 'f' (°f / ℉ / fahrenheit) is treated as Fahrenheit and
/// converted; everything else (°, ℃, 度, degrees, celsius) is Celsius.
List<double> parseTemperaturesC(String text) {
  final List<double> out = <double>[];
  for (final RegExpMatch m in _tempRe.allMatches(text)) {
    final String unit = (m.group(3) ?? '').toLowerCase();
    final bool isF = unit.contains('f') || unit.contains('℉');
    for (final String? g in <String?>[m.group(1), m.group(2)]) {
      if (g == null) continue;
      final double? v = double.tryParse(g);
      if (v == null) continue;
      out.add(isF ? (v - 32) * 5 / 9 : v);
    }
  }
  return out;
}

// ------------------------------------------------------- measured quantities

/// A weather message counts only when it carries a measured quantity.
///
/// The owner's rule, and it is the right one: "nice weather", "rain later",
/// "windy out there" are opinions, and a channel of them is not a weather
/// station. A number and a unit is a report. Everything below exists so a real
/// report is read correctly and a bare word is not.
class WxMeasurements {
  const WxMeasurements({
    this.tempsC = const <double>[],
    this.humidityPct,
    this.pressureHpa,
    this.windMps,
  });

  /// Temperatures found, normalised to °C. A range contributes both ends.
  final List<double> tempsC;
  final int? humidityPct;
  final double? pressureHpa;

  /// Wind speed, normalised to m/s.
  final double? windMps;

  bool get isEmpty =>
      tempsC.isEmpty &&
      humidityPct == null &&
      pressureHpa == null &&
      windMps == null;

  bool get isNotEmpty => !isEmpty;
}

/// Numbers that are a speed, a pressure or a percentage rather than a
/// temperature: a temperature match must not be read out of "12 mph".
const String _nonTempUnit =
    '(?!(?:\\s*(?:mph|kt|kts|knots?|km/?h|kph|m/s|fps|hPa|hpa|mb|mbar|inHg|inhg|%)))';

/// A number immediately followed by a temperature unit. Decimals allowed, and
/// the unit must not be one of the other weather units.
final RegExp _tempUnitRe = RegExp(
  r'(-?\d{1,3}(?:\.\d+)?)\s*(?:[-–~]\s*(-?\d{1,3}(?:\.\d+)?))?\s*'
  r'(°c|℃|°f|℉|degrees?\s*fahrenheit|degrees?\s*celsius|degrees?\s*f\b|'
  '${r'degrees?\s*c\b|degrees?|celsius|fahrenheit|°|度|c\b|f\b)'}$_nonTempUnit',
  caseSensitive: false,
);

final RegExp _percentNearHumidity = RegExp(
  r'(?:humid(?:ity)?|rh|相対湿度|湿度)[^.\n]{0,24}?(\d{1,3})\s*%',
  caseSensitive: false,
);
/// "40% humidity" — the percentage first, which is how most people write it.
final RegExp _numberThenHumidity = RegExp(
  r'(\d{1,3})\s*%\s*(?:rh|relative\s+humidity|humidity|相対湿度|湿度)',
  caseSensitive: false,
);
/// "humidity 40" / "humid 40 percent" — the word then the number, but the
/// number must be a percentage and not a temperature: "humid 95F" is 95
/// degrees at high humidity, not 95 % relative humidity.
final RegExp _humidityWordThenNumber = RegExp(
  r'(?:humid(?:ity)?|rh)[^.\n]{0,16}?(\d{1,3})\s*'
  r'(?:%|percent|pct|パーセント)',
  caseSensitive: false,
);
/// "rh 62" — the abbreviation is itself the unit, which is how weather nets
/// read it. "humid 95" is not, because that number can be a temperature.
final RegExp _rhThenNumber = RegExp(
  r'\brh\s*[:=]?\s*(\d{1,3})\b',
  caseSensitive: false,
);

final RegExp _pressureHpa = RegExp(
  r'(\d{3,4}(?:\.\d{1,2})?)\s*(?:hpa|mb|mbar|ミリバール|ヘクトパスカル)',
  caseSensitive: false,
);
final RegExp _pressureInHg = RegExp(
  r'(\d{2}\.\d{1,2})\s*(?:inhg|in\s*hg|inches?(?:\s*of\s*mercury)?)',
  caseSensitive: false,
);

final RegExp _windSpeed = RegExp(
  r'(\d{1,3}(?:\.\d+)?)\s*(mph|kt|kts|knots?|km/?h|kph|m/s|fps)',
  caseSensitive: false,
);
final RegExp _windContext = RegExp(
  r'\b(?:wind|winds|windy|gust|gusts|gusting|breeze|blowing)\b|風',
  caseSensitive: false,
);

double _toMps(double v, String unit) {
  final String u = unit.toLowerCase();
  if (u.startsWith('mph')) return v * 0.44704;
  if (u.startsWith('kt')) return v * 0.514444;
  if (u.startsWith('km') || u.startsWith('kph')) return v / 3.6;
  if (u.startsWith('fp')) return v * 0.3048;
  return v; // m/s
}

/// Parse the measured quantities in [text].
///
/// Deliberately strict, because the cost of a false positive is a microclimate
/// card that claims a channel reported weather when somebody said "rain later".
WxMeasurements parseWxMeasurements(String text) {
  final List<double> temps = <double>[];

  for (final RegExpMatch m in _tempUnitRe.allMatches(text)) {
    final String unit = (m.group(3) ?? '').toLowerCase();
    final bool isF = unit.contains('f') || unit.contains('℉');
    for (final String? g in <String?>[m.group(1), m.group(2)]) {
      if (g == null) continue;
      final double? v = double.tryParse(g);
      if (v == null) continue;
      // Convert FIRST, then judge: 95F is 35 C and is a perfectly ordinary
      // report, while the old order rejected anything over 70 before the
      // Fahrenheit conversion and silently dropped every warm US reading.
      final double c = isF ? (v - 32) * 5 / 9 : v;
      if (c < -90 || c > 60) continue;
      temps.add(c);
    }
  }

  int? humidity;
  final RegExpMatch? h1 = _percentNearHumidity.firstMatch(text);
  final RegExpMatch? h2 = h1 == null
      ? _numberThenHumidity.firstMatch(text)
      : null;
  final RegExpMatch? h3 = (h1 == null && h2 == null)
      ? _humidityWordThenNumber.firstMatch(text)
      : null;
  final RegExpMatch? h4 = (h1 == null && h2 == null && h3 == null)
      ? _rhThenNumber.firstMatch(text)
      : null;
  final String? hRaw =
      h1?.group(1) ?? h2?.group(1) ?? h3?.group(1) ?? h4?.group(1);
  final int? hVal = hRaw == null ? null : int.tryParse(hRaw);
  if (hVal != null && hVal >= 0 && hVal <= 100) humidity = hVal;

  double? pressure;
  final RegExpMatch? pHpa = _pressureHpa.firstMatch(text);
  final RegExpMatch? pIn = pHpa == null ? _pressureInHg.firstMatch(text) : null;
  if (pHpa != null) {
    final double? v = double.tryParse(pHpa.group(1)!);
    if (v != null && v > 800 && v < 1100) pressure = v;
  } else if (pIn != null) {
    final double? v = double.tryParse(pIn.group(1)!);
    if (v != null && v > 25 && v < 33) pressure = v * 33.8639;
  }

  double? wind;
  if (_windContext.hasMatch(text)) {
    final RegExpMatch? w = _windSpeed.firstMatch(text);
    if (w != null) {
      final double? v = double.tryParse(w.group(1)!);
      if (v != null && v >= 0 && v <= 250) wind = _toMps(v, w.group(2)!);
    }
  }

  return WxMeasurements(
    tempsC: temps,
    humidityPct: humidity,
    pressureHpa: pressure,
    windMps: wind,
  );
}
