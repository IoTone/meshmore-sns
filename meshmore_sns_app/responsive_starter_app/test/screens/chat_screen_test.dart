// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/chat/draft_store.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/screens/chat_screen.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

class FakeTtsSpeaker implements TtsSpeaker {
  final List<String> spoken = <String>[];
  @override
  Future<void> speak(String text) async => spoken.add(text);
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

Widget _host(MeshcoreController mc, TtsController tts) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<MeshcoreController>.value(value: mc),
            ChangeNotifierProvider<TtsController>.value(value: tts),
          ],
          child: const ChatScreen(),
        ),
      ),
    );

void main() {
  // TtsController.setEnabled persists via shared_preferences; without
  // a mock its platform channel never answers and the test hangs.
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('compose + send emits 0x03 and shows the line (R6)',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final TtsController tts = TtsController(speaker: FakeTtsSpeaker());
    await t.pumpWidget(_host(mc, tts));

    await mc.connect();
    fake.emit(selfInfoFrame()); // → ready
    await t.pumpAndSettle();

    expect(find.text('— no messages on this channel —'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'hello mesh');
    await t.tap(find.byIcon(Icons.send));
    await t.pumpAndSettle();

    expect(fake.sent.any((f) => f.isNotEmpty && f[0] == 0x03), isTrue);
    expect(find.text('hello mesh'), findsOneWidget);
    mc.dispose();
  });

  testWidgets('channel chips switch the active channel', (t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final TtsController tts = TtsController(speaker: FakeTtsSpeaker());
    await t.pumpWidget(_host(mc, tts));
    await mc.connect();
    fake.emit(selfInfoFrame()); // → ready
    await t.pump();
    fake.emit(channelInfoFrame(idx: 1, name: 'Ops'));
    await t.pump();

    // R91 — the selected chip is the header. There is no separate
    // "CHANNEL · NAME" caption repeating it.
    expect(find.text('CHANNEL · PUBLIC'), findsNothing);
    ChoiceChip selected() =>
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Public'));
    expect(selected().selected, isTrue);
    await t.tap(find.text('Ops'));
    await t.pump();
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Ops')).selected,
        isTrue);
    expect(mc.activeChannel, 1);
    mc.dispose();
  });

  testWidgets('long-press → Delete removes the row locally (R20)',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final TtsController tts = TtsController(speaker: FakeTtsSpeaker());
    await t.pumpWidget(_host(mc, tts));
    await mc.connect();
    fake.emit(selfInfoFrame()); // → ready
    await t.pump();
    fake.emit(channelMsgFrame(text: 'delete me'));
    await t.pump();
    expect(find.text('delete me'), findsOneWidget);

    await t.longPress(find.text('delete me'));
    await t.pumpAndSettle();
    expect(find.text('Delete locally'), findsOneWidget);
    await t.tap(find.text('Delete locally'));
    await t.pumpAndSettle();
    expect(find.text('Delete this message locally?'), findsOneWidget);
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();

    expect(find.text('delete me'), findsNothing);
    expect(mc.messagesFor(0).where((m) => m.text == 'delete me'),
        isEmpty);
    mc.dispose();
  });

  testWidgets('Reply prepends a quoted prefix into the composer (R20)',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final TtsController tts = TtsController(speaker: FakeTtsSpeaker());
    await t.pumpWidget(_host(mc, tts));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pump();
    fake.emit(channelMsgFrame(text: 'hey there'));
    await t.pump();

    await t.longPress(find.text('hey there'));
    await t.pumpAndSettle();
    await t.tap(find.text('Reply'));
    await t.pumpAndSettle();

    final TextField field =
        t.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, startsWith('> hey there'));
    mc.dispose();
  });

  // The screen must NOT speak on its own: playback moved to `CueBridge`
  // so a channel is heard whether or not you are looking at it. Both
  // halves of the old pair (on → spoken, off → silent) now live in
  // test/cue/cue_bridge_test.dart. This is the guard against someone
  // re-adding the subscription here and double-speaking every message.
  testWidgets('ChatScreen does not itself speak inbound messages (R5)',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final FakeTtsSpeaker spk = FakeTtsSpeaker();
    final TtsController on = TtsController(speaker: spk);
    await on.setEnabled(true); // everything permits speech...
    await t.pumpWidget(_host(mc, on));
    await mc.connect();
    fake.emit(selfInfoFrame()); // → ready
    await t.pump();
    fake.emit(channelMsgFrame(text: 'spoken aloud'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 10));
    // ...but no CueBridge is wired in this host, so nothing speaks.
    expect(spk.spoken, isEmpty);
    mc.dispose();
  });

  group('APP-D1/D2 composer budget and APP-E7 drafts', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('mm_drafts_w');
      DraftStore.cipherOverride = MemoryRecordCipher.random();
      DraftStore.directoryOverride = dir;
    });

    tearDown(() {
      DraftStore.cipherOverride = null;
      DraftStore.directoryOverride = null;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<MeshcoreController> open(WidgetTester t,
        FakeMeshcoreTransport fake) async {
      await t.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => fake,
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      );
      await t.pumpWidget(_host(mc, TtsController(speaker: FakeTtsSpeaker())));
      await mc.connect();
      fake.emit(selfInfoFrame());
      await t.pumpAndSettle();
      return mc;
    }

    testWidgets('the counter counts the bytes the radio counts', (t) async {
      final MeshcoreController mc = await open(t, FakeMeshcoreTransport(connected: true));
      // No name on the self-info frame: the fallback prefix is 8 bytes, so 152
      // of the radio's 160 remain, and the copy says the number is an estimate.
      expect(find.textContaining('about 152 of 160'), findsOneWidget);
      mc.dispose();
    });

    testWidgets('an over-long message is refused before it is sent', (t) async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await open(t, fake);
      await t.enterText(find.byType(TextField), 'a' * 160);
      await t.pump();
      await t.tap(find.byTooltip('Send'));
      await t.pump();
      // The counter and the refusal both say it, so the send icon cannot be
      // tapped into a silent truncation.
      expect(find.textContaining('Too long by 8 bytes'), findsWidgets);
      expect(mc.messagesFor(mc.activeChannel), isEmpty);
      mc.dispose();
    });

    testWidgets('typing is kept as a draft, and a stored one comes back',
        (t) async {
      final _MemoryDrafts sink = _MemoryDrafts();
      DraftStore.sinkOverride = sink;
      addTearDown(() => DraftStore.sinkOverride = null);
      await sink.save(
          DraftStore.keyFor(DraftStore.noRadio, channelIdx: 0), 'half a thought');

      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => fake,
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      );
      await t.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_host(mc, TtsController(speaker: FakeTtsSpeaker())));
      await t.pump();
      // The draft for this conversation is recalled into the composer.
      expect(find.text('half a thought'), findsOneWidget);

      // A new keystroke replaces it after one pause, not per character. The
      // composer only accepts typing once the radio has answered.
      await mc.connect();
      fake.emit(selfInfoFrame());
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'half a thought, finished');
      await t.pump(const Duration(milliseconds: 100));
      expect(sink.values.values, contains('half a thought'));
      await t.pumpAndSettle(DraftStore.debounce);
      await t.pump(DraftStore.debounce);
      expect(sink.values.values, contains('half a thought, finished'));
      mc.dispose();
    });
  });
}

class _MemoryDrafts implements DraftSink {
  final Map<String, String> values = <String, String>{};
  @override
  Future<String> read(String key) async => values[key] ?? '';
  @override
  Future<void> save(String key, String text) async {
    if (text.trim().isEmpty) {
      values.remove(key);
    } else {
      values[key] = text;
    }
  }

  @override
  Future<void> clear(String key) async => values.remove(key);
}

