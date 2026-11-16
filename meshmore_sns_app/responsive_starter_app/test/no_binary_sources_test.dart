// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A NUL byte anywhere in a `.dart` file makes the whole file read as
/// binary. `grep` and `ripgrep` then **skip it silently** — a search
/// returns no matches from that file, which is indistinguishable from
/// the symbol genuinely not being there. No error, no warning.
///
/// This is not hypothetical: `chat_screen.dart` carried a literal NUL
/// in an identity sentinel, and a search for `tts` across `lib/`
/// reported nothing from the one file that owned the channel-speech
/// subscription. Write control characters as escapes.
void main() {
  test('no .dart source contains a literal NUL byte', () {
    final List<String> offenders = <String>[];
    for (final String root in <String>['lib', 'test']) {
      final Directory d = Directory(root);
      if (!d.existsSync()) continue;
      for (final FileSystemEntity e in d.listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        if (e.readAsBytesSync().contains(0)) offenders.add(e.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Literal NUL bytes make these files invisible to grep/rg. '
          'Write the character as a \u0000 escape instead.',
    );
  });
}
