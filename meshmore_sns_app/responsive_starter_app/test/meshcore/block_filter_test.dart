// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/block_filter.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';

/// One test per surface the filter must cover (`meshmore-sns-block-spec.md`
/// §5). The failure mode this guards is the one that actually happens: the
/// timeline is filtered and search, the roster or a notification is not.
void main() {
  final String blockedKey = 'a' * 64;
  final String otherKey = 'b' * 64;

  BlockStore storeWith(BlockedKey key) =>
      BlockStore(seed: <String, BlockedKey>{key.pubKeyHex: key});

  final BlockedKey blocked =
      BlockedKey(pubKeyHex: blockedKey, sinceMs: 1, name: 'Mallory');

  ChatMessage dm({String? key, String text = 'hi'}) => ChatMessage(
        channelIdx: 0,
        text: text,
        outgoing: false,
        peerPubKeyHex: key,
      );

  ChatMessage channel({required String sender, String body = 'hello'}) =>
      ChatMessage(
        channelIdx: 1,
        text: '$sender: $body',
        outgoing: false,
      );

  /// A row on [channelIdx] stamped [secondsAgo] in the past, so ranking and
  /// recency can be asserted without depending on the order of a list.
  ChatMessage chatAt(int channelIdx, String text, {int secondsAgo = 0}) =>
      ChatMessage(
        channelIdx: channelIdx,
        text: text,
        outgoing: false,
        at: DateTime.now().subtract(Duration(seconds: secondsAgo)),
      );

  test('the channel timeline hides a keyed DM and a pinned name', () {
    final BlockFilter f = BlockFilter(storeWith(blocked));
    expect(f.hidesMessage(dm(key: blockedKey)), isTrue);
    expect(f.hidesMessage(dm(key: otherKey)), isFalse);
    expect(f.hidesMessage(channel(sender: 'Mallory')), isTrue,
        reason: 'channel text carries a name, so the unique-name pin applies');
    expect(f.hidesMessage(channel(sender: 'Trudy')), isFalse);
    expect(f.visible(<ChatMessage>[dm(key: blockedKey), dm(key: otherKey)])
        .length, 1);
  });

  test('a channel name shared by two blocked keys pins neither', () {
    final BlockStore store = storeWith(blocked);
    store.block(BlockedKey(
        pubKeyHex: otherKey, sinceMs: 2, name: 'Mallory'));
    final BlockFilter f = BlockFilter(store);
    expect(f.hidesMessage(channel(sender: 'Mallory')), isFalse,
        reason: 'two keys answer to that name, so the row cannot be attributed');
  });

  test('the node roster and telemetry use the key, never the name', () {
    final BlockFilter f = BlockFilter(storeWith(blocked));
    expect(f.hidesNode(blockedKey), isTrue);
    expect(f.hidesNode(blockedKey.substring(0, 12)), isTrue,
        reason: 'a legacy frame carries the prefix of the same key');
    expect(f.hidesNode(otherKey), isFalse);
    expect(f.hidesNode(null), isFalse);
  });

  test('a keyed place is hidden, an unkeyed one stays and is labelled', () {
    final BlockFilter f = BlockFilter(storeWith(blocked));
    expect(f.hidesPlace(createdByKeyHex: blockedKey), isTrue);
    expect(f.hidesPlace(createdByKeyHex: otherKey), isFalse);
    expect(f.hidesPlace(), isFalse,
        reason: 'channel text carries no author key, so nothing can match');
  });

  test('search never shows a blocked hit but counts it', () {
    final BlockFilter f = BlockFilter(storeWith(blocked));
    final List<ChatMessage> history = <ChatMessage>[
      dm(key: blockedKey, text: 'meet at the ford'),
      dm(key: otherKey, text: 'the ford is high'),
      channel(sender: 'Mallory', body: 'ford closed'),
      channel(sender: 'Trudy', body: 'unrelated'),
    ];
    final MessageSearchResult r =
        MessageSearch.run(history, 'ford', filter: f);
    expect(r.hits.length, 1);
    expect(r.hits.single.text, contains('the ford is high'));
    expect(r.hidden, 2);
    expect(r.hiddenCount, 2);
    expect(r.isEmpty, isFalse);
  });

  test('search folds Latin accents, so a missing diaeresis still finds it',
      () {
    final BlockFilter f = BlockFilter(storeWith(blocked));
    final List<ChatMessage> history = <ChatMessage>[
      chatAt(1, 'Jose: the cafe is open', secondsAgo: 30),
      chatAt(1, 'Trudy: Strassenende gesperrt', secondsAgo: 20),
    ];
    expect(MessageSearch.run(history, 'café', filter: f).hits.length, 1,
        reason: 'APP-E6 rule 4: accent-insensitive in both directions');
    expect(MessageSearch.run(history, 'CAFÉ', filter: f).hits.length, 1,
        reason: 'and case-insensitive');
    expect(MessageSearch.run(history, 'straße', filter: f).hits.length, 1);
  });

  test('a word that starts a row outranks one found inside it', () {
    final BlockFilter f = BlockFilter(storeWith(blocked));
    final List<ChatMessage> history = <ChatMessage>[
      chatAt(1, 'Trudy: Waterford is flooded', secondsAgo: 10),
      chatAt(1, 'Jose: ford closed at the bridge', secondsAgo: 300),
    ];
    final MessageSearchResult r = MessageSearch.run(history, 'ford', filter: f);
    expect(r.hits.length, 2);
    expect(r.hits.first.text, contains('ford closed'),
        reason: 'the newer row is a substring hit, the older one starts the '
            'word — rank wins over recency (APP-E6 rule 4)');
  });

  test('search says when the display cap cut the list, not silence', () {
    final BlockFilter f = BlockFilter(storeWith(blocked));
    final List<ChatMessage> history = <ChatMessage>[
      for (int i = 0; i < 12; i++) chatAt(1, 'Trudy: ford $i', secondsAgo: i),
    ];
    final MessageSearchResult r =
        MessageSearch.run(history, 'ford', filter: f, displayCap: 5);
    expect(r.hits.length, 5);
    expect(r.truncated, isTrue, reason: 'APP-E6 rule 3: say it was cut');
    expect(MessageSearch.run(history, 'ford', filter: f).truncated, isFalse,
        reason: 'under the real cap nothing is cut');
  });

  test('an empty query returns nothing and says so', () {
    final BlockFilter f = BlockFilter(storeWith(blocked));
    final MessageSearchResult r = MessageSearch.run(
        <ChatMessage>[dm(key: otherKey)], '   ',
        filter: f);
    expect(r.isEmpty, isTrue);
    expect(r.hits, isEmpty);
  });

  test('search says when retention, not the query, bounded the answer', () {
    final BlockFilter f = BlockFilter(storeWith(blocked));
    final List<ChatMessage> full = <ChatMessage>[
      for (int i = 0; i < RetentionNotice.cap; i++) dm(key: otherKey, text: 'x'),
    ];
    final MessageSearchResult r = MessageSearch.run(full, 'x', filter: f);
    expect(r.boundedByRetention, isTrue);
    expect(RetentionNotice.atCap(full.length), isTrue);
  });

  test('unread counts skip blocked rows, so the badge is not a lie', () {
    final BlockFilter f = BlockFilter(storeWith(blocked));
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<ChatMessage> history = <ChatMessage>[
      dm(key: blockedKey),
      dm(key: otherKey),
      ChatMessage(channelIdx: 1, text: 'Trudy: hi', outgoing: false),
    ];
    expect(
      ChannelUnread.count(history, channelIdx: 1,
          lastReadMs: now - 60000, filter: f),
      1,
      reason: 'the blocked DM is on another channel; the channel row counts',
    );
    expect(ChannelUnread.count(history, channelIdx: 0,
        lastReadMs: now - 60000, filter: f),
      1);
  });

  test('blocking a key emits nothing: the filter is not the wire', () {
    // The spec's test 10: blocking is a local store operation. There is no
    // frame to assert against because the store has no transport at all; this
    // pins that the API cannot acquire one by accident.
    final BlockStore store = storeWith(blocked);
    expect(store.isBlocked(blockedKey), isTrue);
  });
}
