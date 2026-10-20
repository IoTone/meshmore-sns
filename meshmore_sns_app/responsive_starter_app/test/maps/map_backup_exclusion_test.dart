// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// R82 — a region archive is tens to hundreds of megabytes of re-downloadable
/// cache. Android Auto Backup includes `files/` by default and has a 25 MB
/// quota, so an archive either fails the backup or pays to upload hundreds of
/// megabytes to the user's drive. Both rule files must exclude it, and the
/// manifest must point at them.
void main() {
  const String manifest = 'android/app/src/main/AndroidManifest.xml';
  const String legacy = 'android/app/src/main/res/xml/backup_rules.xml';
  const String modern =
      'android/app/src/main/res/xml/data_extraction_rules.xml';

  test('the manifest points at both backup rule files', () {
    final String m = File(manifest).readAsStringSync();
    expect(m, contains('android:fullBackupContent="@xml/backup_rules"'),
        reason: 'Android 11 and below');
    expect(m, contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
        reason: 'Android 12 and above, where the old attribute is ignored');
  });

  test('the map directory is excluded from cloud backup and transfer', () {
    final String l = File(legacy).readAsStringSync();
    expect(l, contains('<exclude domain="file" path="maps/" />'));

    final String d = File(modern).readAsStringSync();
    for (final String section in <String>['cloud-backup', 'device-transfer']) {
      final String body = RegExp('<$section>(.*?)</$section>', dotAll: true)
          .firstMatch(d)
          ?.group(1) ??
          '';
      expect(body, contains('<exclude domain="file" path="maps/" />'),
          reason: '$section must not carry map data');
    }
  });

  test('the excluded path matches where the maps controller writes', () {
    // getApplicationSupportDirectory() is `files/` on Android, and the
    // controller roots the store at `maps` inside it (maps_controller.dart).
    final String c = File('lib/maps/maps_controller.dart').readAsStringSync();
    expect(c, contains("getApplicationSupportDirectory()).path}/maps"));
  });
}
