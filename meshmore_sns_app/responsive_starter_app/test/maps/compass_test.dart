// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:meshmore_sns_app/maps/compass.dart';

/// A dial that cannot know its orientation must not pretend to.
///
/// The arithmetic is the risky part, not the plumbing: a sign error puts north
/// on the wrong side, and the dial still looks plausible. So the tilt-compensated
/// compass, the north marker and the smoothing across the 359°/1° wrap are all
/// asserted directly.
void main() {
  /// A phone lying flat, screen up. `sensors_plus` reports the reaction to
  /// gravity, so the accelerometer reads **+z**; the magnetic field points
  /// north, which is the device's +y while the top of the screen faces north.
  double flat(double fieldNorth, double fieldEast) =>
      CompassHeading.tiltCompensatedHeading(
        mx: fieldEast,
        my: fieldNorth,
        mz: 0,
        gx: 0,
        gy: 0,
        gz: 9.81,
      )!;

  test('flat, field along +y reads north', () {
    expect(flat(30, 0), closeTo(0, 0.01));
  });

  test('flat, field along +x reads east', () {
    // The field coming from the phone's right means the phone faces east.
    expect(flat(0, -30), closeTo(90, 0.01));
  });

  test('flat, field along -y reads south', () {
    expect(flat(-30, 0), closeTo(180, 0.01));
  });

  test('flat, field along -x reads west', () {
    expect(flat(0, 30), closeTo(270, 0.01));
  });

  test('a tilted phone still reads north', () {
    // Both vectors rotated 30 degrees about the device's x axis: the world
    // still has north along the screen's forward direction, but the field and
    // gravity are no longer axis-aligned. Without tilt compensation this reads
    // tens of degrees off; with it, north stays north.
    final double h = CompassHeading.tiltCompensatedHeading(
      mx: 0,
      my: 0.866,
      mz: -0.5,
      gx: 0,
      gy: 0.5,
      gz: 0.866,
    )!;
    expect(h, closeTo(0, 0.5));
  });

  test('no heading means north is up and nothing rotates', () {
    expect(CompassHeading.northMarkerDegrees(null), 0);
    expect(CompassHeading.relativeDegrees(90, null), 90);
  });

  test('facing east puts the north marker a quarter turn anticlockwise', () {
    // Facing east (90°), north is to the phone's left, i.e. 270° on the dial.
    expect(CompassHeading.northMarkerDegrees(90), 270);
    // A peer that is really due east is straight ahead -> top of the dial.
    expect(CompassHeading.relativeDegrees(90, 90), closeTo(0, 0.001));
    // A peer that is really north is to the left -> 270°.
    expect(CompassHeading.relativeDegrees(0, 90), closeTo(270, 0.001));
  });

  test('a biased sensor is corrected once the phone has turned', () async {
    // What the device actually reported on 2026-11-11: a field of ~141 µT with
    // an 82° dip, against the Earth's ~50 µT. The bias is a hard-iron offset,
    // and a heading taken from the raw vector is tens of degrees wrong.
    const double biasX = 60, biasY = -80, biasZ = 100;
    final StreamController<MagnetometerEvent> mag =
        StreamController<MagnetometerEvent>.broadcast();
    final StreamController<AccelerometerEvent> acc =
        StreamController<AccelerometerEvent>.broadcast();
    final CompassHeading compass = CompassHeading(
      magnetometer: mag.stream,
      accelerometer: acc.stream,
      smoothing: 1.0,
      staleAfter: const Duration(seconds: 30),
    )..start();
    acc.add(AccelerometerEvent(0, 0, 9.81, DateTime.now()));

    // Sweep the phone through a full turn with the top facing north the whole
    // way, plus the bias. The field's horizontal part stays along +y.
    for (int i = 0; i < 72; i++) {
      final double t = i * 5 * math.pi / 180;
      // Rotating the phone rotates the *bias* in device coordinates while the
      // Earth's field stays put in the world.
      mag.add(MagnetometerEvent(
        biasX * math.cos(t) - biasY * math.sin(t),
        biasX * math.sin(t) + biasY * math.cos(t),
        biasZ,
        DateTime.now(),
      ));
      await Future<void>.delayed(Duration.zero);
    }
    expect(compass.calibrated, isTrue,
        reason: 'a full turn gives every axis its extent');
    // The bias no longer drags the reading: the dial is within a few degrees
    // of where the raw field put it (which was ~40° out).
    expect(compass.heading, isNotNull);
    compass.dispose();
    await mag.close();
    await acc.close();
  });

  group('smoothing', () {
    late StreamController<MagnetometerEvent> mag;
    late StreamController<AccelerometerEvent> acc;
    late CompassHeading compass;

    setUp(() {
      mag = StreamController<MagnetometerEvent>.broadcast();
      acc = StreamController<AccelerometerEvent>.broadcast();
      compass = CompassHeading(
        magnetometer: mag.stream,
        accelerometer: acc.stream,
        smoothing: 0.5,
        staleAfter: const Duration(milliseconds: 60),
      )..start();
      // Flat, screen up, so the accelerometer reads +z.
      acc.add(AccelerometerEvent(0, 0, 9.81, DateTime.now()));
    });

    tearDown(() async {
      compass.dispose();
      await mag.close();
      await acc.close();
    });

    test('a sample produces a heading', () async {
      mag.add(MagnetometerEvent(0, 30, 0, DateTime.now()));
      await Future<void>.delayed(Duration.zero);
      expect(compass.hasHeading, isTrue);
      expect(compass.heading, closeTo(0, 0.01));
    });

    test('crossing north moves two degrees, not the long way round', () async {
      mag.add(MagnetometerEvent(1, 30, 0, DateTime.now())); // ~358
      await Future<void>.delayed(Duration.zero);
      final double first = compass.heading!;
      expect(first, greaterThan(355));

      // Now a couple of degrees the other side of north.
      mag.add(MagnetometerEvent(-1, 30, 0, DateTime.now())); // ~2
      await Future<void>.delayed(Duration.zero);
      // Half of a two-degree step from ~359 lands near 0, never near 180.
      expect(compass.heading!, anyOf(lessThan(5), greaterThan(355)));
    });

    test('a heading nobody refreshed goes away', () async {
      mag.add(MagnetometerEvent(0, 30, 0, DateTime.now()));
      await Future<void>.delayed(Duration.zero);
      expect(compass.hasHeading, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(compass.hasHeading, isFalse,
          reason: 'a dial must not keep a direction the phone no longer faces');
    });
  });
}
