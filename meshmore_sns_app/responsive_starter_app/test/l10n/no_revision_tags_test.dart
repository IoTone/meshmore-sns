// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Seen on the phone, Settings hub: "Meshcore radio & device (R7)". The R-number
/// is a spec revision tag; it means nothing to the person reading the screen.
/// Four strings carried one ("(R5)", "(R7)", "(R12)", "(R13)"), in EN and JA.
void main() {
  for (final String lang in <String>['en', 'ja']) {
    test('no "(R<n>)" revision tag reaches a user-facing $lang string', () {
      final Map<String, dynamic> arb = jsonDecode(
          File('lib/l10n/app_$lang.arb').readAsStringSync())
          as Map<String, dynamic>;
      final RegExp tag = RegExp(r'\(R\d+\)');
      final List<String> leaks = <String>[
        for (final MapEntry<String, dynamic> e in arb.entries)
          if (!e.key.startsWith('@') &&
              e.value is String &&
              tag.hasMatch(e.value as String))
            '${e.key}: ${e.value}',
      ];
      expect(leaks, isEmpty);
    });
  }
}
