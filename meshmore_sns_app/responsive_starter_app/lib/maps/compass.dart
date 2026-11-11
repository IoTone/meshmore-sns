// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Canvas, Color, Offset, Paint, PaintingStyle, Path;
import 'package:sensors_plus/sensors_plus.dart';

/// Which way the phone is pointing, so a radar can draw the world the right
/// way round.
///
/// Both the hyperlocal radar and the grid's radar plot peers by *bearing*: a
/// repeater to your east belongs on the right of the rings. That is only true
/// while the phone is held facing north. Held facing east, a north-up dial puts
/// every peer a quarter turn away from where the antenna actually is, which is
/// worse than no dial at all — it looks authoritative and is wrong.
///
/// So the dials rotate: the top of the screen is the direction the phone is
/// facing, and a red marker on the rim says where north is. North-up remains
/// the fallback whenever there is no heading, because a dial that cannot know
/// its orientation must not pretend to.
///
/// **Magnetic north.** The magnetometer reports the field, not the meridian,
/// and the difference (declination) varies by roughly ±20° over the planet. The
/// dial therefore calls the red marker north in the magnetic sense, which is
/// what every hand compass does when it has not been told where it is. Applying
/// a real declination needs a geomagnetic model this app does not ship, so the
/// claim stays as small as it can be.
class CompassHeading extends ChangeNotifier {
  CompassHeading({
    Stream<MagnetometerEvent>? magnetometer,
    Stream<AccelerometerEvent>? accelerometer,
    this.smoothing = 0.15,
    this.staleAfter = const Duration(seconds: 3),
  })  : _mag = magnetometer,
        _acc = accelerometer;

  /// Injected in tests. Null means "subscribe from `sensors_plus`", which is
  /// what the app does; a test passes a controller it can drive.
  final Stream<MagnetometerEvent>? _mag;
  final Stream<AccelerometerEvent>? _acc;

  /// How much of each new sample is taken. A magnetometer is noisy and a dial
  /// redrawn 60 times a second from raw samples shivers; a low-pass keeps it
  /// steady without lagging a whole turn behind a hand.
  final double smoothing;

  /// A heading older than this is not trusted. Phones that stop delivering
  /// samples (screen off, sensor throttled) would otherwise leave a dial
  /// rotated to a direction the phone no longer faces.
  final Duration staleAfter;

  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<AccelerometerEvent>? _accSub;
  Timer? _stale;

  double? _heading;

  /// Degrees clockwise from magnetic north, or null when nothing is known.
  ///
  /// Null is the important case: no sensor, no permission, or a device whose
  /// samples stopped. Every caller must draw north-up for null.
  double? get heading => _heading;

  /// Whether the dial should rotate at all.
  bool get hasHeading => _heading != null;

  /// The last magnetometer sample, and the last accelerometer sample, kept so
  /// a heading can be computed from two sensors that do not tick together.
  ({double x, double y, double z})? _magVec;
  ({double x, double y, double z})? _accVec;

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    final Stream<MagnetometerEvent> mag =
        _mag ?? magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval);
    final Stream<AccelerometerEvent> acc =
        _acc ?? accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval);
    _magSub = mag.listen(_onMag, onError: (Object _) {}, cancelOnError: false);
    _accSub = acc.listen(_onAcc, onError: (Object _) {}, cancelOnError: false);
  }

  void _onMag(MagnetometerEvent e) {
    _magVec = (x: e.x, y: e.y, z: e.z);
    _recompute();
  }

  void _onAcc(AccelerometerEvent e) {
    _accVec = (x: e.x, y: e.y, z: e.z);
    _recompute();
  }

  void _recompute() {
    final ({double x, double y, double z})? m = _magVec;
    final ({double x, double y, double z})? g = _accVec;
    if (m == null) return;
    // Tilt compensation needs gravity. Without it the simplest usable reading
    // is the horizontal component of the field, which is right for a phone
    // held flat — the case a radar is read in — and wrong by the tilt when it
    // is not, which is why gravity is preferred when it exists.
    final double? raw = g == null
        ? _flatHeading(m)
        : tiltCompensatedHeading(
            mx: m.x, my: m.y, mz: m.z, gx: g.x, gy: g.y, gz: g.z);
    if (raw == null) return;
    _apply(raw);
  }

  void _apply(double raw) {
    final double? prev = _heading;
    double next;
    if (prev == null) {
      next = raw;
    } else {
      // Interpolate across the wrap, or a heading passing north would swing
      // the long way round: 359° to 1° must move two degrees, not 358.
      double delta = raw - prev;
      while (delta > 180) {
        delta -= 360;
      }
      while (delta < -180) {
        delta += 360;
      }
      next = (prev + delta * smoothing) % 360;
      if (next < 0) next += 360;
    }
    _heading = next;
    _stale?.cancel();
    _stale = Timer(staleAfter, () {
      _heading = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// A phone held flat: the horizontal field points north, so the bearing of
  /// the field from the phone's +Y axis is the heading.
  static double? _flatHeading(({double x, double y, double z}) m) {
    if (m.x == 0 && m.y == 0) return null;
    // atan2 with x and y swapped, because `heading` is degrees clockwise from
    // north and the sensor's axes are x-right, y-up-the-screen.
    double deg = math.atan2(-m.x, m.y) * 180 / math.pi;
    if (deg < 0) deg += 360;
    return deg;
  }

  /// The standard tilt-compensated compass, in degrees clockwise from north.
  ///
  /// Built from the two vectors Android hands us: the accelerometer, which for
  /// a phone lying flat and screen-up reports **+z** (the reaction to gravity,
  /// pointing out of the screen), and the magnetometer, which reports the
  /// field. From them:
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
    _magSub?.cancel();
    _accSub?.cancel();
    _stale?.cancel();
    super.dispose();
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
void paintNorthMarker(
  Canvas canvas,
  Offset center,
  double radius, {
  required double markerDegrees,
  required Color color,
  double size = 9,
}) {
  final double a = markerDegrees * math.pi / 180;
  // Point on the ring, and the two base corners a little inside it.
  Offset at(double r, double off) => Offset(
        center.dx + r * math.sin(a + off),
        center.dy - r * math.cos(a + off),
      );
  final double halfBase = size * 0.62;
  final Offset tip = at(radius, 0);
  final Offset left = at(radius - size, -halfBase / radius);
  final Offset right = at(radius - size, halfBase / radius);
  final Path path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(left.dx, left.dy)
    ..lineTo(right.dx, right.dy)
    ..close();
  canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
}
