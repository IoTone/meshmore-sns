// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Store obligations that live in build files and the manifest, so nothing in
/// Dart can regress them silently:
///
/// * API 36 is pinned rather than inherited from `flutter.compileSdkVersion`,
///   because it is a Play requirement and a toolchain change must not move it.
/// * The foreground service declares the `connectedDevice` type, which is what
///   holding a BLE peripheral connection for polling/sync actually is — the
///   wrong type either fails review or hits Android 15's `dataSync` timeout.
/// * The notification copy still says why the service runs: a foreground
///   service the user cannot explain is a service they turn off.
/// * The 16 KB page check is a script in the tree, not a claim in a document.
void main() {
  const String gradle = 'android/app/build.gradle';
  const String manifest = 'android/app/src/main/AndroidManifest.xml';
  const String keepalive = 'lib/meshcore/background_keepalive.dart';
  const String sixteenKb = 'tool/check_16k.sh';
  const String legacyBackupRules = 'android/app/src/main/res/xml/backup_rules.xml';
  const String dataExtractionRules =
      'android/app/src/main/res/xml/data_extraction_rules.xml';

  test('API 36 is pinned in the app build, not inherited', () {
    final String g = File(gradle).readAsStringSync();
    expect(RegExp(r'^\s*compileSdk 36\s*$', multiLine: true).hasMatch(g),
        isTrue,
        reason: 'compileSdk must be the literal 36, not flutter.compileSdkVersion');
    expect(RegExp(r'^\s*targetSdkVersion 36\s*$', multiLine: true).hasMatch(g),
        isTrue,
        reason: 'targetSdkVersion must be the literal 36');
    // minSdk stays the toolchain's minimum: it is not a store obligation.
    expect(g, contains('minSdkVersion flutter.minSdkVersion'));
  });

  test('the foreground service is declared as connectedDevice', () {
    final String m = File(manifest).readAsStringSync();
    expect(m, contains('android.permission.FOREGROUND_SERVICE'));
    expect(m, contains('android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE'));
    expect(m, contains('android.permission.POST_NOTIFICATIONS'));

    final RegExp service = RegExp('<service[^>]*>', dotAll: true);
    final String declared = service
        .allMatches(m)
        .map((RegExpMatch x) => x.group(0)!)
        .firstWhere(
          (String s) =>
              s.contains('flutter_foreground_task.service.ForegroundService'),
          orElse: () => '',
        );
    expect(declared, isNotEmpty, reason: 'the keepalive service is declared in the manifest');
    expect(declared, contains('android:foregroundServiceType="connectedDevice"'));
    expect(declared, contains('android:exported="false"'));
  });

  test('the keepalive notification says why it runs', () {
    final String k = File(keepalive).readAsStringSync();
    expect(k, contains("channelDescription:"));
    expect(k, contains('while the app is in the background'),
        reason: 'the running notification must explain the link it keeps alive');
    expect(k, isNot(contains("foregroundServiceType=\"dataSync\"")),
        reason: 'dataSync is not what a BLE link is');
  });

  test('the 16 KB page check ships as a runnable script', () {
    final File f = File(sixteenKb);
    expect(f.existsSync(), isTrue);
    expect(f.readAsStringSync(), contains('-c -P 16'),
        reason: 'the archive half of the check must stay');
    expect(f.readAsStringSync(), contains('GNU_RELRO'),
        reason: 'the per-library half of the check must stay');
    final ProcessResult r = Process.runSync('test', <String>['-x', sixteenKb]);
    expect(r.exitCode, 0, reason: '$sixteenKb must be executable');
  });

  test('nothing leaves the device in a backup, on either platform rule set',
      () {
    // D8.8: the store's key is in the Android Keystore and cannot be exported,
    // so a restored copy of the ciphertext is unreadable; map tiles are cache.
    // Both rule files must exclude every domain, or a later feature puts a file
    // back into the cloud by default.
    const List<String> domains = <String>[
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
    ];
    final String legacy = File(legacyBackupRules).readAsStringSync();
    final String modern = File(dataExtractionRules).readAsStringSync();

    for (final String d in domains) {
      final String exclude = '<exclude domain="$d" path="." />';
      expect(legacy, contains(exclude),
          reason: 'backup_rules.xml must exclude the $d domain');
      // Android 12+ has two directions and both must exclude it.
      expect(
          RegExp(RegExp.escape(exclude)).allMatches(modern).length, 2,
          reason: 'data_extraction_rules.xml must exclude $d in cloud-backup '
              'and device-transfer');
    }
    expect(modern, contains('<cloud-backup>'));
    expect(modern, contains('<device-transfer>'));
  });

  test('the sealed store is the only history the app writes', () {
    // The migration removes the plaintext only after the sealed copy verifies,
    // and it is the only place that may name the old key.
    final String chat = File('lib/meshcore/chat_store.dart').readAsStringSync();
    expect(chat, contains('EncryptedStore'));
    expect(chat, contains("'mm.chat.v1'"),
        reason: 'the legacy key is read for the migration and nowhere else');
    // The plaintext write is a fallback only: it sits after the sealed path
    // in `save`, and the migration removes the plaintext once sealed works.
    expect(RegExp('setString\\(_kLegacyKey').allMatches(chat).length, 1,
        reason: 'exactly one plaintext write, the host-with-no-key fallback');
    expect(chat, contains('p.remove(_kLegacyKey)'),
        reason: 'migration must delete the plaintext after verifying the copy');
  });
}
