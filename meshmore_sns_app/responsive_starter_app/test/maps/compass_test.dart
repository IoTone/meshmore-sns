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
/// on the wrong side, and the dial still looks plausible. So every case here is
/// a *bearing* asserted against a known rotation, including the one the owner
/// reported: turning a phone flat on a desk 30° must read 30°, not 60° and not
/// "somewhere else", on a handset whose magnetometer carries a large vertical
/// offset.
/// The shorter way round between two bearings, in degrees (0..180).
double apart(double a, double b) {
  double d = (a - b) % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d.abs();
}

void main() {
  /// A phone flat on a desk, screen up, with the Earth's field along north at
  /// 20 µT horizontal and 46 µT down — Denver's, which is where the reported
  /// fault was measured. The top of the screen faces [facing] degrees clockwise
  /// from north.
  ///
  /// Device axes: x right, y up-the-screen, z out of the screen (so up, when
  /// the phone is flat).
  ({double x, double y, double z}) fieldAt(double facing) {
    // The world's north, expressed in device coordinates.
    final double t = facing * math.pi / 180;
    final double northX = -math.sin(t);
    final double northY = math.cos(t);
    // East = north rotated 90° clockwise, so it points along device x for a
    // north-facing phone.
    final double eastX = math.cos(t);
    final double eastY = math.sin(t);
    const double h = 20.0, down = 46.0;
    return (
      x: northX * h + eastX * 0,
      y: northY * h + eastY * 0,
      z: -down,
    );
  }

  /// The same, with the hard-iron offset the handset in the fault report has:
  /// ~154 µT on z and a little on the horizontal pair, fixed in the *device*
  /// frame, so it stays put while the Earth's field turns underneath it.
  ({double x, double y, double z}) biasedFieldAt(double facing) {
    final ({double x, double y, double z}) f = fieldAt(facing);
    return (x: f.x + 7.3, y: f.y + 0.8, z: f.z - 108.0);
  }

  group('the flat bearing', () {
    test('a phone facing north reads north', () {
      expect(CompassHeading.flatHeading(0, 30), closeTo(0, 0.01));
    });

    test('facing each cardinal reads that cardinal', () {
      expect(CompassHeading.flatHeading(-30, 0), closeTo(90, 0.01));
      expect(CompassHeading.flatHeading(0, -30), closeTo(180, 0.01));
      expect(CompassHeading.flatHeading(30, 0), closeTo(270, 0.01));
    });

    test('a vertical offset cannot move it, at any angle', () {
      for (int deg = 0; deg < 360; deg += 15) {
        final ({double x, double y, double z}) clean = fieldAt(deg.toDouble());
        // The measured handset: 108 µT of bias, all of it on z. The flat
        // bearing takes only the horizontal pair, so it cannot see it.
        final ({double x, double y, double z}) biased =
            (x: clean.x, y: clean.y, z: clean.z - 108);
        expect(CompassHeading.flatHeading(biased.x, biased.y),
            closeTo(CompassHeading.flatHeading(clean.x, clean.y), 0.001));
      }
    });

    test('the circle fit recovers a horizontal offset the box could not', () {
      // A hard-iron offset in the horizontal plane is what a box centre gets
      // wrong: at the top of a sweep the box centre is the arc's chord, not the
      // circle's. A full turn is enough for the fit, and the recovered centre
      // takes the bearing from tens of degrees out to a couple.
      const double ox = 12, oy = -9, r = 20;
      final List<({double x, double y})> pts = <({double x, double y})>[];
      for (int deg = 0; deg < 360; deg += 6) {
        final double t = deg * math.pi / 180;
        pts.add((x: ox + r * math.sin(t), y: oy + r * math.cos(t)));
      }
      final ({double x, double y, double r, double rms})? fit =
          CompassHeading.fitCircle(pts);
      expect(fit, isNotNull);
      expect(fit!.x, closeTo(ox, 0.5));
      expect(fit.y, closeTo(oy, 0.5));
      expect(fit.r, closeTo(r, 0.5));
      // The bearing of a field seen at -34.4° from the phone's forward axis is
      // 34.4°. With the fit's centre subtracted it reads that; raw it is out by
      // the offset's own angle.
      final ({double x, double y}) sample =
          (x: ox + r * math.sin(-0.6), y: oy + r * math.cos(-0.6));
      final double corrected =
          CompassHeading.flatHeading(sample.x - fit.x, sample.y - fit.y);
      final double raw = CompassHeading.flatHeading(sample.x, sample.y);
      expect(apart(corrected, 34.4), lessThan(1.0));
      expect(apart(raw, 34.4), greaterThan(8),
          reason: 'the offset this phone has really does move the bearing');
    });

    test('a short, noisy arc is rejected by the gate', () {
      // Real samples have noise, and noise on a 40° arc leaves the circle
      // radius unconstrained: the fit walks off to a huge circle, which the
      // r <= 90 µT test refuses. That is the case a phone that has only been
      // nudged produces, and it must not be trusted as a calibration.
      const double ox = 12, oy = -9, r = 20;
      final List<({double x, double y})> pts = <({double x, double y})>[];
      for (int deg = 0; deg <= 40; deg += 2) {
        final double t = deg * math.pi / 180;
        final double jitter = (deg % 4 == 0) ? 1.2 : -1.2;
        pts.add(
            (x: ox + r * math.sin(t) + jitter, y: oy + r * math.cos(t) - jitter));
      }
      final ({double x, double y, double r, double rms})? fit =
          CompassHeading.fitCircle(pts);
      final bool trusted = fit != null &&
          fit.r >= 5 &&
          fit.r <= 90 &&
          fit.rms <= fit.r * 0.15;
      expect(trusted, isFalse,
          reason: 'a short noisy arc must not be mistaken for a calibration');
    });
  });

  group('tracking a turn', () {
    late StreamController<MagnetometerEvent> mag;
    late StreamController<AccelerometerEvent> acc;
    late StreamController<GyroscopeEvent> gyro;
    late CompassHeading compass;
    late DateTime clock;

    setUp(() {
      mag = StreamController<MagnetometerEvent>.broadcast();
      acc = StreamController<AccelerometerEvent>.broadcast();
      gyro = StreamController<GyroscopeEvent>.broadcast();
      compass = CompassHeading(
        magnetometer: mag.stream,
        accelerometer: acc.stream,
        gyroscope: gyro.stream,
        staleAfter: const Duration(seconds: 30),
      )..start();
      clock = DateTime(2026, 11, 11, 23, 59);
      // Flat on the desk: screen up, so the accelerometer reads +z.
      acc.add(AccelerometerEvent(0, 0, 9.81, clock));
    });

    tearDown(() async {
      compass.dispose();
      await mag.close();
      await acc.close();
      await gyro.close();
    });

    /// Turn the phone by [deg] over [steps] gyroscope samples of 20 ms.
    ///
    /// A clockwise turn raises the bearing, which is a negative rate about the
    /// world's up axis.
    Future<void> turn(double deg, {int steps = 30}) async {
      final double perStep = deg / steps;
      for (int i = 0; i < steps; i++) {
        clock = clock.add(const Duration(milliseconds: 20));
        final double ratePerSec = -perStep / 0.020;
        gyro.add(GyroscopeEvent(
            0, 0, ratePerSec * math.pi / 180, clock));
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('a flat turn of 30° reads 30°', () async {
      mag.add(MagnetometerEvent(0, 20, -46, clock));
      await Future<void>.delayed(Duration.zero);
      expect(compass.heading, closeTo(0, 0.5));

      await turn(30);
      expect(apart(compass.heading!, 30), lessThan(1.5),
          reason: 'degree for degree: this is the reported fault');
      // And it keeps going: a second 30 is 60, not something else.
      await turn(30);
      expect(apart(compass.heading!, 60), lessThan(1.5));
    });

    test('turning back returns to the same reading', () async {
      mag.add(MagnetometerEvent(0, 20, -46, clock));
      await Future<void>.delayed(Duration.zero);
      await turn(40);
      await turn(-40);
      expect(apart(compass.heading!, 0), lessThan(1.5),
          reason: 'the old tilt-compensated path did not come back');
    });

    test('a turn across north wraps instead of unwinding', () async {
      mag.add(MagnetometerEvent(0, 20, -46, clock));
      await Future<void>.delayed(Duration.zero);
      await turn(-20); // 340
      expect(apart(compass.heading!, 340), lessThan(1.5));
    });

    test('a tilted phone still tracks the turn', () async {
      // Held at about 45°: the accelerometer leans, so the up axis is not the
      // device's +z. The yaw rate is taken along that axis, so a turn about the
      // world's vertical still reads degree for degree.
      acc.add(AccelerometerEvent(0, 6.94, 6.94, clock));
      mag.add(MagnetometerEvent(0, 20, -46, clock));
      await Future<void>.delayed(Duration.zero);
      final double? before = compass.heading;
      // The gyroscope reports the same world rotation, expressed in device axes
      // that now lean: its component along up is 0.707 of the z rate.
      for (int i = 0; i < 30; i++) {
        clock = clock.add(const Duration(milliseconds: 20));
        const double perStep = 20 / 30; // 20 degrees total
        final double rate = -(perStep / 0.020) * math.pi / 180;
        gyro.add(GyroscopeEvent(0, rate * 0.707, rate * 0.707, clock));
        await Future<void>.delayed(Duration.zero);
      }
      expect((compass.heading! - before!) % 360, closeTo(20, 2),
          reason: 'a leaned phone turns the dial by the angle it was turned');
    });

    /// Turn the phone through [deg] with both sensors agreeing about the turn,
    /// so the magnetometer sees the circle the fit needs.
    Future<void> sweep(double deg, {int steps = 80}) async {
      final double perStep = deg / steps;
      for (int i = 0; i < steps; i++) {
        clock = clock.add(const Duration(milliseconds: 20));
        final double rate = -(perStep / 0.020) * math.pi / 180;
        gyro.add(GyroscopeEvent(0, 0, rate, clock));
        final ({double x, double y, double z}) f =
            biasedFieldAt((i + 1) * perStep);
        mag.add(MagnetometerEvent(f.x, f.y, f.z, clock));
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('a turn through a full circle calibrates the offset', () async {
      mag.add(MagnetometerEvent(0, 20, -46, clock));
      await Future<void>.delayed(Duration.zero);
      expect(compass.calibratedCircle, isFalse,
          reason: 'a phone that has not turned cannot be calibrated');
      await sweep(360);
      expect(compass.calibratedCircle, isTrue,
          reason: 'the field has described a circle of Earth-like radius');
    });

    test('with a calibrated offset the field wins again', () async {
      mag.add(MagnetometerEvent(0, 20, -46, clock));
      await Future<void>.delayed(Duration.zero);
      await sweep(360);
      expect(compass.calibratedCircle, isTrue);
      // Now stand still facing north with the offset present: the anchor should
      // pull the bearing to the *corrected* one, which is north.
      for (int i = 0; i < 40; i++) {
        clock = clock.add(const Duration(milliseconds: 100));
        final ({double x, double y, double z}) f = biasedFieldAt(0);
        mag.add(MagnetometerEvent(f.x, f.y, f.z, clock));
        await Future<void>.delayed(Duration.zero);
      }
      expect(apart(compass.heading!, 0), lessThan(12),
          reason: 'the absolute bearing wins once the phone is flat again');
    });

    test('an unusable field never anchors the heading', () async {
      // A plausible field first, so there is a track worth protecting, then the
      // kind of reading this handset produces: 157 µT with most of it on z. A
      // bearing taken from that can be the opposite direction, so it may not
      // drag the gyroscope track anywhere.
      mag.add(MagnetometerEvent(0, 20, -46, clock));
      await Future<void>.delayed(Duration.zero);
      await turn(20);
      final double afterTurn = compass.heading!;
      for (int i = 0; i < 20; i++) {
        clock = clock.add(const Duration(milliseconds: 100));
        mag.add(MagnetometerEvent(-24, 6, -154, clock));
        await Future<void>.delayed(Duration.zero);
      }
      expect(apart(compass.heading!, afterTurn), lessThan(3),
          reason: 'a 157 µT field is not a bearing, so it anchors nothing');
    });

  });

  test('a heading with no anchor for a staleness window goes away', () async {
    final StreamController<MagnetometerEvent> mag =
        StreamController<MagnetometerEvent>.broadcast();
    final StreamController<AccelerometerEvent> acc =
        StreamController<AccelerometerEvent>.broadcast();
    final StreamController<GyroscopeEvent> gyro =
        StreamController<GyroscopeEvent>.broadcast();
    final CompassHeading compass = CompassHeading(
      magnetometer: mag.stream,
      accelerometer: acc.stream,
      gyroscope: gyro.stream,
      staleAfter: const Duration(milliseconds: 60),
    )..start();
    final DateTime now = DateTime(2026, 11, 11, 23, 59);
    acc.add(AccelerometerEvent(0, 0, 9.81, now));
    mag.add(MagnetometerEvent(0, 20, -46, now));
    await Future<void>.delayed(Duration.zero);
    expect(compass.hasHeading, isTrue);

    // Real elapsed time, because the staleness timer is a wall clock and a
    // widget test's fake clock would never reach it.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(compass.hasHeading, isFalse,
        reason: 'a dial must not keep a direction the phone no longer faces');
    compass.dispose();
    await mag.close();
    await acc.close();
    await gyro.close();
  });

  group('the platform compass', () {
    test('a good reading is adopted as-is', () async {
      final StreamController<CompassReading> platform =
          StreamController<CompassReading>.broadcast();
      final CompassHeading compass = CompassHeading(
        platform: platform.stream,
        staleAfter: const Duration(seconds: 30),
      )..start();
      platform.add(const CompassReading(heading: 137.5, accuracy: 15));
      await Future<void>.delayed(Duration.zero);
      expect(compass.heading, closeTo(137.5, 0.001));
      expect(compass.needsCalibration, isFalse);
      compass.dispose();
      await platform.close();
    });

    test('an unreliable reading is not drawn', () async {
      // The OS says its magnetometer is uncalibrated: a dial drawn from it is a
      // guess with a confident face, which is exactly the reported fault.
      final StreamController<CompassReading> platform =
          StreamController<CompassReading>.broadcast();
      final CompassHeading compass = CompassHeading(
        platform: platform.stream,
        staleAfter: const Duration(seconds: 30),
      )..start();
      platform.add(const CompassReading(heading: 10, accuracy: 15));
      await Future<void>.delayed(Duration.zero);
      expect(compass.heading, closeTo(10, 0.001));
      platform.add(const CompassReading(heading: 200, accuracy: -1));
      await Future<void>.delayed(Duration.zero);
      expect(compass.needsCalibration, isTrue);
      expect(compass.heading, closeTo(10, 0.001),
          reason: 'the last good direction is held, not replaced by a guess');
      compass.dispose();
      await platform.close();
    });
  });

  group('a field that cannot be believed', () {
    test('a 157 µT reading starts no dial and anchors none', () async {
      final StreamController<MagnetometerEvent> mag =
          StreamController<MagnetometerEvent>.broadcast();
      final StreamController<AccelerometerEvent> acc =
          StreamController<AccelerometerEvent>.broadcast();
      final StreamController<GyroscopeEvent> gyro =
          StreamController<GyroscopeEvent>.broadcast();
      final CompassHeading compass = CompassHeading(
        magnetometer: mag.stream,
        accelerometer: acc.stream,
        gyroscope: gyro.stream,
        staleAfter: const Duration(seconds: 30),
      )..start();
      final DateTime now = DateTime(2026, 11, 12, 0, 30);
      acc.add(AccelerometerEvent(0, 0, 9.81, now));
      mag.add(MagnetometerEvent(3.6, 2.1, -157.8, now));
      await Future<void>.delayed(Duration.zero);
      expect(compass.fieldTrusted, isFalse);
      expect(compass.disturbed, isTrue);
      expect(compass.hasHeading, isFalse,
          reason: 'north-up is the honest dial when the field is 3x the Earth');
      compass.dispose();
      await mag.close();
      await acc.close();
      await gyro.close();
    });

    test('a plausible field is believed straight away', () async {
      final StreamController<MagnetometerEvent> mag =
          StreamController<MagnetometerEvent>.broadcast();
      final StreamController<AccelerometerEvent> acc =
          StreamController<AccelerometerEvent>.broadcast();
      final StreamController<GyroscopeEvent> gyro =
          StreamController<GyroscopeEvent>.broadcast();
      final CompassHeading compass = CompassHeading(
        magnetometer: mag.stream,
        accelerometer: acc.stream,
        gyroscope: gyro.stream,
      )..start();
      final DateTime now = DateTime(2026, 11, 12, 0, 30);
      acc.add(AccelerometerEvent(0, 0, 9.81, now));
      mag.add(MagnetometerEvent(0, 20, -46, now));
      await Future<void>.delayed(Duration.zero);
      expect(compass.fieldTrusted, isTrue);
      expect(compass.hasHeading, isTrue);
      expect(apart(compass.heading!, 0), lessThan(1));
      compass.dispose();
      await mag.close();
      await acc.close();
      await gyro.close();
    });
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

  group('the tilt formula, for a calibrated sensor', () {
    // Kept because it seeds the first bearing on a phone that is already
    // tilted, and because it is the whole answer on a device with no
    // gyroscope. It is not used to track a turn: see the class comment.
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

    test('a tilted phone still reads north', () {
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
  });
}
