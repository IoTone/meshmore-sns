// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A painter that takes a value must say so when that value changes.
///
/// Two faults on the radars came from exactly this and nothing else. The grid's
/// painter took `headingDegrees` and did not pass it to `positionFor`, so every
/// peer was drawn at its true bearing while the red north marker rotated — the
/// arrow said where north was and the dots did not follow it. And the hyperlocal
/// painter did not compare `headingDegrees` in `shouldRepaint`, so a heading
/// change only reached the canvas because the sweep animation forced a repaint
/// every frame; with reduce-motion on, where the sweep is null and never
/// changes, the whole dial froze.
///
/// Neither is a maths error, and neither can be caught by asserting a bearing.
/// What can be asserted is the contract: a painter's `shouldRepaint` names every
/// input that changes what it draws.
void main() {
  /// The body of a declaration, braces balanced from its first `{`.
  String bodyOf(String source, int from) {
    final int start = source.indexOf('{', from);
    if (start < 0) return '';
    int depth = 0;
    int i = start;
    while (i < source.length) {
      if (source[i] == '{') {
        depth++;
      } else if (source[i] == '}') {
        depth--;
        if (depth == 0) break;
      }
      i++;
    }
    return source.substring(start, i + 1);
  }

  /// The body of a declaration that may be an expression (`=> ...;`) rather than
  /// a block. Reading the next `{` for an expression body finds the *following*
  /// declaration instead, which is how this guard first passed a painter that
  /// did not compare its heading.
  String declBody(String source, int at) {
    final int arrow = source.indexOf('=>', at);
    final int brace = source.indexOf('{', at);
    if (arrow >= 0 && (brace < 0 || arrow < brace)) {
      final int semi = source.indexOf(';', arrow);
      return source.substring(arrow, semi + 1);
    }
    return bodyOf(source, at);
  }

  test('every painter compares the heading it draws with', () {
    final List<String> offenders = <String>[];
    int checked = 0;
    for (final FileSystemEntity e
        in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String src = e.readAsStringSync();
      if (!src.contains('extends CustomPainter')) continue;
      for (final RegExpMatch m
          in RegExp(r'class\s+(\w+)\s+extends\s+CustomPainter')
              .allMatches(src)) {
        final String paint = bodyOf(src, m.end);
        final bool takesHeading = RegExp(r'final\s+double\??\s+headingDegrees')
            .hasMatch(paint);
        if (!takesHeading) continue;
        checked++;
        final int at = src.indexOf('bool shouldRepaint', m.end);
        if (at < 0) {
          offenders.add('${e.path} ${m.group(1)}: no shouldRepaint at all');
          continue;
        }
        final String repaint = declBody(src, at);
        if (!repaint.contains('headingDegrees')) {
          final int number = src.substring(0, at).split('\n').length;
          offenders.add('${e.path}:$number ${m.group(1)}: shouldRepaint '
              'ignores headingDegrees');
        }
      }
    }
    expect(checked, greaterThanOrEqualTo(2),
        reason: 'the scan must find the painters that take a heading, or it is '
            'asserting nothing');
    expect(offenders, isEmpty, reason: offenders.join(', '));
  });
}
