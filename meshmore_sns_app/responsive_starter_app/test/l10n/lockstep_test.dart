// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// EN and JA ship together or the app lies in one of its two languages.
///
/// Four things can go wrong, and each one is silent on the phone: a key added
/// to EN only (the JA build shows English or throws), a key removed from EN but
/// left in JA (dead weight that hides the stale use), a translation that drops
/// a `{placeholder}` (the sentence loses its subject), and a generated getter
/// that no longer matches the ARB files (a hand-edited `lib/gen`, which the
/// next `flutter gen-l10n` would silently undo).
///
/// The sources are read as files, not through `AppLocalizations`, because the
/// point is to catch the state before generation.
void main() {
  Map<String, dynamic> read(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  /// Message keys only: `@@locale` is metadata and `@key` entries are the
  /// per-message annotations flutter_intl writes, which JA legitimately omits.
  Set<String> messages(Map<String, dynamic> arb) => <String>{
        for (final String k in arb.keys)
          if (!k.startsWith('@')) k,
      };

  /// The `{name}` tokens in a message, as a sorted list.
  List<String> placeholders(Object? message) {
    if (message is! String) return const <String>[];
    final List<String> out = <String>[
      for (final RegExpMatch m
          in RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}').allMatches(message))
        m.group(1)!,
    ]..sort();
    return out;
  }

  late final Map<String, dynamic> en =
      read('lib/l10n/app_en.arb');
  late final Map<String, dynamic> ja =
      read('lib/l10n/app_ja.arb');
  late final Set<String> enKeys = messages(en);
  late final Set<String> jaKeys = messages(ja);

  test('every EN message has a JA translation, and nothing is JA-only', () {
    final List<String> missingInJa =
        (enKeys.difference(jaKeys).toList()..sort());
    final List<String> missingInEn =
        (jaKeys.difference(enKeys).toList()..sort());

    expect(missingInJa, isEmpty,
        reason: 'these keys exist in app_en.arb only, so the Japanese build '
            'has no string for them: ${missingInJa.join(', ')}');
    expect(missingInEn, isEmpty,
        reason: 'these keys exist in app_ja.arb only, so nothing can ever '
            'read them: ${missingInEn.join(', ')}');
  });

  test('a translation keeps every placeholder the English message has', () {
    final List<String> broken = <String>[];
    for (final String key in enKeys.intersection(jaKeys)) {
      final List<String> want = placeholders(en[key]);
      final List<String> got = placeholders(ja[key]);
      if (want.join(',') != got.join(',')) {
        broken.add('$key (en: ${want.join(',')}; ja: ${got.join(',')})');
      }
    }
    expect(broken, isEmpty,
        reason: 'a placeholder dropped in translation is data the user never '
            'sees: ${broken.join(' | ')}');
  });

  test('the generated localizations match the ARB message set', () {
    final String gen =
        File('lib/gen/app_localizations.dart').readAsStringSync();
    final Set<String> getters = <String>{
      for (final RegExpMatch m
          in RegExp(r'String\s+(?:get\s+)?([a-z][A-Za-z0-9]*)\s*[;(]')
              .allMatches(gen))
        m.group(1)!,
    }..removeWhere((String k) => k == 'get');

    final List<String> notGenerated =
        (enKeys.difference(getters).toList()..sort());
    expect(notGenerated, isEmpty,
        reason: 'these ARB keys have no generated accessor, so `lib/gen` is '
            'stale — run `flutter gen-l10n`: ${notGenerated.join(', ')}');
  });

  test('every message key is read somewhere in the app', () {
    // One pass over the sources, then a set difference: 1,300 keys against
    // 200 files must stay a fast test.
    final Set<String> used = <String>{};
    final List<File> sources = <FileSystemEntity>[
      ...Directory('lib').listSync(recursive: true),
      ...Directory('test').listSync(recursive: true),
    ]
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();
    final RegExp member = RegExp(r'\.([a-z][A-Za-z0-9]*)\b');
    for (final File f in sources) {
      if (f.path.contains('lib/gen/')) continue;
      for (final RegExpMatch m in member.allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }

    final List<String> orphans =
        (enKeys.difference(used).toList()..sort());
    expect(orphans, isEmpty,
        reason: 'these keys are translated, generated and read by nothing — '
            'delete them from both ARB files: ${orphans.join(', ')}');
  });
}
