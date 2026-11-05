// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/chat/history_retention_notice.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/chat_store.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/screens/chat_screen.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';

import 'fake_transport.dart';
import 'package:meshcore/meshcore.dart';

/// APP-E2 / register §2 "History threads, export, truncation visibility".
///
/// The 250-row cap used to truncate in silence, so a chat could lose its
/// oldest rows and read exactly like a chat that never had them. The count
/// is now carried per thread and said at the top of the thread, and it
/// survives the restart that hid the rows in the first place.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = Directory.systemTemp.createTempSync('mm_retention');
  });
  tearDown(() {
    ChatStore.cipherOverride = null;
    ChatStore.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// The sealed store. Only the two storage tests need it: the counts in the
  /// controller path are proven without it, and switching it on for a test
  /// that fires 250 unawaited saves would leave writes landing after the
  /// temp directory is gone.
  void useSealedStore() {
    ChatStore.cipherOverride = MemoryRecordCipher.random();
    ChatStore.directoryOverride = dir;
  }

  test('the row that the cap drops is counted, not just discarded', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await c.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);

    // One message over the cap: the oldest is evicted.
    for (int i = 0; i < ChatStore.cap + 1; i++) {
      await c.sendChannelText('m$i');
    }
    expect(c.messagesFor(0), hasLength(ChatStore.cap));
    expect(c.droppedForChannel(0), 1,
        reason: 'the first row is gone, and the thread says so');
    expect(c.messagesFor(0).first.text, 'm1');
    c.dispose();
  });

  test('the count is per thread and survives a reload', () async {
    useSealedStore();
    final ChatMessage dropped =
        ChatMessage(channelIdx: 3, text: 'old', outgoing: true);
    expect(ChatStore.threadKeyOf(dropped), 'ch:3');
    expect(
        ChatStore.threadKeyOf(ChatMessage(
            channelIdx: -1,
            text: 'dm',
            outgoing: true,
            peerPubKeyHex: 'aabbccddeeff0011')),
        'dm:aabbccddeeff');

    await ChatStore.saveDropped(<String, int>{'ch:3': 4, 'dm:aabbccddeeff': 2});
    final Map<String, int> back = await ChatStore.loadDropped();
    expect(back['ch:3'], 4);
    expect(back['dm:aabbccddeeff'], 2);

    // The sealed file is where it lives, and it is not readable as plain
    // numbers from the outside.
    final Uint8List onDisk = File(
            '${dir.path}${Platform.pathSeparator}mm_store.bin')
        .readAsBytesSync();
    expect(onDisk.sublist(0, 4), <int>[0x4D, 0x4D, 0x53, 0x31]);
  });

  test('a zero count is not stored, so a clean thread says nothing', () async {
    useSealedStore();
    await ChatStore.saveDropped(<String, int>{'ch:3': 0});
    expect(await ChatStore.loadDropped(), isEmpty);
  });

  testWidgets('the notice names the count and the rule; a clean thread shows '
      'nothing', (WidgetTester t) async {
    Future<void> show(int dropped) async {
      await t.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: HistoryRetentionNotice(dropped: dropped)),
      ));
    }

    await show(0);
    expect(find.textContaining('older message'), findsNothing);

    await show(3);
    expect(find.textContaining('3 older messages are gone'), findsOneWidget);
    expect(find.textContaining('newest 250'), findsOneWidget,
        reason: 'the rule is named, not just the number');

    await show(1);
    expect(find.textContaining('1 older message is gone'), findsOneWidget);
  });

  testWidgets('the chat thread carries the notice from the controller',
      (WidgetTester t) async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final TtsController tts = TtsController(speaker: _SilentTts());
    await t.pumpWidget(MaterialApp(
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
          providers: <SingleChildWidget>[
            ChangeNotifierProvider<MeshcoreController>.value(value: mc),
            ChangeNotifierProvider<TtsController>.value(value: tts),
          ],
          child: const ChatScreen(),
        ),
      ),
    ));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pump();
    expect(find.byType(HistoryRetentionNotice), findsOneWidget);
    expect(find.textContaining('older messages are gone'), findsNothing);

    for (int i = 0; i < ChatStore.cap + 1; i++) {
      await mc.sendChannelText('m$i');
    }
    await t.pump();
    expect(find.textContaining('1 older message is gone'), findsOneWidget);

    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}

class _SilentTts implements TtsSpeaker {
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
