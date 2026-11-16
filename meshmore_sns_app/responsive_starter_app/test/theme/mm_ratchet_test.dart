// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// W2 — the size and colour ratchet.
///
/// Two source scans, both **lower-only**, in the same style as
/// `test/ui/type_rule_guard_test.dart` (the mono face) and
/// `test/ui/square_controls_guard_test.dart` (control radii): the number of
/// literal type sizes and the number of literal colours a file carries may not
/// grow, so the screens that have not been migrated yet stop accumulating new
/// ones, and every migration lowers its own entry in the same commit.
///
/// What is NOT enforceable by a scan: whether a number is the *right* step.
/// That is a judgement each migration records (see `meshmore-sns-UX-spec.md`,
/// type scale) — the roles live in `MmType`, the spacings in `MmSpace`.

/// The source with its comments removed.
///
/// A scan that reads raw text counts prose: `basemap.dart` carried a comment
/// saying "`Colors.black54` was the only literal colour left in this file" and
/// the colour ratchet counted that sentence as a literal colour, so the file
/// could never reach zero. A comment is not a defect. Strings are kept, because
/// a colour inside a string is still a colour the app draws.
String withoutComments(String src) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  String? quote;
  while (i < src.length) {
    final String c = src[i];
    if (quote != null) {
      out.write(c);
      if (c == r'\\' && i + 1 < src.length) {
        out.write(src[i + 1]);
        i += 2;
        continue;
      }
      if (c == quote) quote = null;
      i++;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      out.write(c);
      i++;
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      i += 2;
      while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

void main() {
  const Set<String> exempt = <String>{
    // Runs before the provider tree exists, so no skin can be read.
    'lib/shell/boot_overlay.dart',
    // Generated licence text in its own fixed style.
    'lib/licenses/asset_licenses.dart',
  };

  /// Files a scan may read: `lib/**` minus generated l10n, minus the token
  /// layer itself (that is where the literals are *supposed* to live), minus
  /// the two files that have no skin to read.
  List<File> scanned() => <File>[
        for (final FileSystemEntity e
            in Directory('lib').listSync(recursive: true))
          if (e is File && e.path.endsWith('.dart'))
            if (!e.path.replaceAll('\\', '/').startsWith('lib/gen/') &&
                !e.path.replaceAll('\\', '/').startsWith('lib/theme/') &&
                !exempt.contains(e.path.replaceAll('\\', '/')))
              e,
      ];

  String rel(File f) => f.path.replaceAll('\\', '/');

  final RegExp fontSize = RegExp(r'fontSize:\s*\d+(?:\.\d+)?');
  final RegExp colour = RegExp(r'Color\(0x|Colors\.(\w+)');

  int countColours(String source) {
    int n = <RegExpMatch>[
      for (final RegExpMatch m in colour.allMatches(source))
        if (m.group(0) == 'Color(0x' ||
            (m.group(1) != null && m.group(1) != 'transparent'))
          m
    ].length;
    return n;
  }

  test('literal type sizes per file: no file grows past its baseline', () {
    // Empty as of this pass: every literal type size is a role
    // (`sizeSm`/`sizeBody`/`sizeBodyLg`) or `size(n)` for the few steps that
    // have no role yet, so the number still rides the skin's scale and the
    // accessibility pass. The map stays so a new literal fails here.
    const Map<String, int> baseline = <String, int>{};
    final List<String> drifted = <String>[];
    for (final File f in scanned()) {
      final int n =
          fontSize.allMatches(withoutComments(f.readAsStringSync())).length;
      final int was = baseline[rel(f)] ?? 0;
      if (n > was) {
        drifted.add('${rel(f)}: $n literals, baseline $was — '
            'use skin.type.sizeSm / sizeBody / size(...) instead');
      } else if (n < was) {
        drifted.add('${rel(f)}: $n literals, baseline $was — lower the entry');
      }
    }
    expect(drifted, isEmpty, reason: drifted.join('\n'));
  });

  test('literal colours per file: no file grows past its baseline', () {
    // What is left is deliberate, and each entry says why. Everything else in
    // `lib/` takes its colours from the skin or from `viz_palette.dart`.
    const Map<String, int> baseline = <String, int>{
      // The vector style's own `background` layer colour, so an unloaded tile
      // reads as "land, not yet drawn". A guard test keeps it equal to the
      // style's background, which is why it cannot be a skin colour.
      'lib/maps/vector_basemap.dart': 1,
      // The QR field. A camera expects dark modules on a light field, so this
      // one surface does not follow the skin's ground; its shape does.
      'lib/screens/channels_screen.dart': 2,
      // DR Pop's Mondrian palette: seven deliberate colour fields, which are
      // the preset's identity rather than chrome.
      'lib/screens/chat_screen.dart': 7,
      'lib/screens/dashboards/drpop_dashboard.dart': 3,
      // The scanline overlay. A scanline is black by definition: it is a
      // darkening of whatever is under it, not a colour the theme chooses.
      'lib/ui/mm_scaffold.dart': 1,
    };
    final List<String> drifted = <String>[];
    for (final File f in scanned()) {
      final int n = countColours(withoutComments(f.readAsStringSync()));
      final int was = baseline[rel(f)] ?? 0;
      if (n > was) {
        drifted.add('${rel(f)}: $n literals, baseline $was — '
            'use skin.color.*, or a declared encoding in viz_palette');
      } else if (n < was) {
        drifted.add('${rel(f)}: $n literals, baseline $was — lower the entry');
      }
    }
    expect(drifted, isEmpty, reason: drifted.join('\n'));
  });

  test('a corner radius is never a bare number outside the token layer', () {
    // `lib/theme` builds the theme; `mm_shape` owns the constants and the
    // helper; the two older-preset dashboards predate the guard and are the
    // same two files the >=6px rule allows.
    const Set<String> allowed = <String>{
      'lib/ui/mm_shape.dart',
      'lib/screens/dashboards/aghud_dashboard.dart',
      'lib/screens/dashboards/hyperlocal_dashboard.dart',
    };
    final RegExp literal = RegExp(r'BorderRadius\.circular\(\s*[0-9.]');
    final List<String> bad = <String>[];
    for (final File f in scanned()) {
      if (allowed.contains(rel(f))) continue;
      if (literal.hasMatch(withoutComments(f.readAsStringSync()))) {
        bad.add('${rel(f)} — use kRadiusXs / kRadiusSm / kRadiusMd, or '
            'mmRadius(context, …) for a control surface');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
