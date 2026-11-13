// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:provider/provider.dart';
import 'package:flutter/painting.dart' show Canvas, Color, Offset, Paint, PaintingStyle, Path;
import 'package:sensors_plus/sensors_plus.dart';

/// The heading implied by a fused rotation vector, for the direction the
/// *screen* faces.
///
/// [qx]..[qw] is Android's `TYPE_ROTATION_VECTOR` quaternion and [displayRotation]
/// is `Surface.ROTATION_0/90/180/270`. Both are raw platform facts; the heading is
/// computed here rather than by `SensorManager.getOrientation` because the
/// azimuth that function returns is the rotation about *one chosen axis*, and
/// which axis is right depends on how the phone is held. Android's sample swaps
/// that axis at ±45° of pitch, and on a phone that is neither flat nor upright —
/// the way a phone is actually held — the reading jumps between two frames.
///
/// This is a projection instead, so it is continuous in the tilt:
///
///  * the rotation matrix says where the screen's own axes point in the world
///    (east, north, up),
///  * flat, the direction a reader means is the screen's **up** axis; upright, it
///    is the screen's **-out** axis (where the back of the phone points, i.e.
///    where you are facing),
///  * the two are mixed by how flat the phone is, and the bearing of the result
///    is the answer.
///
/// Both vectors are well-conditioned in their own regime, the mix is continuous,
/// and every case is asserted in `test/maps/compass_test.dart` against a known
/// attitude rather than against a plausible-looking number.
double headingFromRotation({
  required double qx,
  required double qy,
  required double qz,
  required double qw,
  required int displayRotation,
}) {
  // Rotation matrix, device → world (east, north, up), row-major.
  final double x2 = qx + qx, y2 = qy + qy, z2 = qz + qz;
  final double xx = qx * x2, xy = qx * y2, xz = qx * z2;
  final double yy = qy * y2, yz = qy * z2, zz = qz * z2;
  final double wx = qw * x2, wy = qw * y2, wz = qw * z2;
  final List<double> r = <double>[
    1 - (yy + zz), xy - wz, xz + wy, //
    xy + wz, 1 - (xx + zz), yz - wx, //
    xz - wy, yz + wx, 1 - (xx + yy), //
  ];
  // Apply R to a device axis: the world components are R * v.
  (double e, double n, double u) apply(double vx, double vy, double vz) => (
        r[0] * vx + r[1] * vy + r[2] * vz,
        r[3] * vx + r[4] * vy + r[5] * vz,
        r[6] * vx + r[7] * vy + r[8] * vz,
      );

  // The screen's own axes, in device coordinates. The screen's out axis is the
  // device's +z whatever the rotation; its up axis follows the display.
  final (double ux, double uy) screenUp = switch (displayRotation) {
    1 => (1, 0), // ROTATION_90: the screen's top is the device's +x
    2 => (0, -1), // ROTATION_180
    3 => (-1, 0), // ROTATION_270
    _ => (0, 1), // ROTATION_0
  };
  final (double e1, double n1, double u1) = apply(screenUp.$1, screenUp.$2, 0);
  final (double e2, double n2, double u2) = apply(0, 0, 1);

  // 1 flat screen-up, 0 upright.
  final double flat = u2.abs().clamp(0.0, 1.0);
  // Screen up when flat, and the opposite of "out of the screen" when upright.
  final double fe = e1 * flat + (-e2) * (1 - flat);
  final double fn = n1 * flat + (-n2) * (1 - flat);
  if (fe == 0 && fn == 0) {
    // Screen vertical and edge-on: nothing to project. Keep the last heading by
    // reporting north, which every caller treats as "no better answer".
    return 0;
  }
  double deg = math.atan2(fe, fn) * 180 / math.pi;
  if (deg < 0) deg += 360;
  return deg;
}

/// One reading from the platform's fused orientation sensor.
@immutable
class CompassReading {
  const CompassReading({
    required this.qx,
    required this.qy,
    required this.qz,
    required this.qw,
    required this.displayRotation,
    required this.accuracy,
  });

  final double qx;
  final double qy;
  final double qz;
  final double qw;
  final int displayRotation;

  /// The direction the screen faces, in degrees clockwise from magnetic north.
  double get heading => headingFromRotation(
        qx: qx,
        qy: qy,
        qz: qz,
        qw: qw,
        displayRotation: displayRotation,
      );

  /// The OS's own accuracy figure in degrees, or −1 when it will not say
  /// (which is what an uncalibrated magnetometer reports).
  final int accuracy;

  /// Android's accuracy figures: 15 high, 30 medium, 45 low, −1 unreliable.
  /// Anything worse than 45 means the phone itself is asking for calibration,
  /// and a dial drawn from it is a guess with a confident face.
  bool get usable => accuracy >= 0 && accuracy <= 45;
}

/// Which way the phone is pointing, so a dial can draw the world the right way
/// round.
///
/// Both the hyperlocal radar and the grid's radar plot peers by *bearing*: a
/// repeater to your east belongs on the right of the rings. That is only true
/// while the phone is held facing north. Held facing east, a north-up dial puts
/// every peer a quarter turn away from where the antenna actually is, which is
/// worse than no dial at all — it looks authoritative and is wrong.
///
/// **Why this is not a magnetometer reading with a tilt correction.** The phone
/// this was measured on reads a magnetic field of ~157 µT where the Earth's is
/// about 50, with the excess almost entirely on **z**: `mag=(27.3, 0.8, −154.3)`
/// from `logcat` on 2026-11-11. That is a hard-iron offset fixed in the *device*
/// frame, so it turns with the phone while the Earth's field does not. Feeding it
/// through a tilt-compensated formula — which assumes the vector it is handed is
/// the Earth's field — makes the computed bearing a nonlinear function of the
/// real one: on that handset a small turn swung the dial tens of degrees, and it
/// did not return to the same reading when the phone was turned back. That is the
/// reported fault, and no amount of averaging fixes it, because the error is in
/// the geometry rather than in the noise.
///
/// So the heading comes from two sources with different jobs:
///
///   * **The gyroscope integrates the turn.** Rotating about the *world* vertical
///     is exactly a change of heading, and the gyroscope measures that rate
///     directly, smoothly and without a magnetic bias. Its component along the
///     measured up axis is the yaw rate, in any orientation, so a phone held at
///     an angle turns the dial by the same angle it was turned.
///   * **The magnetometer anchors it, only when the phone is near flat.** Flat,
///     the bearing is `atan2(−mx, my)`: the horizontal pair only. A vertical
///     offset — which is what this handset has — cannot reach it at all, and a
///     horizontal one shifts it by a constant instead of warping it with the
///     rotation. Anchoring is a slow correction towards that bearing, so the dial
///     reads degree for degree while the phone turns and never drifts away.
///
/// Tilted, there is no trustworthy absolute bearing: tilt compensation needs the
/// dip, and the dip is the part the offset ruins. The gyroscope still integrates
/// the rotation correctly, and the next moment the phone is flat again the
/// magnetometer re-anchors it. A dial that cannot know north does not claim it:
/// with no anchor for [staleAfter] the heading is dropped and every dial draws
/// north-up.
///
/// **Magnetic north.** The magnetometer reports the field, not the meridian, and
/// the difference (declination) varies by roughly ±20° over the planet. The dial
/// therefore calls the red marker north in the magnetic sense, which is what every
/// hand compass does when it has not been told where it is.
class CompassHeading extends ChangeNotifier {
  CompassHeading({
    Stream<MagnetometerEvent>? magnetometer,
    Stream<AccelerometerEvent>? accelerometer,
    Stream<GyroscopeEvent>? gyroscope,
    Stream<CompassReading>? platform,
    this.staleAfter = const Duration(seconds: 3),
    this.anchorGain = 2.0,
    this.flatCosine = 0.90,
  })  : _mag = magnetometer,
        _acc = accelerometer,
        _gyro = gyroscope,
        _platform = platform;

  /// The platform channel the app's Android build answers with the OS's fused
  /// rotation vector.
  static const EventChannel platformChannel = EventChannel('meshmore/compass');

  /// The OS's own compass, when the platform has one.
  ///
  /// This is the first choice and the hand-rolled path below is the fallback.
  /// Sensor fusion is something a platform does better than an app: it has the
  /// gyroscope, the accelerometer and the magnetometer already combined, and the
  /// factory magnetometer calibration already applied, and it reports the
  /// accuracy it has. Doing it by hand here was measurably wrong on a handset
  /// whose field reads 157 µT where the Earth's is about 50.
  final Stream<CompassReading>? _platform;
  StreamSubscription<CompassReading>? _platformSub;

  /// Injected in tests. Null means "subscribe from `sensors_plus`", which is
  /// what the app does; a test passes controllers it can drive.
  final Stream<MagnetometerEvent>? _mag;
  final Stream<AccelerometerEvent>? _acc;
  final Stream<GyroscopeEvent>? _gyro;

  /// A heading with no anchor newer than this is not trusted. Phones that stop
  /// delivering samples (screen off, sensor throttled) would otherwise leave a
  /// dial rotated to a direction the phone no longer faces.
  final Duration staleAfter;

  /// How hard a flat magnetometer reading pulls the heading towards itself, per
  /// second. High enough to re-anchor a gyroscope that has drifted for a few
  /// seconds, low enough that a single noisy sample cannot swing the dial.
  final double anchorGain;

  /// How flat counts as flat: the cosine between the screen normal and the
  /// world's up axis. 0.90 is about 26° of tilt, which is the angle past which
  /// a hand-held compass is being read off the top of the screen rather than
  /// looked down at.
  final double flatCosine;

  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  Timer? _stale;

  double? _heading;

  /// World "up" in device coordinates: the accelerometer, normalised. For a
  /// phone lying flat and screen-up this is the device's +z.
  ({double x, double y, double z})? _up;

  int _lastGyroMs = 0;
  int _lastMagMs = 0;

  /// Degrees clockwise from magnetic north, or null when nothing is known.
  ///
  /// Null is the important case: no sensor, no permission, or a heading that has
  /// not been anchored for [staleAfter]. Every caller must draw north-up for
  /// null.
  double? get heading => _heading;

  /// Whether the dial should rotate at all.
  bool get hasHeading => _heading != null;

  /// Whether the last anchor was flat and recent enough to be believed as an
  /// absolute bearing, rather than a gyroscope integration.
  bool get anchored => _anchoredAt != 0 &&
      DateTime.now().millisecondsSinceEpoch - _anchoredAt <
          staleAfter.inMilliseconds;

  int _anchoredAt = 0;

  /// How much of the last reading was an absolute bearing rather than a turn.
  /// Exposed for tests: the reported fault is a *bearing*, so the tests assert
  /// that a turn of 30° reads 30° and nothing else.
  bool get _flatNow {
    final ({double x, double y, double z})? up = _up;
    if (up == null) return false;
    // The screen normal is the device's +z; its dot product with world up is
    // just the z component of the normalised accelerometer.
    return up.z.abs() >= flatCosine;
  }

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    // Injected streams mean "use these": that is what a test does, and what a
    // platform without the channel gets. Otherwise, on Android, the OS's own
    // fused sensor is the answer.
    final bool usePlatform = _platform != null ||
        (_mag == null &&
            _acc == null &&
            _gyro == null &&
            defaultTargetPlatform == TargetPlatform.android);
    if (usePlatform) {
      final Stream<CompassReading> stream = _platform ??
          platformChannel.receiveBroadcastStream().map((Object? event) {
            final Map<Object?, Object?> m = event! as Map<Object?, Object?>;
            return CompassReading(
              qx: (m['qx']! as num).toDouble(),
              qy: (m['qy']! as num).toDouble(),
              qz: (m['qz']! as num).toDouble(),
              qw: (m['qw']! as num).toDouble(),
              displayRotation: (m['rotation']! as num).toInt(),
              accuracy: (m['accuracy']! as num).toInt(),
            );
          });
      _platformSub = stream.listen(_onPlatform,
          onError: (Object _) {
            // No fused sensor on this device: fall back to the sensors below.
            if (!_platformUnavailable) {
              _platformUnavailable = true;
              _startSensors();
            }
          },
          cancelOnError: false);
      return;
    }
    _startSensors();
  }

  bool _platformUnavailable = false;

  void _startSensors() {
    final Stream<MagnetometerEvent> mag = _mag ??
        magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval);
    final Stream<AccelerometerEvent> acc = _acc ??
        accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval);
    _magSub = mag.listen(_onMag, onError: (Object _) {}, cancelOnError: false);
    _accSub = acc.listen(_onAcc, onError: (Object _) {}, cancelOnError: false);
    // The gyroscope is the responsive half. A device without one still gets a
    // magnetometer heading, which is correct while flat and coarse while
    // tilted; it is the case the tilt formula below exists for.
    final Stream<GyroscopeEvent> gyro = _gyro ??
        gyroscopeEventStream(samplingPeriod: SensorInterval.uiInterval);
    _gyroSub =
        gyro.listen(_onGyro, onError: (Object _) {}, cancelOnError: false);
  }

  /// A reading from the platform's fused sensor.
  ///
  /// The OS has fused, calibrated and tilt-compensated this already, so it is
  /// taken as the heading rather than feeding any arithmetic here. What is added
  /// is the one thing a raw reading cannot say: the accuracy. A phone that
  /// reports "unreliable" is asking to be calibrated, and a dial must not draw a
  /// confident arrow from a reading the sensor itself does not believe.
  void _onPlatform(CompassReading r) {
    _platformReadings++;
    _platformAccuracy = r.accuracy;
    if (!r.usable) {
      // Held, not adopted: the last good direction is better than a wrong one,
      // and the staleness timer drops it if the sensor never recovers.
      return;
    }
    _set(_wrap(r.heading));
    _anchoredAt = DateTime.now().millisecondsSinceEpoch;
    _touch();
  }

  int _platformAccuracy = -1;

  /// Whether the OS says its own compass cannot be trusted right now.
  ///
  /// Only meaningful once a reading has arrived: a compass that has not spoken
  /// yet is *unknown*, not uncalibrated, and saying "the field is too strong"
  /// before the first sample is a claim the app cannot make.
  bool get needsCalibration =>
      _platformReadings > 0 &&
      (_platformAccuracy < 0 || _platformAccuracy > 45);

  int _platformReadings = 0;

  void _onAcc(AccelerometerEvent e) {
    final double n = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (n == 0) return;
    _up = (x: e.x / n, y: e.y / n, z: e.z / n);
    // The very first reading can seed an absolute bearing without waiting for a
    // turn, so a phone that is already held still still says which way it faces.
    if (_heading == null) _seedFromMagnetometer();
  }

  void _onGyro(GyroscopeEvent e) {
    final ({double x, double y, double z})? up = _up;
    final double? heading = _heading;
    final int ms = e.timestamp.millisecondsSinceEpoch;
    final int last = _lastGyroMs;
    _lastGyroMs = ms;
    if (up == null || heading == null || last == 0) return;
    final double dt = (ms - last) / 1000.0;
    // A gap is not an integration step: the phone may have been turned while
    // nothing was listening, and integrating across it would invent the turning.
    if (dt <= 0 || dt > 0.25) return;
    // The rate about the world's vertical axis, in degrees per second. Turning
    // clockwise raises the bearing, which is a *negative* rotation about up in
    // the right-handed device frame.
    final double rate =
        -(e.x * up.x + e.y * up.y + e.z * up.z) * 180 / math.pi;
    _set(_wrap(heading + rate * dt));
    // Sensors are alive, so the direction is one the phone is still facing.
    _touch();
  }

  void _onMag(MagnetometerEvent e) {
    _lastMagEvent = e;
    final int ms = e.timestamp.millisecondsSinceEpoch;
    final int last = _lastMagMs;
    _lastMagMs = ms;

    // Flat samples are collected whether or not there is a heading yet, because
    // collecting them is how a 157 µT field stops being unusable: a turn
    // measures the offset, and the corrected pair is trustworthy even when the
    // raw one is not. Gating this behind "we already have a heading" deadlocks —
    // no heading without a trusted field, no trusted field without a turn.
    if (_flatNow) _accumulate(e.x, e.y);

    if (_heading == null) {
      _seedFromMagnetometer();
      return;
    }
    // The anchor is the flat bearing, and it is only an anchor while the phone
    // is flat: tilted, the horizontal pair is not the horizontal field.
    if (!_flatNow) {
      _touch();
      return;
    }
    if (!fieldTrusted) {
      // A field of three times the Earth's is not a bearing. Leave the
      // gyroscope track alone and let it carry the rotation.
      _touch();
      return;
    }
    final double hx = e.x - _offset.x;
    final double hy = e.y - _offset.y;
    // A horizontal field this small is two large vectors nearly cancelling, and
    // its angle is noise.
    if (hx * hx + hy * hy < 64) {
      _touch();
      return;
    }
    final double target = flatHeading(hx, hy);
    final double dt = last == 0 ? 0 : (ms - last) / 1000.0;
    final double step = (anchorGain * (dt <= 0 ? 0.02 : dt.clamp(0.0, 0.25)))
        .clamp(0.0, 0.5);
    _set(_wrap(_heading! + _shortestDelta(_heading!, target) * step));
    _anchoredAt = DateTime.now().millisecondsSinceEpoch;
    _touch();
  }

  /// The first bearing of a session, from whatever the sensors can support.
  void _seedFromMagnetometer() {
    final MagnetometerEvent? m = _lastMagEvent;
    if (m == null) return;
    // A 157 µT reading is not the Earth's field, and a dial started from it
    // points wherever the phone's own magnet happens to be. No heading is the
    // honest answer until the field is plausible or a turn has measured the
    // offset.
    if (!fieldTrusted) return;
    final double seed;
    if (_flatNow) {
      _accumulate(m.x, m.y);
      seed = flatHeading(m.x - _offset.x, m.y - _offset.y);
    } else {
      final ({double x, double y, double z})? up = _up;
      if (up == null) return;
      final double? tilted = tiltCompensatedHeading(
        mx: m.x,
        my: m.y,
        mz: m.z,
        // The accelerometer is the reaction to gravity, so it already points
        // along world up; passing it as the gravity vector is the same frame
        // the sensor fusion uses.
        gx: up.x,
        gy: up.y,
        gz: up.z,
      );
      if (tilted == null) return;
      seed = tilted;
    }
    _set(_wrap(seed));
    _anchoredAt = DateTime.now().millisecondsSinceEpoch;
    _touch();
  }

  MagnetometerEvent? _lastMagEvent;

  /// The horizontal field samples seen while the phone was flat, for the
  /// hard-iron fit below. A ring: the field in a new place is a new problem, so
  /// the fit always describes where the phone is now.
  final List<({double x, double y})> _fitPoints = <({double x, double y})>[];

  /// The accepted horizontal offset. Zero until a fit is good enough to trust.
  ({double x, double y}) _offset = (x: 0, y: 0);
  int _sinceFit = 0;

  /// A hard-iron offset rotates with the *phone*, so on a flat turn the field
  /// sweeps a circle whose centre is the offset and whose radius is the Earth's
  /// horizontal component. The centre is what the bearing needs removed, and a
  /// least-squares circle fit recovers it — unlike a min/max box, which is only
  /// the centre when the sweep happens to be a full turn and wastes the reading
  /// entirely when it is not. `calibratedCircle` is the gate: a partial arc, or
  /// points that do not lie on a circle, are rejected rather than applied.
  static const int _fitWindow = 240;
  static const int _fitMinPoints = 48;

  void _accumulate(double x, double y) {
    _fitPoints.add((x: x, y: y));
    if (_fitPoints.length > _fitWindow) _fitPoints.removeAt(0);
    _sinceFit++;
    if (_sinceFit < 20 || _fitPoints.length < _fitMinPoints) return;
    _sinceFit = 0;
    final ({double x, double y, double r, double rms})? fit = fitCircle(_fitPoints);
    if (fit == null) return;
    // Accepted only when it describes the Earth's horizontal field. Measured on
    // the handset: a phone sitting still gives a "circle" of radius 0.1 µT, and
    // accepting that subtracts the whole horizontal field and leaves noise —
    // which is exactly the flapping dial the gate exists to prevent.
    if (!_trusted(fit)) return;
    _offset = (x: fit.x, y: fit.y);
    _offsetTrusted = true;
  }

  bool _trusted(({double x, double y, double r, double rms}) fit) =>
      fit.r >= 10 && fit.r <= 40 && fit.rms <= fit.r * 0.12;

  /// Whether the last field reading can be believed at all.
  ///
  /// The Earth's field is 25–65 µT. This handset reports 157 µT with the excess
  /// on z, which is a hard-iron offset the OS never removed, and a horizontal
  /// pair that is the offset and the field nearly cancelling: a bearing taken
  /// from it is not "a few degrees out", it can be the opposite direction. So a
  /// reading outside the plausible band is not used to start the dial off and
  /// not used to anchor it — until a turn has measured the offset, after which
  /// the corrected pair is trustworthy whatever the raw magnitude.
  bool get fieldTrusted {
    final MagnetometerEvent? m = _lastMagEvent;
    if (m == null) return false;
    if (_offsetTrusted) return true;
    final double magnitude =
        math.sqrt(m.x * m.x + m.y * m.y + m.z * m.z);
    return magnitude >= 20 && magnitude <= 90;
  }

  /// A field reading has arrived and cannot be used: the phone is sitting in a
  /// magnetic mess (a case, a mount, a speaker) that nobody has calibrated.
  /// Whether a dial must draw north-up and say why.
  ///
  /// Two different unknowns, kept apart: on the platform path the OS tells us
  /// its accuracy, and only a reading it will not vouch for counts; on the
  /// fallback path the test is whether the field looks like the Earth's.
  bool get disturbed => _platformSub != null
      ? needsCalibration
      : (_lastMagEvent != null && !fieldTrusted);

  /// Whether the horizontal offset has been measured from a real turn.
  ///
  /// False until the phone has been turned far enough for the field to describe
  /// a circle of Earth-like radius. While it is false the dial is driven by the
  /// gyroscope from a first guess: the *rotation* is right and the absolute
  /// bearing is not yet, which is the honest state of an uncalibrated compass.
  bool get calibratedCircle => _offsetTrusted;

  bool _offsetTrusted = false;

  /// A least-squares circle through the horizontal field samples.
  ///
  /// Kasa's algebraic fit: every point satisfies `2ax + 2by + c = x² + y²`, so
  /// the centre `(a, b)` is a 3×3 linear solve. Returns null when the points do
  /// not describe a circle, which is the normal case for a phone that has only
  /// been turned a little: a short arc is satisfied by a family of circles, and
  /// the one the algebra picks has a meaningless centre.
  @visibleForTesting
  static ({double x, double y, double r, double rms})? fitCircle(
      List<({double x, double y})> pts) {
    final int n = pts.length;
    if (n < 12) return null;
    double sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
    double sxz = 0, syz = 0, sz = 0;
    for (final ({double x, double y}) p in pts) {
      final double z = p.x * p.x + p.y * p.y;
      sx += p.x;
      sy += p.y;
      sxx += p.x * p.x;
      syy += p.y * p.y;
      sxy += p.x * p.y;
      sxz += p.x * z;
      syz += p.y * z;
      sz += z;
    }
    // Normal equations for 2a·x + 2b·y + c = z.
    final List<List<double>> m = <List<double>>[
      <double>[2 * sxx, 2 * sxy, sx, sxz],
      <double>[2 * sxy, 2 * syy, sy, syz],
      <double>[2 * sx, 2 * sy, n.toDouble(), sz],
    ];
    // Gaussian elimination with partial pivoting.
    for (int col = 0; col < 3; col++) {
      int piv = col;
      for (int r = col + 1; r < 3; r++) {
        if (m[r][col].abs() > m[piv][col].abs()) piv = r;
      }
      if (m[piv][col].abs() < 1e-9) return null;
      final List<double> tmp = m[col];
      m[col] = m[piv];
      m[piv] = tmp;
      for (int r = 0; r < 3; r++) {
        if (r == col) continue;
        final double f = m[r][col] / m[col][col];
        for (int k = col; k < 4; k++) {
          m[r][k] -= f * m[col][k];
        }
      }
    }
    final double a = m[0][3] / m[0][0];
    final double b = m[1][3] / m[1][1];
    final double c = m[2][3] / m[2][2];
    final double rr = c + a * a + b * b;
    if (!rr.isFinite || rr <= 0) return null;
    final double r = math.sqrt(rr);
    // Residual: how far the points actually are from that circle.
    double sq = 0;
    for (final ({double x, double y}) p in pts) {
      final double d = math.sqrt(
              (p.x - a) * (p.x - a) + (p.y - b) * (p.y - b)) -
          r;
      sq += d * d;
    }
    return (x: a, y: b, r: r, rms: math.sqrt(sq / n));
  }

  void _set(double deg) {
    _heading = deg;
  }

  void _touch() {
    _stale?.cancel();
    _stale = Timer(staleAfter, () {
      // No anchor for a whole staleness window: the gyroscope may have drifted
      // and the magnetometer is not saying otherwise. Stop claiming a direction
      // rather than drawing one that is merely plausible.
      _heading = null;
      _anchoredAt = 0;
      notifyListeners();
    });
    notifyListeners();
  }

  /// The shorter way round from [from] to [to], in (−180, 180].
  static double _shortestDelta(double from, double to) {
    double d = to - from;
    while (d > 180) {
      d -= 360;
    }
    while (d < -180) {
      d += 360;
    }
    return d;
  }

  static double _wrap(double deg) {
    double d = deg % 360;
    if (d < 0) d += 360;
    return d;
  }

  /// A phone held flat: the field's horizontal pair points north, so the bearing
  /// of the field from the phone's +Y axis is the heading.
  ///
  /// This is the one formula that does not touch the field's vertical component,
  /// and that is the point: a hard-iron offset on z — which is what this handset
  /// has, 154 µT of it — cannot move the answer. `atan2(-x, y)` because the
  /// sensor's axes are x-right, y-up-the-screen and the bearing is clockwise from
  /// north.
  @visibleForTesting
  static double flatHeading(double mx, double my) {
    double deg = math.atan2(-mx, my) * 180 / math.pi;
    if (deg < 0) deg += 360;
    return deg;
  }

  /// The standard tilt-compensated compass, for a *well calibrated* sensor.
  ///
  /// Used only to seed the very first heading on a phone that is already tilted
  /// (and, on a device with no gyroscope, as the whole answer). It is not used to
  /// track a turn: it assumes the vector it is given is the Earth's field, and
  /// with an uncorrected hard-iron offset it is not — which is why the heading
  /// is integrated from the gyroscope instead.
  ///
  ///   * `a` is the unit up-axis of the world,
  ///   * `E = m x a` is east in device coordinates,
  ///   * `N = a x E` is north in device coordinates.
  ///
  /// The heading is then the angle of the device's own forward axis (`+y`,
  /// toward the top of the screen) measured from north toward east. That last
  /// step is the one worth stating: projecting the *field* instead gives the
  /// bearing of the field, which is 0 whenever the field is horizontal and the
  /// phone is not — a dial that always says north.
  @visibleForTesting
  static double? tiltCompensatedHeading({
    required double mx,
    required double my,
    required double mz,
    required double gx,
    required double gy,
    required double gz,
  }) {
    final double gNorm = math.sqrt(gx * gx + gy * gy + gz * gz);
    if (gNorm == 0) return null;
    final double ax = gx / gNorm, ay = gy / gNorm, az = gz / gNorm;

    // East = field x up.
    final double ex = my * az - mz * ay;
    final double ey = mz * ax - mx * az;
    final double ez = mx * ay - my * ax;
    final double eNorm = math.sqrt(ex * ex + ey * ey + ez * ez);
    if (eNorm == 0) return null;
    final double ux = ex / eNorm, uy = ey / eNorm, uz = ez / eNorm;

    // North = up x east. Only its `y` component is needed: the device's
    // forward axis is +y, and its projections onto east and north are the two
    // legs of the bearing triangle.
    final double ny = az * ux - ax * uz;
    double deg = math.atan2(uy, ny) * 180 / math.pi;
    if (deg < 0) deg += 360;
    return deg;
  }

  /// The marker's position on the rim: the bearing a north tick belongs at when
  /// the top of the screen is where the phone points.
  ///
  /// Pure, because this is the line every dial shares and the sign of it is
  /// what decides whether the marker sits on the correct side.
  static double northMarkerDegrees(double? heading) =>
      heading == null ? 0 : (360 - heading) % 360;

  /// Where a point at [bearingDegrees] from the phone (clockwise from north)
  /// belongs on a dial whose top is the phone's own facing.
  static double relativeDegrees(double bearingDegrees, double? heading) =>
      heading == null
          ? bearingDegrees % 360
          : (bearingDegrees - heading) % 360;

  @override
  void dispose() {
    _platformSub?.cancel();
    _magSub?.cancel();
    _accSub?.cancel();
    _gyroSub?.cancel();
    _stale?.cancel();
    super.dispose();
  }
}

/// The app's one compass, or null when nothing above provided one.
///
/// Three screens draw a dial — the hyperlocal radar, the grid's radar and the
/// map's own arrow — and each used to build its own `CompassHeading`. Two
/// consequences, both visible: switching tabs started a *fresh* filter, whose
/// first bearing is the raw magnetometer guess until the gyroscope has been
/// running, so the dial could jump on the way in; and the calibration one screen
/// accumulated was invisible to the next, so a phone that had been turned enough
/// to calibrate on the dashboard had to be turned again on the map. One instance,
/// provided once, is continuous by construction.
extension CompassScope on BuildContext {
  CompassHeading? get sharedCompass {
    try {
      return Provider.of<CompassHeading?>(this, listen: false);
    } on ProviderNotFoundException {
      // No provider above us: a widget test, or a screen shown on its own. The
      // caller makes its own.
      return null;
    }
  }
}

/// The red north marker every dial draws, so "which way is north" reads the
/// same on all of them.
///
/// A filled triangle sitting on the outer ring and pointing outwards, because a
/// word at the top of a dial is read as decoration and a shape at the edge is
/// read as a direction. [markerDegrees] is the bearing the marker belongs at on
/// a dial whose top is the phone's own facing — see
/// [CompassHeading.northMarkerDegrees].
/// The north triangle's three points, for a ring of [radius].
///
/// The base sits **on** the ring and the tip points outwards. It used to sit
/// [size] inside the ring with the tip on it, so the triangle straddled the line
/// and the marker's own centre landed on the stroke: the one fixed landmark on
/// every dial was half inside the data it labels. Outside is also where a compass
/// rose puts it.
({Offset tip, Offset left, Offset right}) northMarkerTriangle(
  Offset center,
  double radius, {
  required double markerDegrees,
  double size = 15,
}) {
  final double a = markerDegrees * math.pi / 180;
  Offset at(double r, double off) => Offset(
        center.dx + r * math.sin(a + off),
        center.dy - r * math.cos(a + off),
      );
  final double halfBase = size * 0.78;
  return (
    tip: at(radius + size, 0),
    left: at(radius, -halfBase / radius),
    right: at(radius, halfBase / radius),
  );
}

void paintNorthMarker(
  Canvas canvas,
  Offset center,
  double radius, {
  required double markerDegrees,
  required Color color,
  double size = 15,
}) {
  final ({Offset tip, Offset left, Offset right}) t = northMarkerTriangle(
    center,
    radius,
    markerDegrees: markerDegrees,
    size: size,
  );
  final Path path = Path()
    ..moveTo(t.tip.dx, t.tip.dy)
    ..lineTo(t.left.dx, t.left.dy)
    ..lineTo(t.right.dx, t.right.dy)
    ..close();
  canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
}
