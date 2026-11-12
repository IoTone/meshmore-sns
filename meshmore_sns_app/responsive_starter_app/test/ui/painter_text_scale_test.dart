// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A painter draws the user's text at the user's size.
///
/// Text painted onto a canvas is the one place in Flutter that has no
/// `MediaQuery`, so a `CustomPainter` cannot read the text scale for itself and
/// has to be handed it. Five painters were not: the radar's callouts, the mesh
/// tree's node names, the cells view's labels, the elevation chart's axes and
/// the grid's ring labels all drew at the *skin's* size only, which meant the
/// one text in the app that ignored the font setting. Raising it to 200 % grew
/// every list, sheet and notice and left those five exactly where they were,
/// which is the opposite of what a person who raised it needs.
///
/// The rule this holds: inside a painter class, every `fontSize:` is derived
/// from the user's scale, visibly. That is either `textScale` itself or a
/// `scaledSize` the painter computed from it, so a reader of the line can see
/// where the number came from.
void main() {
  /// The body of a class declaration, braces balanced from its opening brace.
  String classBody(String source, int from) {
    int i = source.indexOf('{', from);
    final int start = i;
    int depth = 0;
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

  test('every painter draws text at the user text scale', () {
    final List<String> offenders = <String>[];
    int paintersWithText = 0;
    for (final FileSystemEntity e
        in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String src = e.readAsStringSync();
      for (final RegExpMatch m
          in RegExp(r'class\s+(\w+)\s+extends\s+CustomPainter')
              .allMatches(src)) {
        final String body = classBody(src, m.end);
        final List<String> sizes = <String>[
          for (final String line in body.split('\n'))
            if (line.contains('fontSize:')) line.trim(),
        ];
        if (sizes.isEmpty) continue;
        paintersWithText++;
        for (final String line in sizes) {
          if (!line.contains('textScale') && !line.contains('scaledSize')) {
            final int at = src.indexOf(line);
            final int number = src.substring(0, at).split('\n').length;
            offenders.add('${e.path}:$number ${m.group(1)}: $line');
          }
        }
      }
    }
    expect(paintersWithText, greaterThanOrEqualTo(5),
        reason: 'the scan must find the painters that draw text, or it is '
            'asserting nothing');
    expect(offenders, isEmpty,
        reason: 'a painter cannot read the text scale, so it has to be handed '
            'it: ${offenders.join(', ')}');
  });
}
