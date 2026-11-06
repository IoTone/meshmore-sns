// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the single-source-of-truth rule for our own position.
///
/// `MeshcoreController.ownLocation` decides where "we" are: the device's
/// reported fix when it has one, otherwise the one-shot phone fix. Views
/// that read `selfInfo.latitude/longitude` instead bypass that rule — and
/// two did:
///
///  - `grid_screen.dart` read `selfInfo`, so a device reporting (0,0)
///    (GPS off, no lock, hidden position) made the phone fallback
///    unreachable and every peer fell to the RSSI-ring placement.
///  - `globe_view.dart` preferred the cached phone fix over the device's,
///    the inverse of `ownLocation`, so it could centre somewhere else
///    than every other screen.
///
/// These assertions are deliberately textual: the failure mode is a
/// view picking the wrong *source*, which no behavioural widget test
/// notices until the two sources disagree, and the radar has no
/// observable seam.
///
/// Two files are excluded by name, both because their job is to print the raw
/// wire values so the two sources can be compared by eye rather than to decide
/// where "we" are: the dashboard's `_LocationDebugLine` and the Diagnostics
/// developer section's position readout, which is where that line moved when
/// it left the home screen. A view that picks a source is still caught.
void main() {
  final Directory lib = Directory('lib');

  /// Strips `//` comments so a passing mention in prose cannot trip a
  /// guard, and so the guards cannot be satisfied by commenting code out.
  List<(int, String)> codeLines(File f) {
    final List<(int, String)> out = <(int, String)>[];
    final List<String> lines = f.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final String t = lines[i].trimLeft();
      if (t.startsWith('//')) continue;
      out.add((i + 1, lines[i]));
    }
    return out;
  }

  test('no view reads a position out of selfInfo', () {
    expect(lib.existsSync(), isTrue,
        reason: 'run from the package root (lib/ not found in '
            '${Directory.current.path})');

    final String pattern = r'selfInfo\s*[!?]?\s*\.\s*(latitude|longitude)';
    final RegExp re = RegExp(pattern);
    final List<String> offenders = <String>[];
    for (final FileSystemEntity e in lib.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.endsWith('dashboard_screen.dart')) continue; // by design
      if (e.path.endsWith('diagnostics_screen.dart')) continue; // raw readout
      for (final (int n, String line) in codeLines(e)) {
        if (re.hasMatch(line)) {
          offenders.add('${e.path}:$n: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'read mc.ownLocation, which applies the device-first / '
            'phone-fallback rule:\n${offenders.join('\n')}');
  });

  test('the radar and the globe both go through ownLocation', () {
    for (final String path in <String>[
      'lib/screens/grid_screen.dart',
      'lib/screens/globe_view.dart',
    ]) {
      final File f = File(path);
      expect(f.existsSync(), isTrue, reason: '$path must exist');
      final String src = f.readAsStringSync();
      expect(src.contains('ownLocation'), isTrue,
          reason: '$path must take our position from mc.ownLocation');
      for (final (int n, String line) in codeLines(f)) {
        expect(line.contains('selfInfo'), isFalse,
            reason: '$path:$n reads selfInfo — this file must not pick a '
                'position source of its own:\n  ${line.trim()}');
      }
    }
  });

  test('the globe is device-first, not phone-first', () {
    // The specific inversion: `phoneLocationFix ?? selfInfo`. The device
    // fix is the authoritative one; a stale cached phone fix must not
    // outrank it.
    final String src = File('lib/screens/globe_view.dart').readAsStringSync();
    final RegExp phoneFirst =
        RegExp(r'phoneLocationFix\s*\?\?|\?phoneLocationFix');
    for (final (int n, String line) in codeLines(File('lib/screens/globe_view.dart'))) {
      expect(phoneFirst.hasMatch(line), isFalse,
          reason: 'globe_view.dart:$n prefers the phone fix over the '
              'device fix again:\n  ${line.trim()}');
    }
    expect(src, contains('ownLocation'));
  });
}