// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/maps/compass.dart';

/// The quarter-turn click has to reach the platform, from the one compass the
/// whole app shares.
///
/// It was wired into the grid's radar alone, behind an `isCurrent` flag, so a
/// phone turned on the dashboard or the map — the two other screens that draw a
/// bearing — clicked nothing. The listener lives in `CompassHeading` now; this
/// pins that a crossing actually asks the platform for a haptic, and that a phone
/// that is merely wobbling on a mark asks for nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> haptics;
  setUp(() {
    haptics = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add('${call.arguments}');
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// A level phone facing [deg]: the frame is rotated by -deg about up.
  CompassReading level(double deg, {int accuracy = 15}) {
    final double half = -deg * 3.141592653589793 / 360;
    return CompassReading(
      qx: 0,
      qy: 0,
      qz: _sin(half),
      qw: _cos(half),
      displayRotation: 0,
      accuracy: accuracy,
    );
  }

  test('a quarter turn clicks once, through the shared compass', () async {
    final StreamController<CompassReading> platform =
        StreamController<CompassReading>.broadcast();
    final CompassHeading compass = CompassHeading(
      platform: platform.stream,
      staleAfter: const Duration(seconds: 30),
    )..start();
    addTearDown(() async {
      compass.dispose();
      await platform.close();
    });

    // Two degrees past east is not yet a crossing; six is.
    for (final double h in <double>[80, 89, 90, 92, 96]) {
      platform.add(level(h));
      await Future<void>.delayed(Duration.zero);
    }
    expect(haptics.length, 1, reason: 'one click for one crossing');

    // A hand wobbling on the mark asks for nothing more.
    for (final double h in <double>[94, 90, 88, 90, 92]) {
      platform.add(level(h));
      await Future<void>.delayed(Duration.zero);
    }
    expect(haptics.length, 1, reason: 'a wobble is not a turn');
  });

  test('the click can be turned off', () async {
    final StreamController<CompassReading> platform =
        StreamController<CompassReading>.broadcast();
    final CompassHeading compass = CompassHeading(
      platform: platform.stream,
      staleAfter: const Duration(seconds: 30),
    )..start();
    compass.clickAtQuarterTurns = false;
    addTearDown(() async {
      compass.dispose();
      await platform.close();
    });
    for (final double h in <double>[80, 96]) {
      platform.add(level(h));
      await Future<void>.delayed(Duration.zero);
    }
    expect(haptics, isEmpty);
  });
}

double _sin(double x) {
  // Small-angle-free: the headings used here are multiples of a few degrees.
  double t = x;
  double acc = x;
  for (int i = 1; i < 12; i++) {
    t *= -x * x / ((2 * i) * (2 * i + 1));
    acc += t;
  }
  return acc;
}

double _cos(double x) {
  double t = 1;
  double acc = 1;
  for (int i = 1; i < 12; i++) {
    t *= -x * x / ((2 * i - 1) * (2 * i));
    acc += t;
  }
  return acc;
}
