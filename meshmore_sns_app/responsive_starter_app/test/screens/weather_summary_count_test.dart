// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/meshcore/node_telemetry.dart';
import 'package:meshmore_sns_app/screens/weather_view.dart';
import 'package:meshcore/meshcore.dart';

/// The temperature band's count and its three figures come from one set.
///
/// It used to be two: the card counted every node whose telemetry carried *any*
/// environment value, and computed min, average and max over the nodes that
/// carried a temperature. A node with humidity and no temperature was therefore
/// counted in "N reporting" and absent from every number under it, so the card
/// stated a count none of its own figures came from (`docs/MISSING-WORK.md`,
/// the weather row of the 2026-11-14 audit).
NodeTelemetry _t({
  double? temperatureC,
  double? humidityPct,
  double? pressureHpa,
  double? luminosity,
}) =>
    NodeTelemetry(
      pubKeyPrefixHex: 'aabbccddeeff',
      receivedAt: DateTime(2026, 11, 15),
      entries: <LppEntry>[],
      temperatureC: temperatureC,
      humidityPct: humidityPct,
      pressureHpa: pressureHpa,
      luminosity: luminosity,
    );

void main() {
  test('a humidity-only node is counted apart, not into the temperature set',
      () {
    final WeatherTemperatureSummary? s = WeatherTemperatureSummary.from(
      <NodeTelemetry>[
        _t(temperatureC: 10),
        _t(temperatureC: 20),
        _t(humidityPct: 61),
      ],
    );

    expect(s, isNotNull);
    // Two nodes carry a temperature, so two numbers are what the three figures
    // are computed over.
    expect(s!.count, 2);
    expect(s.minC, 10);
    expect(s.maxC, 20);
    expect(s.avgC, 15);
    // The one that reported something else is named, not silently dropped.
    expect(s.other, 1);
    // The figure the card states is a figure its own numbers came from.
    expect(s.count, lessThan(s.count + s.other));
  });

  test('every environment value counts as reporting something else', () {
    final WeatherTemperatureSummary? s = WeatherTemperatureSummary.from(
      <NodeTelemetry>[
        _t(temperatureC: 5),
        _t(humidityPct: 40),
        _t(pressureHpa: 1012),
        _t(luminosity: 77),
      ],
    );

    expect(s!.count, 1);
    expect(s.other, 3);
  });

  test('a battery-only node is not reporting environment at all', () {
    // `hasEnvironment` excludes battery: power is not weather. A node that
    // reports only a voltage must not appear in either count.
    final WeatherTemperatureSummary? s = WeatherTemperatureSummary.from(
      <NodeTelemetry>[
        _t(temperatureC: 12),
        NodeTelemetry(
          pubKeyPrefixHex: 'aabbccddeeff',
          receivedAt: DateTime(2026, 11, 15),
          entries: <LppEntry>[],
          batteryVoltageV: 4.1,
        ),
      ],
    );

    expect(s!.count, 1);
    expect(s.other, 0);
  });

  test('no temperature anywhere is no band at all', () {
    final WeatherTemperatureSummary? s = WeatherTemperatureSummary.from(
      <NodeTelemetry>[
        _t(humidityPct: 61),
        _t(pressureHpa: 1004),
      ],
    );

    // Null rather than a band of zero figures: three numbers computed over
    // nothing are not a reading.
    expect(s, isNull);
    expect(WeatherTemperatureSummary.from(<NodeTelemetry>[]), isNull);
  });
}
