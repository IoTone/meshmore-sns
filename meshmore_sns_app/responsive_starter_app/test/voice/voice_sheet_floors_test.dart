// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/media/media_codec.dart';
import 'package:meshmore_sns_app/media/media_transfer.dart';
import 'package:meshmore_sns_app/meshcore/airtime.dart';
import 'package:meshmore_sns_app/meshcore/channel_datagram.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/voice/voice_capture.dart';
import 'package:meshmore_sns_app/voice/voice_codec.dart';
import 'package:meshmore_sns_app/voice/voice_composer.dart';
import 'package:meshmore_sns_app/voice/voice_inbox.dart';
import 'package:meshmore_sns_app/voice/voice_notes_sheet.dart';
import 'package:meshmore_sns_app/voice/voice_payload.dart';
import 'package:meshmore_sns_app/voice/voice_playback.dart';

import '../support/fake_voice_codec.dart';

/// The two voice surfaces at the accessibility floor: 320 dp wide, 200 % text,
/// in every preset.
///
/// The composer carries up to four controls in one row and the notes sheet
/// carries a title, a hint, a list and a close. Both are drawn inside a bottom
/// sheet, which cannot scroll away from an overflow — a stack of buttons that
/// does not fit is clipped instead, so the shape has to stack or the last
/// control is unreachable. A widget test can prove that; it cannot prove a
/// preset looks right, which is the recorded limit of this check.

final class _ReadyCapture implements VoiceCapture {
  Uint8List pcm = pcmOf(50, (int f) => 100 + f);

  @override
  Duration get limit => kVoiceMaxDuration;

  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<VoiceRecording> stop() async =>
      VoiceRecording(pcm: pcm, stoppedAtCeiling: false);
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

MediaTransferService _service() => MediaTransferService(
      codec: FakeMediaCodec(),
      estimator: const AirtimeEstimator(millisPerByte: 4),
      clock: () => DateTime(2026, 11, 10, 9),
      newPayloadId: () => 91,
      wait: (Duration d) async {},
    );

Widget _host(Widget child, ThemeController theme) =>
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: child),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  for (final MmThemePreset preset in MmThemePreset.values) {
    testWidgets('the composer holds the floor on ${preset.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final ThemeController theme = ThemeController();
      await theme.setPreset(preset);
      final _ReadyCapture capture = _ReadyCapture();
      await t.pumpWidget(_host(
        VoiceComposer(
          service: _service(),
          capture: capture,
          codec: FakeVoiceCodec(modes: VoiceMode.values.toSet()),
          channelPsk: const <int>[1, 2, 3],
          playback: SilentVoicePlayback(),
          sendBlob: (Uint8List blob) async =>
              const ChannelDataSendResult(ChannelDataSendStatus.accepted),
        ),
        theme,
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull,
          reason: 'the idle sheet overflowed at 320 dp / 200 %');
      // The ready state is the widest: preview, discard, close and send. The
      // controls sit past the fold at this size, which is why the sheet
      // scrolls — a button clipped by the sheet itself could not be tapped at
      // all, and this tap is the proof that it can.
      await t.ensureVisible(find.byKey(const ValueKey<String>('voice-record')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('voice-record')));
      await t.pump();
      await t.ensureVisible(find.byKey(const ValueKey<String>('voice-stop')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('voice-stop')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull,
          reason: 'the ready sheet overflowed at 320 dp / 200 %');
    });

    testWidgets('the notes sheet holds the floor on ${preset.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final ThemeController theme = ThemeController();
      await theme.setPreset(preset);
      final PackedVoice packed = FakeVoiceCodec(
              modes: VoiceMode.values.toSet())
          .encode(pcmOf(500, (int f) => f), mode: VoiceMode.narrowband);
      final ReceivedVoice note = ReceivedVoice(
        payloadId: 1,
        channelIndex: 0,
        receivedAt: DateTime(2026, 11, 10, 9, 30),
        payload: VoicePayloadCodec.encode(packed),
        mode: packed.mode,
        frames: packed.frames,
        samples: packed.samples,
      );
      await t.pumpWidget(_host(
        VoiceNotesSheet(
          notes: <ReceivedVoice>[note],
          codec: FakeVoiceCodec(modes: VoiceMode.values.toSet()),
          playback: SilentVoicePlayback(),
        ),
        theme,
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull,
          reason: 'the notes sheet overflowed at 320 dp / 200 %');
      expect(find.byKey(const ValueKey<String>('voice-note-1')), findsOneWidget);
    });
  }
}
