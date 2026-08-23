// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart' show kPublicChannelPsk;
import 'package:meshmore_sns_app/bot/bot_bridge.dart';
import 'package:meshmore_sns_app/bot/bot_controller.dart';
import 'package:meshmore_sns_app/bot/bot_guards.dart';
import 'package:meshmore_sns_app/bot/bot_scope.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/fake_transport.dart';

List<int> privatePsk() =>
    List<int>.generate(kPublicChannelPsk.length, (int i) => (i * 5 + 1) & 0xff);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<
      ({
        MeshcoreController mc,
        FakeMeshcoreTransport fake,
        BotController bot,
        BotBridge bridge,
      })> rig() async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    final BotController bot = BotController(
      pskFor: (int _) => privatePsk(),
      now: () => DateTime.utc(2026, 1, 1, 12),
      rateLimit: const BotRateLimit(
          minInterval: Duration.zero, maxPerWindow: 1000),
    );
    final BotBridge bridge = BotBridge(mc, bot);
    await mc.connect();
    // SelfInfo is what makes the link `ready`; without it every send
    // silently early-returns and the bot looks broken.
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);
    // Reaching `ready` also kicks off the queue drain, and the bot
    // deliberately stays quiet while that runs. Finish it, or every
    // test here would pass for the wrong reason.
    for (int i = 0; i < 8 && mc.isDraining; i++) {
      fake.emit(noMoreMessagesFrame());
      await Future<void>.delayed(Duration.zero);
    }
    return (mc: mc, fake: fake, bot: bot, bridge: bridge);
  }

  test('an inbound channel message on a bound slot gets a labelled reply',
      () async {
    final rec = await rig();
    await rec.bot.setEnabled(const ChannelScope(2), true);

    rec.fake.emit(channelMsgFrame(idx: 2, text: 'ping'));
    await Future<void>.delayed(Duration.zero);

    final List<ChatMessage> out = rec.mc
        .messagesFor(2)
        .where((ChatMessage m) => m.outgoing)
        .toList();
    expect(out, hasLength(1));
    expect(out.single.text, '[bot] pong 1');
    rec.bridge.dispose();
    rec.mc.dispose();
  });

  // The bot may be bound to a private slot while the user is looking
  // at another channel; routing its reply to whatever is on screen
  // would put private traffic somewhere it was never meant to go.
  test('the reply goes to the slot it came from, not the active one',
      () async {
    final rec = await rig();
    await rec.bot.setEnabled(const ChannelScope(2), true);
    rec.mc.setActiveChannel(0); // user is looking at Public

    rec.fake.emit(channelMsgFrame(idx: 2, text: 'ping'));
    await Future<void>.delayed(Duration.zero);

    expect(
      rec.mc.messagesFor(0).where((ChatMessage m) => m.outgoing),
      isEmpty,
      reason: 'nothing may be sent on Public',
    );
    expect(
      rec.mc.messagesFor(2).where((ChatMessage m) => m.outgoing),
      hasLength(1),
    );
    rec.bridge.dispose();
    rec.mc.dispose();
  });

  test('an unbound slot stays silent', () async {
    final rec = await rig();
    rec.fake.emit(channelMsgFrame(idx: 2, text: 'ping'));
    await Future<void>.delayed(Duration.zero);
    expect(rec.mc.messagesFor(2).where((ChatMessage m) => m.outgoing),
        isEmpty);
    rec.bridge.dispose();
    rec.mc.dispose();
  });

  test('Public can never be bound, so it can never be answered',
      () async {
    final rec = await rig();
    expect(await rec.bot.setEnabled(const ChannelScope(0), true),
        BotRefusal.publicSlot);

    rec.fake.emit(channelMsgFrame(idx: 0, text: 'ping'));
    await Future<void>.delayed(Duration.zero);

    expect(rec.mc.messagesFor(0).where((ChatMessage m) => m.outgoing),
        isEmpty);
    rec.bridge.dispose();
    rec.mc.dispose();
  });

  test('an inbound DM on a bound peer gets a reply', () async {
    final rec = await rig();
    await rec.bot.setEnabled(DmScope('010203040506'), true);

    rec.fake.emit(contactMessageFrame(
        prefix: <int>[1, 2, 3, 4, 5, 6], text: 'ping'));
    await Future<void>.delayed(Duration.zero);

    final List<ChatMessage> dms = rec.mc
        .dmHistoryFor('010203040506')
        .where((ChatMessage m) => m.outgoing)
        .toList();
    expect(dms, hasLength(1));
    expect(dms.single.text, startsWith(kBotMarker));
    rec.bridge.dispose();
    rec.mc.dispose();
  });

  // THE regression test for this feature. The firmware does not push
  // text messages in real time: every inbound message arrives through
  // a drain triggered by MSGS_WAITING. The first version of the guard
  // skipped all drained traffic, which skipped everything and made the
  // bot permanently inert — and the old test asserted exactly that,
  // so a green suite proved nothing.
  test('a live MSGS_WAITING drain IS answered — the normal path',
      () async {
    final rec = await rig();
    await rec.bot.setEnabled(const ChannelScope(2), true);

    // Exactly how a real message arrives while connected.
    rec.fake.emit(msgsWaitingFrame());
    await Future<void>.delayed(Duration.zero);
    expect(rec.mc.isDraining, isTrue);
    expect(rec.mc.isBacklogDrain, isFalse,
        reason: 'a live push is not a backlog');

    rec.fake.emit(channelMsgFrame(idx: 2, text: 'ping'));
    await Future<void>.delayed(Duration.zero);

    expect(
      rec.mc.messagesFor(2).where((ChatMessage m) => m.outgoing),
      hasLength(1),
      reason: 'the bot must answer traffic delivered by a live drain',
    );
    rec.bridge.dispose();
    rec.mc.dispose();
  });

  // The legitimate half of the original concern: history replayed on
  // connect is not answered, or reconnecting floods the mesh with
  // stale replies nobody is waiting for.
  test('the connect backlog is NOT answered', () async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    final BotController bot = BotController(
      pskFor: (int _) => privatePsk(),
      now: () => DateTime.utc(2026, 1, 1, 12),
      rateLimit: const BotRateLimit(
          minInterval: Duration.zero, maxPerWindow: 1000),
    );
    final BotBridge bridge = BotBridge(mc, bot);
    await bot.setEnabled(const ChannelScope(2), true);

    await mc.connect();
    fake.emit(selfInfoFrame()); // → ready, which starts the BACKLOG drain
    await Future<void>.delayed(Duration.zero);
    expect(mc.isBacklogDrain, isTrue);

    fake.emit(channelMsgFrame(idx: 2, text: 'ping'));
    await Future<void>.delayed(Duration.zero);

    expect(mc.messagesFor(2).where((ChatMessage m) => m.outgoing), isEmpty,
        reason: 'replayed history must not be answered');
    bridge.dispose();
    mc.dispose();
  });

  test('the bridge learns our own key so the self-guard can fire',
      () async {
    final rec = await rig();
    rec.fake.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);
    expect(rec.bot.ownPubKeyHex, isNotNull);
    expect(rec.bot.ownPubKeyHex, rec.mc.ownPubKeyHex);
    rec.bridge.dispose();
    rec.mc.dispose();
  });
}
