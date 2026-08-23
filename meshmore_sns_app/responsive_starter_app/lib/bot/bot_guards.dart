// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// R59 — the marker that labels machine-written traffic.
///
/// Goes **on the wire**, not just in our own transcript. The spec is
/// explicit that the human on the other end must be able to tell what
/// a machine wrote, and they are not reading our UI. It costs a few
/// bytes of airtime and that is the right trade.
///
/// It doubles as the loop breaker's signature: two bots in one channel
/// each see the other's marker and both decline, so the ping-pong
/// cannot start. That is why it is short, fixed, and ASCII rather than
/// something a rulepack could vary.
const String kBotMarker = '[bot]';

/// Prefix [text] as machine output.
String labelAsBot(String text) => '$kBotMarker $text';

/// True when [text] looks like something a bot wrote — ours or
/// anyone else's running this marker.
bool looksLikeBot(String text) => text.trimLeft().startsWith(kBotMarker);

/// The message without its marker, for display next to a bot tag.
///
/// The marker earns its airtime on the wire, where the other end has
/// no UI to tell them. In our own transcript the tag says it better,
/// and showing both would label the message twice.
String stripBotMarker(String text) {
  final String t = text.trimLeft();
  if (!t.startsWith(kBotMarker)) return text;
  return t.substring(kBotMarker.length).trimLeft();
}

/// Why an inbound message did not get answered.
enum BotSuppression {
  /// We wrote it. Answering our own traffic is the fastest possible
  /// loop.
  ownMessage,

  /// It carries the bot marker. Two bots would otherwise ping-pong
  /// forever, burning shared airtime on somebody else's mesh.
  loopBreaker,

  /// Less than the minimum interval since our last reply here.
  minInterval,

  /// The per-window reply budget for this scope is spent.
  windowBudget,

  /// No rule matched. Not a fault — a quiet bot is a valid rulepack.
  noMatch,

  /// The scope stopped qualifying — its key went public, or we no
  /// longer know it. Counted rather than returned silently: this is
  /// the one refusal that can appear *after* the user switched the bot
  /// on, so it has to be visible or the bot looks broken.
  refused,
}

/// Per-scope evidence for a soak run.
///
/// A soak that reports only "it worked" is a vibe. These counters make
/// the difference between "no replies because nothing arrived" and "no
/// replies because the budget was spent" readable after the fact.
class BotCounters {
  int received = 0;
  int replied = 0;
  int suppressedOwn = 0;
  int suppressedLoop = 0;
  int suppressedRate = 0;
  int noMatch = 0;
  int refused = 0;

  void countSuppression(BotSuppression s) {
    switch (s) {
      case BotSuppression.ownMessage:
        suppressedOwn++;
      case BotSuppression.loopBreaker:
        suppressedLoop++;
      case BotSuppression.minInterval:
      case BotSuppression.windowBudget:
        suppressedRate++;
      case BotSuppression.noMatch:
        noMatch++;
      case BotSuppression.refused:
        refused++;
    }
  }

  Map<String, int> toJson() => <String, int>{
        'received': received,
        'replied': replied,
        'own': suppressedOwn,
        'loop': suppressedLoop,
        'rate': suppressedRate,
        'noMatch': noMatch,
        'refused': refused,
      };

  static BotCounters fromJson(Map<String, Object?> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return BotCounters()
      ..received = n('received')
      ..replied = n('replied')
      ..suppressedOwn = n('own')
      ..suppressedLoop = n('loop')
      ..suppressedRate = n('rate')
      ..noMatch = n('noMatch')
      ..refused = n('refused');
  }

  void reset() {
    received = 0;
    replied = 0;
    suppressedOwn = 0;
    suppressedLoop = 0;
    suppressedRate = 0;
    noMatch = 0;
    refused = 0;
  }
}

/// Airtime policy for one scope.
///
/// LoRa airtime is shared and scarce, and it is not only *our* mesh we
/// can flood. These are mandatory, not polish: the defaults are chosen
/// to be obviously polite rather than maximally useful, on the grounds
/// that someone running a soak will raise them deliberately while
/// someone who forgets the bot is on will not.
class BotRateLimit {
  const BotRateLimit({
    this.minInterval = const Duration(seconds: 10),
    this.maxPerWindow = 20,
    this.window = const Duration(minutes: 10),
  });

  final Duration minInterval;
  final int maxPerWindow;
  final Duration window;
}

/// Tracks reply timing for one scope and answers "may I reply now?".
///
/// Time is injected rather than read from the clock so a soak can be
/// replayed and a test does not have to sleep.
class BotThrottle {
  BotThrottle({BotRateLimit limit = const BotRateLimit()}) : _limit = limit;

  final BotRateLimit _limit;
  final List<DateTime> _replies = <DateTime>[];

  BotRateLimit get limit => _limit;

  /// Replies still allowed in the current window at [now]. Exposed so
  /// the UI can show the remaining budget rather than silently
  /// enforcing it — a bot that has gone quiet should be able to say
  /// why without the operator reading logs.
  int remainingAt(DateTime now) {
    _prune(now);
    final int left = _limit.maxPerWindow - _replies.length;
    return left < 0 ? 0 : left;
  }

  /// Null when a reply is permitted at [now].
  BotSuppression? checkAt(DateTime now) {
    _prune(now);
    if (_replies.isNotEmpty) {
      final Duration since = now.difference(_replies.last);
      if (since < _limit.minInterval) return BotSuppression.minInterval;
    }
    if (_replies.length >= _limit.maxPerWindow) {
      return BotSuppression.windowBudget;
    }
    return null;
  }

  /// Record that a reply went out at [now].
  void recordAt(DateTime now) {
    _replies.add(now);
    _prune(now);
  }

  void _prune(DateTime now) {
    final DateTime cutoff = now.subtract(_limit.window);
    _replies.removeWhere((DateTime t) => t.isBefore(cutoff));
  }

  void reset() => _replies.clear();
}
