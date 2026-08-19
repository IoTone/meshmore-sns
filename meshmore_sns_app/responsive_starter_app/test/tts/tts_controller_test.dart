// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeTtsSpeaker implements TtsSpeaker {
  final List<String> spoken = <String>[];
  int stops = 0;
  double? lastRate;
  double? lastPitch;
  TtsVoice? lastVoice;
  List<TtsVoice> voices = const <TtsVoice>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> setRate(double rate) async => lastRate = rate;

  @override
  Future<void> setPitch(double pitch) async => lastPitch = pitch;

  @override
  Future<void> setVoice(TtsVoice? voice) async => lastVoice = voice;

  @override
  Future<List<TtsVoice>> listVoices() async => voices;

  /// Locale → offline-availability lookup the test can stub.
  Map<String, bool> availability = const <String, bool>{};
  @override
  Future<bool> isLanguageAvailable(String locale) async =>
      availability[locale] ?? false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('speech obeys the audio master', () {
    test('audioMaster off silences the automatic path', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeTtsSpeaker spk = FakeTtsSpeaker();
      final ThemeController tc = ThemeController();
      final TtsController tts =
          TtsController(speaker: spk, theme: tc);
      await tts.setEnabled(true);

      expect(tts.speechAudible, isTrue);
      await tts.speakForChannel(0, 'audible');
      expect(spk.spoken, <String>['audible']);

      await tc.setAudioMaster(false);
      expect(tts.speechAudible, isFalse);
      expect(tts.channelSpeaks(0), isFalse,
          reason: 'the master mute outranks the per-channel state');
      await tts.speakForChannel(0, 'should not speak');
      expect(spk.spoken, <String>['audible']);
    });

    test('visualHapticOnly silences it too', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeTtsSpeaker spk = FakeTtsSpeaker();
      final ThemeController tc = ThemeController();
      final TtsController tts =
          TtsController(speaker: spk, theme: tc);
      await tts.setEnabled(true);

      await tc.setVisualHapticOnly(true);
      expect(tts.speechAudible, isFalse);
      await tts.speakForChannel(0, 'silent mode');
      expect(spk.spoken, isEmpty);
    });

    test('enabled state is preserved, not clobbered, by the master',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ThemeController tc = ThemeController();
      final TtsController tts =
          TtsController(speaker: FakeTtsSpeaker(), theme: tc);
      await tts.setEnabled(true);

      await tc.setAudioMaster(false);
      expect(tts.enabled, isTrue,
          reason: 'muting is not the same as turning speech off');
      await tc.setAudioMaster(true);
      expect(tts.channelSpeaks(0), isTrue);
    });

    test('notifies only when audibility flips, not on every theme change',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ThemeController tc = ThemeController();
      final TtsController tts =
          TtsController(speaker: FakeTtsSpeaker(), theme: tc);
      int notifications = 0;
      tts.addListener(() => notifications++);

      await tc.setFontScale(1.2); // unrelated theme change
      expect(notifications, 0);

      await tc.setAudioMaster(false); // flips audibility
      expect(notifications, 1);
    });

    test('no theme wired is permissive (tests, unwired call sites)',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeTtsSpeaker spk = FakeTtsSpeaker();
      final TtsController tts = TtsController(speaker: spk);
      await tts.setEnabled(true);
      expect(tts.speechAudible, isTrue);
      await tts.speakForChannel(0, 'hi');
      expect(spk.spoken, <String>['hi']);
    });

    test('preview is deliberately ungated — it is an explicit request',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeTtsSpeaker spk = FakeTtsSpeaker();
      final ThemeController tc = ThemeController();
      final TtsController tts =
          TtsController(speaker: spk, theme: tc);
      await tts.setEnabled(true);
      await tc.setAudioMaster(false);

      await tts.previewPhrase('sample');
      expect(spk.spoken, <String>['sample'],
          reason: 'choosing a voice while muted must still be possible');
    });
  });

  test('off by default; speak is a no-op until enabled (R5)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeTtsSpeaker spk = FakeTtsSpeaker();
    final TtsController tts = TtsController(speaker: spk);
    await tts.load();

    expect(tts.enabled, isFalse);
    expect(tts.channelSpeaks(0), isFalse);
    await tts.speakForChannel(0, 'hello');
    expect(spk.spoken, isEmpty);

    await tts.setEnabled(true);
    expect(tts.enabled, isTrue);
    expect(tts.channelSpeaks(0), isTrue);
    await tts.speakForChannel(0, 'hello');
    expect(spk.spoken, <String>['hello']);
  });

  test('per-channel mute gates speech without touching the global',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeTtsSpeaker spk = FakeTtsSpeaker();
    final TtsController tts = TtsController(speaker: spk);
    await tts.setEnabled(true);

    tts.toggleChannelMute(2);
    expect(tts.isChannelMuted(2), isTrue);
    expect(tts.channelSpeaks(2), isFalse);
    expect(tts.channelSpeaks(0), isTrue); // others unaffected
    await tts.speakForChannel(2, 'muted');
    await tts.speakForChannel(0, 'audible');
    expect(spk.spoken, <String>['audible']);

    tts.toggleChannelMute(2); // unmute
    expect(tts.channelSpeaks(2), isTrue);
  });

  test('global flag persists; disabling stops the speaker', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeTtsSpeaker spk = FakeTtsSpeaker();
    final TtsController a = TtsController(speaker: spk);
    await a.setEnabled(true);
    expect(spk.stops, 0);
    await a.setEnabled(false);
    expect(spk.stops, 1);

    // A fresh controller reads back the persisted (false) value.
    final TtsController b = TtsController(speaker: FakeTtsSpeaker());
    await b.load();
    expect(b.enabled, isFalse);

    SharedPreferences.setMockInitialValues(<String, Object>{'mm.tts': true});
    final TtsController c = TtsController(speaker: FakeTtsSpeaker());
    await c.load();
    expect(c.enabled, isTrue);
  });
}
