// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math';

import 'rule.dart';

/// How a rulepack picks among matching clauses (R59).
enum BotMode {
  /// First matching clause wins, under the rulepack's file order.
  /// Identical input always yields identical output — this is the
  /// property that makes a soak trace diffable.
  deterministic,

  /// Uniform choice among *all* matching clauses, from a seeded PRNG.
  /// "Random" here still means reproducible: replaying a soak with the
  /// same seed and the same inbound sequence produces the same
  /// outbound sequence, or a failure is undebuggable.
  random;

  static BotMode fromId(String? id) =>
      id == 'random' ? BotMode.random : BotMode.deterministic;

  String get id => name;
}

/// The default rulepack: **echo with a monotonic counter**.
///
/// The single most useful soak behaviour, because one read of the
/// transcript exposes drops (missing numbers), duplicates (a repeated
/// number) and reordering (numbers out of sequence) at once — none of
/// which a plain "ack" would show.
const String kDefaultRulepack = '''
% Default soak pack — echo with a monotonic counter.
% One read of the transcript shows drops, duplicates and reordering.
reply(ping, "pong {N}").
reply(status, "ok {N}").
reply(Anything..., "#{N} {Anything}").
''';

/// Turns an inbound message into a reply, or nothing.
///
/// Deliberately **pure with respect to the mesh**: it knows nothing
/// about channels, peers, rate limits or sending. Those are policy and
/// live in the binding layer, so this class stays trivially testable
/// and a soak trace can be reproduced without a radio.
class BotResponder {
  BotResponder({
    required this.pack,
    this.mode = BotMode.deterministic,
    int seed = 1,
    int counter = 0,
  })  : _seed = seed,
        _counter = counter,
        _rng = Random(seed);

  final Rulepack pack;
  final BotMode mode;

  final int _seed;
  final Random _rng;
  int _counter;

  /// The PRNG seed. Persisted and shown in the UI — a "random" soak
  /// run that cannot be replayed is not evidence of anything.
  int get seed => _seed;

  /// Replies issued so far. Monotonic across the run; rendered by
  /// `{N}` and never reset by a rule that fails to match.
  int get counter => _counter;

  /// Split a message into tokens. Punctuation is left attached — an
  /// operator writing `reply(ping, ...)` means the word, and silently
  /// stripping a trailing `?` would make `ping?` match `ping`, which
  /// is a surprise in the wrong direction for a determinism tool.
  static List<String> tokenize(String text) => text
      .trim()
      .split(RegExp(r'\s+'))
      .where((String t) => t.isNotEmpty)
      .toList();

  /// The reply for [text], or null when no clause matches.
  ///
  /// Increments [counter] only when a reply is actually produced, so
  /// the numbers in a transcript count *replies*, not attempts.
  String? respondTo(String text) {
    final List<String> tokens = tokenize(text);
    if (tokens.isEmpty) return null;

    final List<({BotRule rule, Map<String, String> bindings})> hits =
        <({BotRule rule, Map<String, String> bindings})>[];
    for (final BotRule r in pack.rules) {
      final Map<String, String>? b = r.match(tokens);
      if (b == null) continue;
      hits.add((rule: r, bindings: b));
      // Deterministic mode never needs to look further, and stopping
      // here also keeps it O(first match) on a long pack.
      if (mode == BotMode.deterministic) break;
    }
    if (hits.isEmpty) return null;

    final ({BotRule rule, Map<String, String> bindings}) chosen =
        mode == BotMode.deterministic
            ? hits.first
            : hits[_rng.nextInt(hits.length)];

    _counter++;
    return chosen.rule.render(chosen.bindings, _counter);
  }
}
