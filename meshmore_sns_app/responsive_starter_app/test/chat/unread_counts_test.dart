// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/chat/channel_read_store.dart';
import 'package:meshmore_sns_app/chat/unread_counts.dart';
import 'package:meshmore_sns_app/meshcore/block_filter.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatMessage inbound(int channel, String text, {int secondsAgo = 0}) =>
    ChatMessage(
      channelIdx: channel,
      text: text,
      outgoing: false,
      at: DateTime.now().subtract(Duration(seconds: secondsAgo)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('the read mark never moves backwards', () async {
    final ChannelReadStore s = ChannelReadStore();
    final DateTime now = DateTime.now();
    await s.markRead(1, at: now);
    await s.markRead(1, at: now.subtract(const Duration(minutes: 5)));
    expect(s.lastReadAtMs(1), now.millisecondsSinceEpoch,
        reason: 'a slower path must not un-read a later message');
    expect(s.lastReadAtMs(2), 0, reason: 'an unopened channel was never read');
  });

  test('the mark survives a reload, and a corrupt blob is not fatal', () async {
    final ChannelReadStore s = ChannelReadStore();
    await s.markRead(3, at: DateTime.fromMillisecondsSinceEpoch(1700000000000));
    final ChannelReadStore reloaded = ChannelReadStore();
    await reloaded.load();
    expect(reloaded.lastReadAtMs(3), 1700000000000);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'mm.channelRead.v1': 'not json',
    });
    final ChannelReadStore broken = ChannelReadStore();
    await broken.load();
    expect(broken.lastReadAtMs(3), 0,
        reason: 'erring toward unread is the safe direction');
  });

  test('a count skips rows the block filter hides', () {
    final BlockStore blocks = BlockStore(seed: <String, BlockedKey>{
      'a' * 64: BlockedKey(pubKeyHex: 'a' * 64, sinceMs: 1, name: 'Mallory'),
    });
    final BlockFilter filter = BlockFilter(blocks);
    final List<ChatMessage> ch1 = <ChatMessage>[
      inbound(1, 'Trudy: hi'),
      inbound(1, 'Mallory: hi'),
    ];
    final ChannelReadStore reads = ChannelReadStore(seed: <int, int>{1: 0});
    List<ChatMessage> history(int idx) =>
        idx == 1 ? ch1 : const <ChatMessage>[];

    final Map<int, int> per = UnreadCounts.perChannel(
      channels: const <int>[1, 2],
      history: history,
      reads: reads,
      filter: filter,
    );
    expect(per[1], 1, reason: 'the blocked author cannot inflate a badge');
    expect(per.containsKey(2), isFalse, reason: 'no messages, no badge');
    expect(
      UnreadCounts.total(
        channels: const <int>[1, 2],
        history: history,
        reads: reads,
        filter: filter,
      ),
      1,
    );
  });

  test('with no read store there is no unread state at all', () {
    expect(
      UnreadCounts.perChannel(
        channels: const <int>[0],
        history: (int idx) => <ChatMessage>[inbound(0, 'Trudy: hi')],
        reads: null,
        filter: BlockFilter(BlockStore()),
      ),
      isEmpty,
    );
  });

  test('a row older than the mark is read, a newer one is not', () {
    final ChannelReadStore reads = ChannelReadStore(
      seed: <int, int>{
        1: DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      },
    );
    final List<ChatMessage> rows = <ChatMessage>[
      inbound(1, 'Trudy: old', secondsAgo: 120),
      inbound(1, 'Trudy: new', secondsAgo: 10),
    ];
    expect(
      UnreadCounts.perChannel(
        channels: const <int>[1],
        history: (int idx) => rows,
        reads: reads,
        filter: BlockFilter(BlockStore()),
      )[1],
      1,
    );
    expect(
      UnreadCounts.perChannel(
        channels: const <int>[1],
        history: (int idx) => <ChatMessage>[
          ChatMessage(channelIdx: 1, text: 'mine', outgoing: true),
        ],
        reads: reads,
        filter: BlockFilter(BlockStore()),
      ),
      isEmpty,
      reason: 'outgoing rows are never unread: the reader wrote them',
    );
  });
}
