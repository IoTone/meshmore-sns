// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/meshcore/ble_connector.dart';
import 'package:meshmore_sns_app/meshcore/failure.dart';

/// APP-N2 — one table, whole in both directions: a cause the firmware can send
/// has an entry, and a cause with an entry is emitted by code that can fail.
/// A table that only grows on one side is how a raw code or a bare "failed"
/// gets back in.
void main() {
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
  final AppLocalizations ja = lookupAppLocalizations(const Locale('ja'));

  test('every firmware ERR code has a catalogue entry', () {
    const List<int> modelled = <int>[
      kErrUnsupportedCmd,
      kErrNotFound,
      kErrTableFull,
      kErrIllegalArg,
      // 4 and 5 are in the firmware enum (`MyMesh.cpp:130-135`) but have no
      // constant in the codec; a radio can still send them.
      4,
      5,
    ];
    for (final int code in modelled) {
      expect(Failure.causeForDeviceError(code),
          isNot(FailureCause.unknownDeviceError),
          reason: 'ERR code $code would fall through to "unknown"');
    }
    expect(Failure.causeForDeviceError(99), FailureCause.unknownDeviceError);
    expect(Failure.causeForDeviceError(null), FailureCause.unknownDeviceError);
  });

  test('every cause has a sentence in both languages', () {
    for (final FailureCause cause in FailureCause.values) {
      final String text = failureText(en, Failure(cause)).trim();
      final String jp = failureText(ja, Failure(cause)).trim();
      expect(text, isNotEmpty, reason: '${cause.name} has no English copy');
      expect(jp, isNotEmpty, reason: '${cause.name} has no Japanese copy');
      expect(jp, isNot(text),
          reason: '${cause.name} was left untranslated (JA equals EN)');
      expect(RegExp(r'^code \d+$').hasMatch(text), isFalse,
          reason: '${cause.name} shows a bare code instead of a sentence');
    }
  });

  test('the MTU refusal names both numbers', () {
    final String text =
        failureText(en, const Failure(FailureCause.mtuTooSmall, mtu: 23));
    expect(text, contains('23'));
    expect(text, contains('${MeshcoreBle.requiredMtu}'));
  });

  test('a link failure is classified, never swallowed', () {
    expect(Failure.from(BleMtuTooSmall(23)).cause, FailureCause.mtuTooSmall);
    expect(Failure.from(BleConnectException(FailureCause.noRadioFound)).cause,
        FailureCause.noRadioFound);
    expect(Failure.from(StateError('unexpected')).cause,
        FailureCause.unknownDeviceError);
  });

  test('every cause a link can raise is emitted by real code', () {
    final StringBuffer all = StringBuffer();
    for (final File f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .where((File f) => !f.path.contains('/gen/'))
        .where((File f) => !f.path.endsWith('meshcore/failure.dart'))) {
      all.writeln(f.readAsStringSync());
    }
    final String text = all.toString();
    // Causes the app has not yet got a path for are named here rather than
    // silently tolerated, so the list can only shrink.
    // The six firmware causes are emitted through `causeForDeviceError`, which
    // the first test pins, not by a literal at a call site.
    const Set<FailureCause> byMapper = <FailureCause>{
      FailureCause.unsupportedCommand,
      FailureCause.notFound,
      FailureCause.tableFull,
      FailureCause.badState,
      FailureCause.fileIoError,
      FailureCause.illegalArgument,
      // Classified from the typed `BleMtuTooSmall` inside `Failure.from`, which
      // the scan excludes because it is the catalogue's own file.
      FailureCause.mtuTooSmall,
    };
    for (int code = 1; code <= 6; code++) {
      expect(byMapper.contains(Failure.causeForDeviceError(code)), isTrue,
          reason: 'ERR code $code has no cause');
    }
    const Set<FailureCause> notYetEmitted = <FailureCause>{
      FailureCause.unknownDeviceError,
      FailureCause.frameTruncated,
      FailureCause.frameTrailingBytes,
      FailureCause.storageFull,
      FailureCause.radioSilent,
    };
    for (final FailureCause cause in FailureCause.values) {
      if (notYetEmitted.contains(cause) || byMapper.contains(cause)) continue;
      expect(text.contains('FailureCause.${cause.name}'), isTrue,
          reason: '${cause.name} has a sentence but nothing emits it');
    }
  });

  test('no screen spells a numeric device code into user text', () {
    final RegExp rawCode = RegExp(r'\$\{[^}]*\.code[^}]*\}');
    for (final File f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) =>
            f.path.endsWith('.dart') &&
            (f.path.contains('/screens/') ||
                f.path.contains('/chat/') ||
                f.path.contains('/shell/')))) {
      expect(rawCode.hasMatch(f.readAsStringSync()), isFalse,
          reason: '${f.path} interpolates a numeric code into user text');
    }
  });
}
