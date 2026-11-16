// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The owner's rule (2026-11-06): "we should always say LoRa radio, or MeshCore
/// radio". A bare "radio" leaves a reader guessing which one, and the app talks
/// to exactly one kind of device.
///
/// The rule is enforced here rather than remembered, because 164 strings broke
/// it and a style note does not survive the next hurried edit. A string may use
/// the bare word once it has already named the radio in the same sentence, which
/// is how English avoids repeating a noun.
void main() {
  final RegExp bare = RegExp(
      r'(?<!MeshCore )(?<!LoRa )(?<!MeshCore-)(?<!LoRa-)\bradio\b',
      caseSensitive: false);

  /// Strings that keep a bare "radio", each for a reason.
  const Map<String, String> allowed = <String, String>{
    'mapKeyClient': 'a legend mark under a heading that already names the radio',
    'rxViaSecondary': 'a profile label, two words wide',
  };

  test('every English string names which radio it means', () {
    final Map<String, dynamic> strings = jsonDecode(
            File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    final List<String> offenders = <String>[];
    for (final MapEntry<String, dynamic> e in strings.entries) {
      if (e.key.startsWith('@')) continue;
      final String v = '${e.value}';
      if (!bare.hasMatch(v)) continue;
      if (allowed.containsKey(e.key)) continue;
      // A string that already qualifies the radio may use the short word after
      // that, which is what a sentence does.
      if (v.contains('MeshCore radio') || v.contains('LoRa radio')) continue;
      offenders.add('${e.key} = $v');
    }
    expect(offenders, isEmpty,
        reason: 'these strings say "radio" without saying which:\n'
            '${offenders.join('\n')}');
  });

  test('the Japanese uses one word for the device', () {
    final Map<String, dynamic> strings = jsonDecode(
            File('lib/l10n/app_ja.arb').readAsStringSync())
        as Map<String, dynamic>;
    final List<String> offenders = <String>[];
    for (final MapEntry<String, dynamic> e in strings.entries) {
      if (e.key.startsWith('@')) continue;
      final String v = '${e.value}';
      // ラジオ and 無線機 were mixed inside single screens. 無線機 is the word
      // the rest of the app uses for the device.
      if (v.contains('ラジオ')) offenders.add('${e.key} = $v');
    }
    expect(offenders, isEmpty,
        reason: 'these strings use the older word for the radio:\n'
            '${offenders.join('\n')}');
  });

  test('the allowance list stays honest', () {
    final Map<String, dynamic> strings = jsonDecode(
            File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    for (final String key in allowed.keys) {
      expect(strings.containsKey(key), isTrue,
          reason: '$key is allowed but no longer exists');
      expect(bare.hasMatch('${strings[key]}'), isTrue,
          reason: '$key no longer needs its allowance');
    }
  });
}
