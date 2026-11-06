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
///    than every other screen. The globe itself was removed from the
///    product on 2026-11-05; the rule outlived it, which is why the
///    radar and the map are still held to it below.
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

  test('the radar goes through ownLocation', () {
    final File f = File('lib/screens/grid_screen.dart');
    expect(f.existsSync(), isTrue, reason: 'lib/screens/grid_screen.dart must exist');
    final String src = f.readAsStringSync();
    expect(src.contains('ownLocation'), isTrue,
        reason: 'the radar must take our position from mc.ownLocation');
    for (final (int n, String line) in codeLines(f)) {
      expect(line.contains('selfInfo'), isFalse,
          reason: 'grid_screen.dart:$n reads selfInfo — this file must not '
              'pick a position source of its own:\n  ${line.trim()}');
    }
  });

}