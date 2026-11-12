// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/media/media_chunk.dart';
import 'package:meshmore_sns_app/media/media_inbox.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/chat_screen.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';
import 'package:meshmore_sns_app/voice/voice_capture.dart';
import 'package:meshmore_sns_app/voice/voice_codec.dart';
import 'package:meshmore_sns_app/voice/voice_inbox.dart';
import 'package:meshmore_sns_app/voice/voice_payload.dart';
import 'package:meshmore_sns_app/voice/voice_playback.dart';

import '../meshcore/fake_transport.dart';
import '../support/fake_voice_codec.dart';

/// The two voice controls the chat surface owns.
///
/// The composer is proved on its own; what this pins is the wiring: the mic sits
/// beside the attach control and opens the note sheet, and the strip's notes
/// control opens what this session has taken off the channel — with the count
/// the badge shows, which is the only reason a reader knows there is anything
/// there.

class _SilentSpeaker implements TtsSpeaker {
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> setVoice(TtsVoice? voice) async {}
  @override
  Future<List<TtsVoice>> listVoices() async => const <TtsVoice>[];
  @override
  Future<bool> isLanguageAvailable(String locale) async => true;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<(MeshcoreController, VoiceInbox, StreamController<MediaInboxPayload>)>
      pumpChat(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final ThemeController theme = ThemeController();
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final StreamController<MediaInboxPayload> completed =
        StreamController<MediaInboxPayload>.broadcast();
    final VoiceInbox inbox = VoiceInbox(completed: completed.stream)..start();
    final SilentVoicePlayback playback = SilentVoicePlayback();
    await t.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<TtsController>.value(
            value: TtsController(speaker: _SilentSpeaker())),
        ChangeNotifierProvider<VoiceInbox?>.value(value: inbox),
        Provider<VoiceCodec?>.value(
            value: FakeVoiceCodec(modes: VoiceMode.values.toSet())),
        Provider<VoiceCapture?>.value(value: _FakeCapture()),
        Provider<VoicePlayback?>.value(value: playback),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: ChatScreen()),
      ),
    ));
    await mc.connect();
    fake.emit(selfInfoFrame());

    // Media and voice belong on a private channel: the public one hides them,
    // because every repeater in range re-transmits the chunks. This test runs on
    // slot 0 with a private key, which is the same thing to the composer.
    await t.pumpAndSettle();
    await mc.setChannel(idx: 0, name: 'Team', psk: List<int>.filled(16, 7));
    await t.pumpAndSettle();
    return (mc, inbox, completed);
  }

  testWidgets('the mic and the notes control are on the chat surface',
      (t) async {
    final (MeshcoreController mc, VoiceInbox _, StreamController<MediaInboxPayload> done) =
        await pumpChat(t);
    expect(find.byKey(const ValueKey<String>('chat-voice')), findsOneWidget);
    // The notes control is inside the strip's overflow menu rather than beside
    // the channel names, so it is proved by opening that menu.
    await t.tap(find.byKey(const ValueKey<String>('chat-overflow')));
    await t.pumpAndSettle();
    expect(
        find.byKey(const ValueKey<String>('chat-voice-notes')), findsOneWidget);
    mc.dispose();
    await done.close();
  });

  testWidgets('the mic opens the note sheet, which states the ceiling',
      (t) async {
    final (MeshcoreController mc, VoiceInbox _, StreamController<MediaInboxPayload> done) =
        await pumpChat(t);
    await t.tap(find.byKey(const ValueKey<String>('chat-voice')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('voice-limit')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('voice-record')), findsOneWidget);
    // Close the sheet so the controller's pollers are not still alive at
    // teardown.
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    mc.dispose();
    await done.close();
  });

  testWidgets('the notes control opens what the channel has taken', (t) async {
    final (MeshcoreController mc, VoiceInbox inbox,
            StreamController<MediaInboxPayload> done) =
        await pumpChat(t);
    // Nothing yet: the sheet says so rather than showing an empty list.
    await t.tap(find.byKey(const ValueKey<String>('chat-overflow')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('chat-voice-notes')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('voice-notes-empty')),
        findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    // One note arrives on slot 0, which is the active channel the fresh
    // controller opens on.
    final PackedVoice packed = FakeVoiceCodec(modes: VoiceMode.values.toSet())
        .encode(pcmOf(50, (int f) => 7 + f), mode: VoiceMode.narrowband);
    done.add(MediaInboxPayload(
      payloadId: 4242,
      kind: MediaKind.voice,
      channelIndex: mc.activeChannel,
      receivedAt: DateTime(2026, 11, 10, 9, 30),
      bytes: VoicePayloadCodec.encode(packed),
    ));
    await t.pumpAndSettle();
    expect(inbox.countFor(mc.activeChannel), 1);
    // The count rides in the menu row's label.
    await t.tap(find.byKey(const ValueKey<String>('chat-overflow')));
    await t.pumpAndSettle();
    expect(find.text('Voice notes (1)'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('chat-voice-notes')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('voice-note-4242')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('voice-notes-empty')),
        findsNothing);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    mc.dispose();
    await done.close();
  });
}

final class _FakeCapture implements VoiceCapture {
  @override
  Duration get limit => kVoiceMaxDuration;

  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<VoiceRecording> stop() async =>
      VoiceRecording(pcm: Uint8List(0), stoppedAtCeiling: false);
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}
