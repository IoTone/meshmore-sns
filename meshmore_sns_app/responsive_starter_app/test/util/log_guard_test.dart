// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Field diagnostics carry a key prefix or a position, and a release log is
/// readable by anything with logcat access. `lib/util/mesh_log.dart` is the one
/// place allowed to print, and it compiles itself out of a release build; this
/// keeps a new call site from going around it.
///
/// `debugPrint` is fine unguarded: it is Flutter's own throttled debug sink and
/// the framework silences it in release.
void main() {
  test('only mesh_log.dart prints in lib', () {
    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity
        in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String path = entity.path.replaceAll(r'\', '/');
      if (path.endsWith('util/mesh_log.dart')) continue;
      if (path.contains('/gen/')) continue;
      final List<String> lines = entity.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (RegExp(r'(?<!debug)\bprint\(').hasMatch(line)) {
          offenders.add('$path:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'route diagnostics through meshLog(tag, message)');
  });
}
