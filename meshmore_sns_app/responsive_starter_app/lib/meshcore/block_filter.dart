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

/// What a search found: the visible hits, the count the block filter removed,
/// and whether retention or the display cap bounded the answer.
class MessageSearchResult {
  const MessageSearchResult({
    required this.hits,
    required this.hidden,
    required this.boundedByRetention,
    this.truncated = false,
  });

  /// Matches after the block filter, ranked: a word that starts a row comes
  /// before a word found inside one (APP-E6 rule 4), newest first within a
  /// rank.
  final List<ChatMessage> hits;

  /// Matches from blocked keys. Shown as a count, never as rows.
  final int hidden;

  /// True when history is at [ChatStore.cap], so the oldest rows are already
  /// gone and the answer is bounded by retention rather than by the query.
  final bool boundedByRetention;

  /// True when [hits] was cut to the display cap, so the UI says so rather
  /// than letting the list look complete (APP-E6 rule 3).
  final bool truncated;

  bool get isEmpty => hits.isEmpty && hidden == 0;

  /// The number the UI says out loud: "3 hidden".
  int get hiddenCount => hidden;
}

/// One search over stored history.
///
/// There is no radio index and no plaintext index outside the sealed store, so
/// search reads the list the app already holds, matches a case- and
/// accent-insensitive substring (APP-E6 rule 4), and reports how many hits the
/// block filter removed instead of letting them vanish silently.
abstract final class MessageSearch {
  /// How many hits the UI draws. Past this the answer says it was cut
  /// (APP-E6 rule 3) rather than showing a list that looks complete.
  static const int displayCap = 100;

  static MessageSearchResult run(
    List<ChatMessage> history,
    String query, {
    required BlockFilter filter,
    int cap = ChatStore.cap,
    int displayCap = displayCap,
  }) {
    final String q = _fold(query.trim());
    if (q.isEmpty) {
      return MessageSearchResult(
        hits: const <ChatMessage>[],
        hidden: 0,
        boundedByRetention: history.length >= cap,
      );
    }
    // Two ranks: the query begins a word, or it sits inside one. "ford" finds
    // "Waterford", one rank lower, and finds "… at the ford" at the top.
    final List<ChatMessage> starts = <ChatMessage>[];
    final List<ChatMessage> contains = <ChatMessage>[];
    int hidden = 0;
    for (final ChatMessage m in history) {
      final String text = _fold(m.text);
      final int at = text.indexOf(q);
      if (at < 0) continue;
      if (filter.hidesMessage(m)) {
        hidden++;
        continue;
      }
      final bool wordStart =
          at == 0 || !_isWordChar(text.codeUnitAt(at - 1));
      (wordStart ? starts : contains).add(m);
    }
    // Newest first inside each rank: a search is usually a question about
    // what was just said.
    int newestFirst(ChatMessage a, ChatMessage b) => b.at.compareTo(a.at);
    starts.sort(newestFirst);
    contains.sort(newestFirst);
    final List<ChatMessage> ranked = <ChatMessage>[...starts, ...contains];
    return MessageSearchResult(
      hits: ranked.length > displayCap
          ? ranked.sublist(0, displayCap)
          : ranked,
      hidden: hidden,
      boundedByRetention: history.length >= cap,
      truncated: ranked.length > displayCap,
    );
  }

  /// Lower-cases and strips the diacritics of the Latin-1 and Latin Extended-A
  /// ranges, which is what APP-E6 rule 4 asks for at minimum. Full Unicode
  /// folding needs a table the app does not ship, so this covers Latin text and
  /// leaves every other script matched exactly.
  static String _fold(String s) {
    final String lower = s.toLowerCase();
    final StringBuffer out = StringBuffer();
    for (final int rune in lower.runes) {
      out.write(_foldRune(rune));
    }
    return out.toString();
  }

  static const Map<int, int> _folded = <int, int>{
    0xE0: 0x61, 0xE1: 0x61, 0xE2: 0x61, 0xE3: 0x61, 0xE4: 0x61, 0xE5: 0x61, // à-å
    0xE7: 0x63, // ç
    0xE8: 0x65, 0xE9: 0x65, 0xEA: 0x65, 0xEB: 0x65, // è-ë
    0xEC: 0x69, 0xED: 0x69, 0xEE: 0x69, 0xEF: 0x69, // ì-ï
    0xF1: 0x6E, // ñ
    0xF2: 0x6F, 0xF3: 0x6F, 0xF4: 0x6F, 0xF5: 0x6F, 0xF6: 0x6F, // ò-ö
    0xF9: 0x75, 0xFA: 0x75, 0xFB: 0x75, 0xFC: 0x75, // ù-ü
    0xFD: 0x79, 0xFF: 0x79, // ý ÿ
    0x101: 0x61, 0x103: 0x61, // ā ă
    0x105: 0x63, // ć
    0x107: 0x63, 0x10D: 0x63, // č
    0x10F: 0x64, 0x111: 0x65, // ď ē
    0x113: 0x65, // ĕ
    0x117: 0x65, // ė
    0x119: 0x65, 0x11B: 0x65, // ę ě
    0x11F: 0x67, 0x121: 0x67, // ğ ġ
    0x123: 0x67, // ģ
    0x125: 0x68, 0x127: 0x68, // ĥ ħ
    0x12B: 0x69, 0x12D: 0x69, 0x12F: 0x69, // ī ĭ į
    0x131: 0x69, // ı
    0x135: 0x6A, // ĵ
    0x137: 0x6B, 0x13C: 0x6B, // ķ ļ
    0x13E: 0x6C, 0x140: 0x6C, // ľ ł
    0x144: 0x6E, 0x146: 0x6E, 0x148: 0x6E, // ń ņ ň
    0x149: 0x6E, // ŉ
    0x14B: 0x6F, 0x14D: 0x6F, 0x14F: 0x6F, // ŋ ō ŏ
    0x151: 0x6F, // ő
    0x155: 0x72, 0x157: 0x72, 0x159: 0x72, // ŕ ŗ ř
    0x15B: 0x73, 0x15D: 0x73, 0x15F: 0x73, 0x161: 0x73, // ś ŝ ş š
    0x163: 0x74, 0x165: 0x74, 0x167: 0x74, // ţ ť ŧ
    0x16B: 0x75, 0x16D: 0x75, 0x16F: 0x75, 0x171: 0x75, // ū ŭ ů ű
    0x173: 0x77, 0x175: 0x79, 0x177: 0x79, // ų ŵ ŷ
    0x17A: 0x7A, 0x17C: 0x7A, 0x17E: 0x7A, // ź ż ž
  };

  static bool _isWordChar(int c) =>
      (c >= 0x61 && c <= 0x7A) || // a-z (the string is folded)
      (c >= 0x30 && c <= 0x39) || // 0-9
      c == 0x5F; // _

  /// Folds one rune, or returns the rune itself when it is not Latin.
  ///
  /// `ß` expands to two letters rather than one, which is why this returns a
  /// string: folding it to a single `s` would stop "Straße" matching
  /// "Strasse", the exact case the rule exists for.
  static String _foldRune(int rune) {
    if (rune == 0xDF) return 'ss';
    final int? folded = _folded[rune];
    return String.fromCharCode(folded ?? rune);
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
