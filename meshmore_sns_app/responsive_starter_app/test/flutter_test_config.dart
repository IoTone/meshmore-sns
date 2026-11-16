// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Package-wide test bootstrap (Flutter auto-loads this file).
///
/// `MeshcoreController` (constructed by most tests) restores chat
/// history via `shared_preferences` on construction. Without a mock
/// the platform channel never answers and the test hangs 10 min —
/// so install an empty mock for every test by default. Individual
/// tests may still call `SharedPreferences.setMockInitialValues(...)`
/// to seed specific values.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Reset BEFORE EVERY test (not once) so messages a test persists
  // don't leak into the next via the shared mock store. Tests that
  // need seeded values call setMockInitialValues again afterwards.
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // `sensors_plus` sets a sampling period through a method channel before it
    // subscribes, with the call left unawaited. There is no platform under
    // `flutter test`, so that call throws a `MissingPluginException` into the
    // zone and fails every test that mounts a screen with a compass in it. The
    // sensor *streams* are event channels: an unmocked one errors, which the
    // subscriber swallows, so only the method channel needs answering.
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/sensors/method'),
      (MethodCall call) async => null,
    );
    // And the sensor streams themselves: an unmocked event channel reports the
    // failed `listen` through the services library, above the stream's own
    // error handler, so there is nothing a subscriber could swallow. A handler
    // that never emits is a phone with no sensors, which is a state every
    // screen already draws.
    // The app's own compass channel. In the app the platform answers it with
    // the OS's fused rotation vector; here it stays silent, which is a phone
    // with no compass — a state every dial already draws.
    messenger.setMockStreamHandler(
      const EventChannel('meshmore/compass'),
      MockStreamHandler.inline(
        onListen: (Object? arguments, MockStreamHandlerEventSink sink) {},
        onCancel: (Object? arguments) {},
      ),
    );
    for (final String sensor in <String>[
      'accelerometer',
      'user_accel',
      'gyroscope',
      'magnetometer',
      'barometer',
    ]) {
      messenger.setMockStreamHandler(
        EventChannel('dev.fluttercommunity.plus/sensors/$sensor'),
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink sink) {},
          onCancel: (Object? arguments) {},
        ),
      );
    }
  });
  await testMain();
}
