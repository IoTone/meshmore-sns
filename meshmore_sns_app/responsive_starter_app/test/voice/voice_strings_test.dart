// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/voice/voice_copy.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';

/// The voice feature's copy, in both languages.
///
/// `lockstep_test.dart` proves EN and JA agree key-for-key; this names the
/// strings the feature actually needs, because a feature whose copy is missing
/// fails at the call site rather than in the ARB. Two are load-bearing: the
/// 20-second limit has to be stated before the microphone opens, and a take
/// that stopped by itself has to say so — both were decisions, not decoration.
void main() {
  const List<String> required = <String>[
    'voiceTitle',
    'voiceLimit',
    'voiceRecord',
    'voiceStop',
    'voiceDiscard',
    'voiceStoppedAtLimit',
    'voiceNoMicrophone',
    'voiceNoCodec',
    'voiceCost',
  ];

  Map<String, dynamic> read(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  test('every voice string is in both ARBs', () {
    final Map<String, dynamic> en = read('lib/l10n/app_en.arb');
    final Map<String, dynamic> ja = read('lib/l10n/app_ja.arb');
    for (final String key in required) {
      expect(en.containsKey(key), isTrue, reason: 'EN is missing $key');
      expect(ja.containsKey(key), isTrue, reason: 'JA is missing $key');
      expect(en[key], isNotEmpty, reason: 'EN $key is empty');
      expect(ja[key], isNotEmpty, reason: 'JA $key is empty');
    }
    // The two sentences that carry a decision, not decoration.
    expect(en['voiceLimit'], contains('20'),
        reason: 'the limit is stated before the microphone opens');
    expect(ja['voiceLimit'], contains('20'));
    expect(en['voiceStoppedAtLimit'], isNotEmpty);
    expect(ja['voiceStoppedAtLimit'], isNotEmpty);
  });

  test('the copy seam reads every string, in both languages', () {
    for (final Locale locale in <Locale>[Locale('en'), Locale('ja')]) {
      final VoiceCopy copy = VoiceCopy(lookupAppLocalizations(locale));
      expect(copy.title, isNotEmpty);
      expect(copy.limit, contains('20'),
          reason: 'the limit is stated before the microphone opens');
      expect(copy.record, isNotEmpty);
      expect(copy.stop, isNotEmpty);
      expect(copy.discard, isNotEmpty);
      expect(copy.stoppedAtLimit, isNotEmpty);
      expect(copy.noMicrophone, isNotEmpty);
      expect(copy.noCodec, isNotEmpty);
      // The cost line takes its numbers and returns a sentence in both
      // languages, which is what a composer needs before a send.
      expect(
          copy.cost(
              datagrams: 12,
              airtime: const Duration(seconds: 9),
              mode: '700C'),
          allOf(contains('12'), contains('9'), contains('700C')));
    }
    expect(
        VoiceCopy(lookupAppLocalizations(const Locale('ja')))
            .cost(datagrams: 12, airtime: const Duration(seconds: 9), mode: '700C'),
        isNot(VoiceCopy(lookupAppLocalizations(const Locale('en')))
            .cost(datagrams: 12, airtime: const Duration(seconds: 9), mode: '700C')),
        reason: 'the sentence is translated, not copied');
  });

  test('every locale the app supports has the strings', () {
    for (final Locale locale in LocaleController.supported) {
      final VoiceCopy copy = VoiceCopy(lookupAppLocalizations(locale));
      expect(copy.stoppedAtLimit, isNotEmpty, reason: locale.languageCode);
    }
  });
}
