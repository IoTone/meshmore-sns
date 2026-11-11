// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/sns/weather_inference.dart';
import 'package:meshmore_sns_app/sns/weather_lexicon.dart';

WxObservation? scanEn(String t) =>
    WeatherInferenceEngine.scan(t, languageCode: 'en');
WxObservation? scanJa(String t) =>
    WeatherInferenceEngine.scan(t, languageCode: 'ja');

void main() {
  group('temperature parsing (→ °C)', () {
    test('degree forms', () {
      expect(parseTemperaturesC('28°C here'), <double>[28]);
      expect(parseTemperaturesC('it is 28°'), <double>[28]);
      expect(parseTemperaturesC('28 degrees'), <double>[28]);
      expect(parseTemperaturesC('28度'), <double>[28]);
    });
    test('fahrenheit converts', () {
      final List<double> v = parseTemperaturesC('72°F');
      expect(v.single, closeTo(22.2, 0.1));
    });
    test('ranges capture both ends', () {
      expect(parseTemperaturesC('18–22°C'), <double>[18, 22]);
    });
    test('bare numbers are NOT temperatures', () {
      expect(parseTemperaturesC('meet at 28 by the dock'), isEmpty);
      expect(parseTemperaturesC('channel 5'), isEmpty);
    });
  });

  // The owner's rule, and the reason the microclimate card stopped claiming a
  // channel reported weather: a condition word is an opinion. Only a measured
  // quantity makes a message a report, and then the word is decoration on it.
  group('a bare condition word is not data', () {
    test('words alone never become an observation', () {
      expect(scanEn('raining hard out here'), isNull);
      expect(scanEn('thick fog on the ridge'), isNull);
      expect(scanEn('clear blue sky today'), isNull);
      expect(scanEn('rain later maybe'), isNull);
      expect(scanEn('windy out of the southeast'), isNull);
      expect(scanEn('nice weather today'), isNull);
      expect(scanEn('heading out ☀'), isNull);
      expect(scanJa('今日は雨です'), isNull);
      expect(scanJa('晴れてきた'), isNull);
      expect(scanJa('暑い'), isNull);
    });

    test('the same words with a measurement are a report', () {
      expect(scanEn('raining hard, 14°C')!.conditions,
          contains(WxCondition.rain));
      expect(scanEn('thick fog, 6°C')!.conditions, contains(WxCondition.fog));
      expect(scanEn('clear, 22°C')!.conditions, contains(WxCondition.clear));
      expect(scanJa('雨、14度')!.conditions, contains(WxCondition.rain));
    });
  });

  group('condition scanning (EN)', () {
    test('word boundaries — "sunday" is not "sun"', () {
      expect(scanEn('see you sunday'), isNull);
    });
    test('negation suppresses the condition, and no measurement means no report',
        () {
      expect(scanEn('no rain so far'), isNull);
      expect(scanEn("it isn't raining"), isNull);
      expect(scanEn("it isn't raining, 9°C")!.conditions, isEmpty);
    });
    test('temperature alone is an observation', () {
      final WxObservation o = scanEn('about 31°C')!;
      expect(o.temperatureC, closeTo(31, 0.01));
      expect(o.conditions, isEmpty);
    });
    test('one measurement is a report, two read stronger', () {
      final WxObservation one = scanEn('23.2C out')!;
      expect(one.temperatureC, closeTo(23.2, 0.01));
      final WxObservation two = scanEn('23.2C and 40% humidity')!;
      expect(two.temperatureC, closeTo(23.2, 0.01));
      expect(two.humidityPct, 40);
      expect(two.confidence, greaterThan(one.confidence));
    });

    test('a condition + temp reads with higher confidence', () {
      final WxObservation o = scanEn('hot, like 34°C')!;
      expect(o.conditions, contains(WxCondition.heat));
      expect(o.temperatureC, closeTo(34, 0.01));
      expect(o.confidence, greaterThan(0.8));
    });
    test('an emoji alone is not data either', () {
      expect(scanEn('heading out ☀'), isNull);
      expect(scanEn('heading out ☀ 18°C')!.conditions,
          contains(WxCondition.clear));
    });
    test('non-weather text yields nothing', () {
      expect(scanEn('on my way to the meetup'), isNull);
    });
  });

  group('condition scanning (JA)', () {
    test('with a measurement, rain / clear / hot are read', () {
      expect(scanJa('今日は雨です、14度')!.conditions,
          contains(WxCondition.rain));
      expect(scanJa('晴れてきた、22度')!.conditions,
          contains(WxCondition.clear));
      expect(scanJa('暑い、33度')!.conditions, contains(WxCondition.heat));
    });
    test('JA negation (trailing) suppresses', () {
      expect(scanJa('雨じゃない'), isNull);
    });
    test('JA temperature', () {
      expect(scanJa('今 28度')!.temperatureC, closeTo(28, 0.01));
    });
  });

  group('aggregateAmbient', () {
    final DateTime t0 = DateTime(2026, 6, 6, 12);
    test('empty → null', () {
      expect(aggregateAmbient(const <WxObservation>[]), isNull);
    });
    test('dominant condition + temp stats', () {
      final List<WxObservation> obs = <WxObservation>[
        WeatherInferenceEngine.scan('raining, 17°C',
            languageCode: 'en', at: t0)!,
        WeatherInferenceEngine.scan('still rain, 19°C', languageCode: 'en', at: t0)!,
        WeatherInferenceEngine.scan('sunny now 24°C', languageCode: 'en', at: t0.add(const Duration(minutes: 5)))!,
      ];
      final AmbientWx a = aggregateAmbient(obs)!;
      expect(a.dominant, WxCondition.rain); // 2 rain vs 1 clear
      expect(a.mentions, 3);
      expect(a.tempMinC, closeTo(17, 0.01));
      expect(a.tempMaxC, closeTo(24, 0.01));
      expect(a.lastSeen, t0.add(const Duration(minutes: 5)));
    });
    test('the measured quantities survive aggregation', () {
      final List<WxObservation> obs = <WxObservation>[
        WeatherInferenceEngine.scan('23.2C, 40% humidity, 1013 hPa',
            languageCode: 'en', at: t0)!,
        WeatherInferenceEngine.scan('wind 20 mph, 25C',
            languageCode: 'en', at: t0)!,
      ];
      final AmbientWx a = aggregateAmbient(obs)!;
      expect(a.humidityAvgPct, 40);
      expect(a.pressureAvgHpa, closeTo(1013, 0.01));
      expect(a.windMaxMps, closeTo(8.94, 0.05));
      expect(a.hasMeasurement, isTrue);
    });

    test('temperature-only observations → null dominant but temps set', () {
      final AmbientWx a = aggregateAmbient(<WxObservation>[
        WeatherInferenceEngine.scan('30°C', languageCode: 'en', at: t0)!,
      ])!;
      expect(a.dominant, isNull);
      expect(a.tempAvgC, closeTo(30, 0.01));
    });
  });

  group('scanAny (multi-locale)', () {
    test('merges EN + JA conditions in one message', () {
      final WxObservation? o = WeatherInferenceEngine.scanAny('雨 and hot, 30度');
      expect(o, isNotNull);
      expect(o!.conditions,
          containsAll(<WxCondition>[WxCondition.rain, WxCondition.heat]));
    });
    test('null when neither locale matches', () {
      expect(WeatherInferenceEngine.scanAny('see you at the dock'), isNull);
    });
  });

  group('aggregateMicroclimates (P2)', () {
    final DateTime t0 = DateTime(2026, 6, 7, 12);
    WxObservation at(double lat, double lon, Set<WxCondition> c,
            {double? temp, String? name}) =>
        WxObservation(
                conditions: c,
                temperatureC: temp,
                confidence: 0.8,
                at: t0)
            .locatedAt(lat, lon, name);

    test('clusters nearby obs into one place; dominant + temp + count', () {
      final List<Microclimate> climates = aggregateMicroclimates(
        <WxObservation>[
          at(47.60, -122.33, <WxCondition>{WxCondition.rain},
              temp: 18, name: 'Seattle'),
          at(47.61, -122.34, <WxCondition>{WxCondition.rain},
              temp: 20, name: 'Seattle'),
          at(45.52, -122.67, <WxCondition>{WxCondition.clear},
              temp: 25, name: 'Portland'),
        ],
      );
      expect(climates.length, 2);
      final Microclimate seattle =
          climates.firstWhere((Microclimate m) => m.placeName == 'Seattle');
      expect(seattle.dominant, WxCondition.rain);
      expect(seattle.mentions, 2);
      expect(seattle.tempMinC, closeTo(18, 0.01));
      expect(seattle.tempMaxC, closeTo(20, 0.01));
      expect(climates.first.mentions, 2); // strongest first
    });

    test('unlocated observations are ignored', () {
      expect(
          aggregateMicroclimates(<WxObservation>[
            WeatherInferenceEngine.scan('raining, 12°C', languageCode: 'en')!,
          ]),
          isEmpty);
    });

    test('withMeasured flags + prefers the sensor reading (P3)', () {
      final Microclimate m = Microclimate(
        lat: 1,
        lon: 2,
        placeName: 'X',
        dominant: WxCondition.rain,
        tempMinC: 18,
        tempAvgC: 19,
        tempMaxC: 20,
        mentions: 3,
        lastSeen: t0,
      );
      expect(m.measured, isFalse);
      final Microclimate mm = m.withMeasured(21.4);
      expect(mm.measured, isTrue);
      expect(mm.measuredTempC, closeTo(21.4, 0.01));
      expect(mm.hasTemp, isTrue);
      // a place with only a measured temp (no text temp) still reads.
      final Microclimate noText = Microclimate(
          lat: 1,
          lon: 2,
          placeName: 'Y',
          dominant: WxCondition.clear,
          tempMinC: null,
          tempAvgC: null,
          tempMaxC: null,
          mentions: 1,
          lastSeen: t0);
      expect(noText.withMeasured(30).hasTemp, isTrue);
    });
  });

  _measurementRules();
}

/// The measured quantities, one test per owner rule: a number and a unit is a
/// report, a bare word is not, and one unit is never read as another.
void _measurementRules() {
  group('measured quantities', () {
    test('humidity reads in both word orders', () {
      expect(parseWxMeasurements('humidity 40%').humidityPct, 40);
      expect(parseWxMeasurements('40% humidity').humidityPct, 40);
      expect(parseWxMeasurements('RH 62%').humidityPct, 62);
    });

    test('pressure reads hPa and inHg, normalised', () {
      expect(parseWxMeasurements('1013 hPa').pressureHpa, closeTo(1013, 0.01));
      expect(parseWxMeasurements('1008mb').pressureHpa, closeTo(1008, 0.01));
      expect(parseWxMeasurements('29.92 inHg').pressureHpa,
          closeTo(1013.2, 0.5));
    });

    test('wind needs a wind word as well as a speed', () {
      // "12 mph" on its own is a car, not a weather report.
      expect(parseWxMeasurements('doing 12 mph down the highway').windMps, isNull);
      expect(parseWxMeasurements('wind 12 mph').windMps, closeTo(5.36, 0.02));
      expect(parseWxMeasurements('gusting 20 kt').windMps,
          closeTo(10.29, 0.02));
      expect(parseWxMeasurements('windy, 30 km/h').windMps,
          closeTo(8.33, 0.02));
    });

    test('a speed is never read as a temperature', () {
      // The old parser took "12" out of "12 mph" and reported 2.0 °C.
      expect(parseWxMeasurements('temp 23.2 celsius, wind 12 mph').tempsC,
          <double>[23.2]);
      expect(parseWxMeasurements('wind 12 mph').tempsC, isEmpty);
      expect(parseWxMeasurements('40% humidity').tempsC, isEmpty);
      expect(parseWxMeasurements('1013 hPa').tempsC, isEmpty);
    });

    test('bare numbers and out-of-range values are not temperatures', () {
      expect(parseWxMeasurements('meet at 28 by the dock').tempsC, isEmpty);
      expect(parseWxMeasurements('28°C').tempsC, <double>[28]);
      expect(parseWxMeasurements('250°C').tempsC, isEmpty,
          reason: 'not a temperature anyone reports in chat');
    });

    test('nothing measured means nothing reported', () {
      expect(parseWxMeasurements('rain later').isEmpty, isTrue);
      expect(parseWxMeasurements('nice weather').isEmpty, isTrue);
    });

    test('a Fahrenheit report is converted before it is judged', () {
      // The range guard ran before the conversion, so every US reading above
      // 70 was dropped as "not a temperature anyone reports": 95F is 35 C and
      // is the most ordinary summer report there is.
      expect(parseWxMeasurements('95F').tempsC, <double>[35.0]);
      expect(parseWxMeasurements('95 °F').tempsC, <double>[35.0]);
      expect(parseWxMeasurements('90f').tempsC.length, 1);
      expect(parseWxMeasurements('30C').tempsC, <double>[30.0]);
      // And the guard still works after conversion: 250 C is not a report.
      expect(parseWxMeasurements('482F').tempsC, isEmpty);
    });

    test('a temperature is never read as a humidity percentage', () {
      // "hot and humid 95F" reported 95 % relative humidity with no
      // temperature, which is both wrong and the opposite of what was written.
      final WxMeasurements m = parseWxMeasurements('hot and humid 95F');
      expect(m.humidityPct, isNull);
      expect(m.tempsC, <double>[35.0]);
      // A percentage has to be written as one, or the word has to carry it.
      expect(parseWxMeasurements('humid 40').humidityPct, isNull);
      expect(parseWxMeasurements('humid 40 percent').humidityPct, 40);
      expect(parseWxMeasurements('humidity 40%').humidityPct, 40);
      // The abbreviation is its own unit, which is how weather nets read it.
      expect(parseWxMeasurements('rh 62').humidityPct, 62);
      expect(parseWxMeasurements('RH: 45').humidityPct, 45);
    });
  });
}

