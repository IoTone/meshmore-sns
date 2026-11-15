// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The owner's copy rules, as a test rather than a habit.
///
/// Two of them are mechanical, so they were measured on this codebase and the
/// answer was 73 em dashes and 38 semicolons in the English strings. A rule
/// that lives only in a style note decays the moment somebody is in a hurry, so
/// it lives here: a semicolon joins two sentences a reader has to unpick, and an
/// em dash is a joining device that a full stop says more plainly.
void main() {
  Map<String, dynamic> arb(String locale) => jsonDecode(
      File('lib/l10n/app_$locale.arb').readAsStringSync()) as Map<String, dynamic>;

  for (final String locale in <String>['en', 'ja']) {
    test('the $locale strings use no em dash and no semicolon', () {
      final Map<String, dynamic> strings = arb(locale);
      final List<String> offenders = <String>[];
      for (final MapEntry<String, dynamic> e in strings.entries) {
        if (e.key.startsWith('@')) continue;
        final String v = '${e.value}';
        if (v.contains('\u2014') || v.contains(';')) {
          offenders.add('${e.key} = $v');
        }
      }
      expect(offenders, isEmpty,
          reason: 'these strings break the copy rules:\n'
              '${offenders.join('\n')}');
    });

    test('the $locale strings carry no bold, and no double space', () {
      final Map<String, dynamic> strings = arb(locale);
      for (final MapEntry<String, dynamic> e in strings.entries) {
        if (e.key.startsWith('@')) continue;
        final String v = '${e.value}';
        expect(v.contains('**'), isFalse, reason: '${e.key} uses bold');
        expect(v.contains('  '), isFalse, reason: '${e.key} has a double space');
      }
    });
  }
}
