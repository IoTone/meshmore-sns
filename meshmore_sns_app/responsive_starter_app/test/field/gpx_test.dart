// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/field/gpx.dart';
import 'package:meshmore_sns_app/field/position_history.dart';
import 'package:meshmore_sns_app/meshcore/own_location.dart';

PositionSample _p(double lat, double lon, DateTime at, {double? alt}) =>
    PositionSample(
      latitude: lat,
      longitude: lon,
      at: at,
      altitudeMeters: alt,
      source: OwnLocationSource.phoneFix,
    );

void main() {
  final DateTime t0 = DateTime.utc(2026, 11, 5, 12, 0, 0);

  test('a track is GPX 1.1 with one segment, in time order', () {
    final String gpx = GpxTrack.encode(
      <PositionSample>[
        _p(51.5002, -0.1202, t0.add(const Duration(minutes: 1))),
        _p(51.5, -0.12, t0),
      ],
      name: 'Morning walk',
      at: t0,
    );
    expect(gpx, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(gpx, contains('xmlns="http://www.topografix.com/GPX/1/1"'));
    expect(gpx, contains('<name>Morning walk</name>'));
    expect(gpx, contains('<trkseg>'));
    // Two points, and the earlier one first.
    expect('<trkpt'.allMatches(gpx).length, 2);
    expect(
      gpx.indexOf('lat="51.500000"'),
      lessThan(gpx.indexOf('lat="51.500200"')),
      reason: 'the sample from t0 is written before the one from t0+1min',
    );
    expect(gpx, contains('2026-11-05T12:00:00.000Z'));
  });

  test('no altitude writes no <ele>, because a zero reads as sea level', () {
    final String gpx = GpxTrack.encode(<PositionSample>[_p(1, 2, t0)], at: t0);
    expect(gpx, isNot(contains('<ele>')));
  });

  test('an altitude is written with one decimal', () {
    final String gpx =
        GpxTrack.encode(<PositionSample>[_p(1, 2, t0, alt: 1234.56)], at: t0);
    expect(gpx, contains('<ele>1234.6</ele>'));
  });

  test('a track name cannot break the document', () {
    final String gpx = GpxTrack.encode(<PositionSample>[_p(1, 2, t0)],
        name: 'A & B <trail>', at: t0);
    expect(gpx, contains('<name>A &amp; B &lt;trail&gt;</name>'));
    expect(gpx, isNot(contains('<trail>')));
  });

  test('an empty trail is still a valid, empty document', () {
    final String gpx = GpxTrack.encode(const <PositionSample>[], at: t0);
    expect('<trkpt'.allMatches(gpx).length, 0);
    expect(gpx.trimRight(), endsWith('</gpx>'));
  });

  test('a local timestamp is written as UTC, with a single Z', () {
    final String gpx = GpxTrack.encode(
      <PositionSample>[
        PositionSample(
          latitude: 1,
          longitude: 2,
          at: DateTime(2026, 11, 5, 12),
          source: OwnLocationSource.phoneFix,
        ),
      ],
      at: t0,
    );
    final String time = RegExp('<time>([^<]+)</time>').allMatches(gpx).last.group(1)!;
    expect(time.endsWith('Z'), isTrue);
    expect(time.endsWith('ZZ'), isFalse);
  });
}
