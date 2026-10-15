// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
//
// R61 — headless runner for the offline-maps self-test on a real
// device. Builds as its own APK entrypoint, runs every check against
// the real servers and the real app-support directory, and writes the
// report to logcat between markers so a script can read it:
//
//   flutter build apk --debug -t tool/maps_selftest_device.dart
//   adb install -r build/app/outputs/flutter-apk/app-debug.apk
//   adb logcat -c && adb shell monkey -p com.iotone.meshmore_sns_app 1
//   adb logcat -s flutter | sed -n '/MAPS-SELFTEST BEGIN/,/MAPS-SELFTEST END/p'
//
// Reinstall the normal APK afterwards (same package id; data is kept).
// The same checks run in the app under Settings → Offline maps →
// Self-test.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:meshmore_sns_app/maps/maps_self_test.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Directory support = await getApplicationSupportDirectory();
  final MapsSelfTest st = MapsSelfTest(
    sandbox: Directory('${support.path}/maps-selftest'),
    appVersion: 'device-runner',
  );
  runApp(MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: st,
          builder: (BuildContext context, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Text(
              st.running || st.total == null ? 'running…\n\n${st.report()}' : st.report(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
      ),
    ),
  ));
  await st.run();
  debugPrint('MAPS-SELFTEST BEGIN');
  for (final String line in st.report().split('\n')) {
    debugPrint('MAPS-SELFTEST $line');
  }
  debugPrint('MAPS-SELFTEST END');
}
