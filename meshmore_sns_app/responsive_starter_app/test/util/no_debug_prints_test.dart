// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A release build keeps its logcat, and a logcat line that carries a
/// position, a channel key or a peer key is readable by anything with
/// `logcat` access. So every diagnostic line in `lib/` is gated by
/// `kDebugMode`, which the compiler folds to `false` in a release build: the
/// call and its string are removed rather than merely skipped.
///
/// Two shapes are accepted, because both are used deliberately:
///  * the gate on the call's own line, `if (kDebugMode) debugPrint(…)`, so a
///    reader sees it at the call site;
///  * a file whose one wrapper (or one enclosing block) holds the gate, listed
///    below with the reason it is allowed.
void main() {
  /// Files allowed to reach `print`/`debugPrint` through a gate that is not on
  /// the same line. Each reason names the gate, so an edit that drops it fails
  /// the second half of this test.
  const Map<String, String> gatedElsewhere = <String, String>{
    'lib/util/mesh_log.dart': 'the one field-log wrapper, gated by _fieldLog',
    'lib/app/app_errors.dart': 'the error ring, an enclosing kDebugMode block',
    'lib/ui/mm_collapsible.dart': 'one warning, an enclosing kDebugMode block',
  };

  test('no diagnostic print escapes the kDebugMode gate', () {
    final List<String> violations = <String>[];
    final Directory lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run from the app root');

    for (final FileSystemEntity e in lib.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.contains('/gen/')) continue;
      if (gatedElsewhere.containsKey(e.path)) continue;

      for (final String line in e.readAsStringSync().split('\n')) {
        final String t = line.trimLeft();
        if (t.startsWith('//')) continue;
        final bool prints = t.contains('debugPrint(') || _barePrint(t);
        if (prints && !t.contains('kDebugMode')) {
          violations.add('${e.path}: $t');
        }
      }
    }

    expect(violations, isEmpty,
        reason: 'these lines print outside a kDebugMode gate:\n'
            '${violations.join('\n')}\n'
            'Route the line through meshLog() or put `if (kDebugMode)` on it.');

    for (final String path in gatedElsewhere.keys) {
      expect(File(path).readAsStringSync().contains('kDebugMode'), isTrue,
          reason: '$path may print only because it holds the gate');
    }
  });
}

/// `print(` on a trimmed line that is not part of `debugPrint(`.
bool _barePrint(String trimmed) {
  if (!trimmed.contains('print(')) return false;
  return !trimmed.contains('debugPrint(');
}
