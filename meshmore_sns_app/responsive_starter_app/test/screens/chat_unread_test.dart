// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/chat/channel_read_store.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/chat_screen.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/fake_transport.dart';
import '../screens/chat_screen_test.dart' show FakeTtsSpeaker;

/// Per-channel unread on the chip strip: a count appears for a channel the
/// reader has not opened, clears when they open it, and never counts a
/// blocked author.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Widget host(MeshcoreController mc, TtsController tts, BlockStore blocks,
      ChannelReadStore reads) {
    return MaterialApp(
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
            ChangeNotifierProvider<BlockStore>.value(value: blocks),
            ChangeNotifierProvider<ChannelReadStore?>.value(value: reads),
          ],
          child: const ChatScreen(),
        ),
      ),
    );
  }

  testWidgets('a second channel shows a count and opening it clears it',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final BlockStore blocks = BlockStore();
    final ChannelReadStore reads = ChannelReadStore();
    await t.pumpWidget(
        host(mc, TtsController(speaker: FakeTtsSpeaker()), blocks, reads));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    fake.emit(channelInfoFrame(idx: 1, name: 'Local'));
    await t.pumpAndSettle();

    // The active channel is 0, so a message on channel 1 is unread.
    fake.emit(channelMsgFrame(idx: 1, text: 'Trudy: the ford is high'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('unread-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('unread-0')), findsNothing,
        reason: 'the open channel is not unread to the person reading it');

    await t.tap(find.text('Local'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('unread-1')), findsNothing,
        reason: 'opening the channel moves the read mark past the message');
    expect(reads.lastReadAtMs(1), greaterThan(0));
    mc.dispose();
  });

  testWidgets('a blocked author cannot inflate a badge', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final BlockStore blocks = BlockStore(seed: <String, BlockedKey>{
      'a' * 64: BlockedKey(pubKeyHex: 'a' * 64, sinceMs: 1, name: 'Mallory'),
    });
    final ChannelReadStore reads = ChannelReadStore();
    await t.pumpWidget(
        host(mc, TtsController(speaker: FakeTtsSpeaker()), blocks, reads));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    fake.emit(channelInfoFrame(idx: 1, name: 'Local'));
    await t.pumpAndSettle();
    fake.emit(channelMsgFrame(idx: 1, text: 'Mallory: the ford is mined'));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('unread-1')), findsNothing);
    mc.dispose();
  });

  // The owner's report: a message arriving in the thread already on screen put
  // a count on that thread's own tag, for a frame, and the tag went dark with a
  // number in it. The count is computed before the read mark moves, so the badge
  // for the channel being read has to be removed from the map rather than drawn
  // and then cleared.
  testWidgets('the channel being read never badges its own tag',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final ChannelReadStore reads = ChannelReadStore();
    await t.pumpWidget(host(mc, TtsController(speaker: FakeTtsSpeaker()),
        BlockStore(), reads));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    // A message lands in the open channel (0) while the reader is at the
    // bottom of it.
    fake.emit(channelMsgFrame(idx: 0, text: 'Ada: bridge is clear'));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('unread-0')), findsNothing,
        reason: 'the thread on screen is being read as it arrives');
    mc.dispose();
  });
}
