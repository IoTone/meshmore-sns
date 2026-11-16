// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/chat_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';
import 'package:meshcore/meshcore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ChatMessage JSON round-trips (in + out)', () {
    final ChatMessage incoming = ChatMessage(
      channelIdx: 2,
      text: 'hello ✓',
      outgoing: false,
      at: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      snrDb: -7.5,
      isFlood: true,
    );
    final ChatMessage r = ChatMessage.fromJson(incoming.toJson());
    expect(r.channelIdx, 2);
    expect(r.text, 'hello ✓');
    expect(r.outgoing, isFalse);
    expect(r.at, incoming.at);
    expect(r.snrDb, -7.5);
    expect(r.isFlood, isTrue);

    final ChatMessage out = ChatMessage(
        channelIdx: 0, text: 'sent', outgoing: true);
    final ChatMessage ro = ChatMessage.fromJson(out.toJson());
    expect(ro.outgoing, isTrue);
    expect(ro.snrDb, isNull);
    expect(ro.isFlood, isFalse);
  });

  group('ChatStore', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('save → load preserves messages; clear empties', () async {
      final List<ChatMessage> msgs = <ChatMessage>[
        ChatMessage(channelIdx: 0, text: 'a', outgoing: true),
        ChatMessage(channelIdx: 0, text: 'b', outgoing: false),
      ];
      await ChatStore.save(msgs);
      final List<ChatMessage> back = await ChatStore.load();
      expect(back.map((ChatMessage m) => m.text), <String>['a', 'b']);

      await ChatStore.clear();
      expect(await ChatStore.load(), isEmpty);
    });

    test('save caps to the newest ChatStore.cap entries', () async {
      final List<ChatMessage> many = <ChatMessage>[
        for (int i = 0; i < ChatStore.cap + 30; i++)
          ChatMessage(channelIdx: 0, text: 'm$i', outgoing: false),
      ];
      await ChatStore.save(many);
      final List<ChatMessage> back = await ChatStore.load();
      expect(back.length, ChatStore.cap);
      expect(back.first.text, 'm30'); // oldest 30 dropped
      expect(back.last.text, 'm${ChatStore.cap + 29}');
    });

    test('the cap is per thread, which is what the settings page promises',
        () async {
      // Three channels, each with more than the cap. The cap used to be applied
      // to the whole list, so three channels shared 250 rows while the page said
      // "the newest 250 messages per channel".
      final List<ChatMessage> many = <ChatMessage>[
        for (int ch = 0; ch < 3; ch++)
          for (int i = 0; i < ChatStore.cap + 10; i++)
            ChatMessage(channelIdx: ch, text: 'c$ch-$i', outgoing: false),
      ];
      final List<ChatMessage> kept = ChatStore.capPerThread(many);
      expect(kept.length, ChatStore.cap * 3);
      for (int ch = 0; ch < 3; ch++) {
        final List<ChatMessage> mine =
            kept.where((ChatMessage m) => m.channelIdx == ch).toList();
        expect(mine.length, ChatStore.cap, reason: 'channel $ch');
        expect(mine.first.text, 'c$ch-10', reason: 'the oldest ten go');
        expect(mine.last.text, 'c$ch-${ChatStore.cap + 9}');
      }
    });

    test('clearing the history leaves the other sealed records alone',
        () async {
      // `mm_store.bin` holds ten records. `clear()` used to delete the file, so
      // "Delete everything" also took the block list, the contact table, the
      // fences and every unsent draft.
      final Directory dir = Directory.systemTemp.createTempSync('chat_clear');
      final MemoryRecordCipher cipher = MemoryRecordCipher.random();
      ChatStore.cipherOverride = cipher;
      ChatStore.directoryOverride = dir;
      BlockStore.cipherOverride = cipher;
      BlockStore.directoryOverride = dir;
      addTearDown(() {
        ChatStore.cipherOverride = null;
        ChatStore.directoryOverride = null;
        BlockStore.cipherOverride = null;
        BlockStore.directoryOverride = null;
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final BlockStore blocks = BlockStore();
      await blocks.load();
      expect(
          await blocks.block(BlockedKey(
            pubKeyHex: 'a' * 64,
            name: 'Ada',
            sinceMs: 1,
          )),
          isTrue);
      await ChatStore.save(<ChatMessage>[
        ChatMessage(channelIdx: 0, text: 'gone', outgoing: false),
      ]);
      await ChatStore.clear();
      expect(await ChatStore.load(), isEmpty);
      final BlockStore after = BlockStore();
      await after.load();
      expect(after.all.map((BlockedKey b) => b.name), <String>['Ada'],
          reason: 'the block list is a setting, and the dialog says settings '
              'stay');
    });

    test('corrupt store loads clean (no throw)', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'mm.chat.v1': 'not json'});
      expect(await ChatStore.load(), isEmpty);
    });
  });

  group('controller persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('restores persisted history on construction', () async {
      final List<ChatMessage> seed = <ChatMessage>[
        ChatMessage(channelIdx: 0, text: 'earlier public msg',
            outgoing: false),
      ];
      await ChatStore.save(seed); // persist before constructing

      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController ctrl =
          MeshcoreController(transportFactory: () async => fake);
      // The store is a sealed file, so the restore is asynchronous. Waiting a
      // fixed 20 ms made this pass or fail on how loaded the machine was.
      await ctrl.historyRestored;
      expect(ctrl.messagesFor(0).map((m) => m.text),
          contains('earlier public msg'));
      ctrl.dispose();
    });

    test('sent + received messages are persisted', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController ctrl = MeshcoreController(
        transportFactory: () async => fake,
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      );
      await ctrl.connect();
      fake.emit(selfInfoFrame()); // → ready
      await Future<void>.delayed(Duration.zero);

      await ctrl.sendChannelText('outgoing one');
      fake.emit(channelMsgFrame(text: 'incoming one'));
      // The history is written on a 400 ms window rather than once per message,
      // because a full sealed rewrite per ingest was the most expensive thing
      // the app did per frame. Wait the window out; the dispose path flushes
      // whatever is still pending, which the next case covers.
      await Future<void>.delayed(const Duration(milliseconds: 450));

      final List<ChatMessage> persisted = await ChatStore.load();
      final Iterable<String> texts =
          persisted.map((ChatMessage m) => m.text);
      expect(texts, containsAll(<String>['outgoing one', 'incoming one']));
      ctrl.dispose();
    });
  });

  group('the write window', () {
    test('dispose flushes history that has not been written yet', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController ctrl = MeshcoreController(
        transportFactory: () async => fake,
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      );
      await ctrl.connect();
      fake.emit(selfInfoFrame());
      await Future<void>.delayed(Duration.zero);
      fake.emit(channelMsgFrame(text: 'inside the window'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Well inside the 400 ms window: nothing has been sealed yet.
      expect((await ChatStore.load()).map((ChatMessage m) => m.text),
          isNot(contains('inside the window')));
      ctrl.dispose();
      // The flush is a real write, so give the event loop one turn.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((await ChatStore.load()).map((ChatMessage m) => m.text),
          contains('inside the window'));
    });
  });
}
