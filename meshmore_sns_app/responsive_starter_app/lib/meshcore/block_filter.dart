// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'block_store.dart';
import 'chat_message.dart';
import 'chat_store.dart';

/// The one place that answers "does a blocked key hide this?".
///
/// Every surface reads it, so the answer cannot drift between the timeline,
/// the roster, the map, search and notifications. It never changes the wire:
/// blocking a key emits nothing (`meshmore-sns-block-spec.md` §10.10).
///
/// What a channel text can and cannot be matched on is a wire fact, not a
/// choice: a channel message carries the sender's *display name* in its text
/// and no public key, so a channel row is filtered by the name pin (exactly
/// one blocked entry carries that name) and never by a key this frame did not
/// contain. Direct messages, nodes and places do carry keys.
class BlockFilter {
  const BlockFilter(this.store);

  final BlockStore store;

  /// True when the author of [message] is blocked, so the row, its unread
  /// count, its notification, its speech and its search hit all go away.
  bool hidesMessage(ChatMessage message) {
    final String? key = message.peerPubKeyHex;
    if (key != null && key.isNotEmpty) return store.isBlocked(key);
    // Channel text: `sender: body`, where the sender is a display name.
    final String text = message.text;
    final int at = text.indexOf(': ');
    if (at <= 0) return false;
    final String sender = text.substring(0, at);
    if (sender.contains('[')) return false;
    return store.isBlockedName(sender);
  }

  /// Node roster, horizon, topology and telemetry polling: keyed, so exact.
  bool hidesNode(String? pubKeyHex) => store.isBlocked(pubKeyHex);

  /// Places are keyed when they arrived by direct message, unkeyed when they
  /// arrived as channel text. An unkeyed place has no author to match, so it
  /// stays visible and labelled rather than guessed at.
  bool hidesPlace({String? createdByKeyHex, String? createdByName}) {
    if (createdByKeyHex != null && createdByKeyHex.isNotEmpty) {
      return store.isBlocked(createdByKeyHex);
    }
    return store.isBlockedName(createdByName);
  }

  /// The rows of [messages] the user is allowed to see.
  List<ChatMessage> visible(List<ChatMessage> messages) =>
      messages.where((ChatMessage m) => !hidesMessage(m)).toList(growable: false);
}

/// One search over stored history.
///
/// There is no radio index and no plaintext index outside the sealed store, so
/// search reads the list the app already holds, matches a case-insensitive
/// substring, and reports how many hits the block filter removed instead of
/// letting them vanish silently.
class MessageSearchResult {
  const MessageSearchResult({
    required this.hits,
    required this.hidden,
    required this.boundedByRetention,
  });

  final List<ChatMessage> hits;

  /// Matches from blocked keys. Shown as a count, never as rows.
  final int hidden;

  /// True when history is at [ChatStore.cap], so the oldest rows are already
  /// gone and the answer is bounded by retention rather than by the query.
  final bool boundedByRetention;

  bool get isEmpty => hits.isEmpty && hidden == 0;

  /// The number the UI says out loud: "3 hidden".
  int get hiddenCount => hidden;
}

abstract final class MessageSearch {
  static MessageSearchResult run(
    List<ChatMessage> history,
    String query, {
    required BlockFilter filter,
    int cap = ChatStore.cap,
  }) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return MessageSearchResult(
        hits: const <ChatMessage>[],
        hidden: 0,
        boundedByRetention: history.length >= cap,
      );
    }
    final List<ChatMessage> hits = <ChatMessage>[];
    int hidden = 0;
    for (final ChatMessage m in history) {
      if (!m.text.toLowerCase().contains(q)) continue;
      if (filter.hidesMessage(m)) {
        hidden++;
      } else {
        hits.add(m);
      }
    }
    return MessageSearchResult(
      hits: hits,
      hidden: hidden,
      boundedByRetention: history.length >= cap,
    );
  }
}

/// Per-channel unread counts. Only DM unread existed; a channel's badge was
/// the whole channel's traffic, which is why a blocked key used to inflate it.
abstract final class ChannelUnread {
  /// Messages in [messages] for [channelIdx] that arrived after
  /// [lastReadMs] and that the block filter does not hide.
  static int count(
    List<ChatMessage> messages, {
    required int channelIdx,
    required int lastReadMs,
    required BlockFilter filter,
  }) {
    int n = 0;
    for (final ChatMessage m in messages) {
      if (m.outgoing || m.channelIdx != channelIdx) continue;
      if (m.at.millisecondsSinceEpoch <= lastReadMs) continue;
      if (filter.hidesMessage(m)) continue;
      n++;
    }
    return n;
  }
}

/// What history retention is doing to the user's view, said out loud.
///
/// The 250-message cap truncates silently today. A store that drops rows
/// without saying so makes search and "where did it go" questions
/// unanswerable.
abstract final class RetentionNotice {
  static const int cap = ChatStore.cap;

  /// True when the store is holding its maximum, so the oldest rows are gone.
  static bool atCap(int storedCount) => storedCount >= cap;
}
