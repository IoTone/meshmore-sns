// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bot_guards.dart';
import 'bot_scope.dart';
import 'responder.dart';
import 'rule.dart';
import 'rulepack_parser.dart';

/// What the user has configured for one scope (R59).
class BotBinding {
  BotBinding({
    this.enabled = false,
    this.mode = BotMode.deterministic,
    this.seed = 1,
    this.rulepackSource,
    this.counter = 0,
    BotCounters? counters,
  }) : counters = counters ?? BotCounters();

  /// Off by default, always. A bot that switched itself on would be a
  /// bot talking on somebody else's mesh without being asked to.
  final bool enabled;
  final BotMode mode;
  final int seed;

  /// Null means "use [kDefaultRulepack]" — so the shipped pack keeps
  /// improving for anyone who never edited theirs.
  final String? rulepackSource;

  /// The responder's monotonic counter, persisted so a soak that spans
  /// an app restart keeps numbering rather than starting over and
  /// making the transcript look like a duplicate storm.
  final int counter;

  final BotCounters counters;

  BotBinding copyWith({
    bool? enabled,
    BotMode? mode,
    int? seed,
    String? rulepackSource,
    bool clearRulepack = false,
    int? counter,
  }) =>
      BotBinding(
        enabled: enabled ?? this.enabled,
        mode: mode ?? this.mode,
        seed: seed ?? this.seed,
        rulepackSource:
            clearRulepack ? null : (rulepackSource ?? this.rulepackSource),
        counter: counter ?? this.counter,
        counters: counters,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'on': enabled,
        'mode': mode.id,
        'seed': seed,
        if (rulepackSource != null) 'rules': rulepackSource,
        'n': counter,
        'c': counters.toJson(),
      };

  static BotBinding fromJson(Map<String, Object?> j) => BotBinding(
        enabled: j['on'] == true,
        mode: BotMode.fromId(j['mode'] as String?),
        seed: (j['seed'] as num?)?.toInt() ?? 1,
        rulepackSource: j['rules'] as String?,
        counter: (j['n'] as num?)?.toInt() ?? 0,
        counters: j['c'] is Map
            ? BotCounters.fromJson((j['c']! as Map).cast<String, Object?>())
            : BotCounters(),
      );
}

/// Owns bot bindings, enforces the guards, and produces replies.
///
/// Knows nothing about *sending* — it returns the text to send and the
/// caller does the I/O. That keeps the whole decision path synchronous
/// and testable, and means a soak trace can be reproduced with no
/// radio present.
class BotController extends ChangeNotifier {
  BotController({
    List<int>? Function(int idx)? pskFor,
    DateTime Function()? now,
    BotRateLimit rateLimit = const BotRateLimit(),
  })  : _pskFor = pskFor ?? ((int _) => null),
        _now = now ?? DateTime.now,
        _rateLimit = rateLimit;

  static const String kKey = 'mm.bot.v1';

  final List<int>? Function(int idx) _pskFor;
  final DateTime Function() _now;
  final BotRateLimit _rateLimit;
  final RulepackParser _parser = RulepackParser();

  final Map<String, BotBinding> _bindings = <String, BotBinding>{};
  final Map<String, BotResponder> _responders = <String, BotResponder>{};
  final Map<String, BotThrottle> _throttles = <String, BotThrottle>{};

  /// Our own pubkey, so the bot never answers itself. Set by the
  /// wiring layer once `SelfInfo` lands.
  String? ownPubKeyHex;

  Map<String, BotBinding> get bindings =>
      Map<String, BotBinding>.unmodifiable(_bindings);

  /// Scopes with the bot switched on. Drives the "a bot is running"
  /// indicator — a bot the operator has forgotten about is the main
  /// way this feature misbehaves.
  Iterable<BotScope> get activeScopes => _bindings.entries
      .where((MapEntry<String, BotBinding> e) => e.value.enabled)
      .map((MapEntry<String, BotBinding> e) => BotScope.fromKey(e.key))
      .whereType<BotScope>();

  Future<void> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(kKey);
    _bindings.clear();
    _responders.clear();
    if (raw != null) {
      try {
        final Object? decoded = json.decode(raw);
        if (decoded is Map) {
          decoded.forEach((Object? k, Object? v) {
            if (k is! String || v is! Map) return;
            _bindings[k] = BotBinding.fromJson(v.cast<String, Object?>());
          });
        }
      } catch (_) {
        // Corrupt payload — start clean rather than throw on launch.
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    if (_bindings.isEmpty) {
      await p.remove(kKey);
      return;
    }
    await p.setString(
      kKey,
      json.encode(<String, Object?>{
        for (final MapEntry<String, BotBinding> e in _bindings.entries)
          e.key: e.value.toJson(),
      }),
    );
  }

  BotBinding bindingFor(BotScope s) =>
      _bindings[resolveKey(s)] ?? BotBinding();

  /// The stored key this scope should read and write.
  ///
  /// Channels are exact. **DMs are prefix-tolerant**: a DM carries the
  /// peer's full 64-hex pubkey when the fabric can resolve it and only
  /// a 12-hex prefix when it cannot, while the user binds the bot from
  /// a sheet that usually knows the full key. An exact lookup would
  /// silently fail to answer on exactly the frames where the fabric is
  /// least sure — see the same resolution in `PeerProfiles`.
  String resolveKey(BotScope s) {
    if (s is! DmScope) return s.key;
    if (_bindings.containsKey(s.key)) return s.key;
    final String hex = s.pubKeyHex;
    for (final String stored in _bindings.keys) {
      if (!stored.startsWith('dm:')) continue;
      final String other = stored.substring(3);
      if (other.startsWith(hex) || hex.startsWith(other)) return stored;
    }
    return s.key;
  }

  /// Why [s] may not host a bot, or null when it may.
  BotRefusal? refusalFor(BotScope s) => botRefusalFor(s, _pskFor);

  bool isEnabled(BotScope s) => bindingFor(s).enabled;

  /// Turn the bot on or off for [s].
  ///
  /// Returns the refusal when enabling is not permitted — the caller
  /// gets a reason to show, and the binding is left untouched. This is
  /// the structural gate: there is no path to an enabled binding on a
  /// public scope, whatever the UI does.
  Future<BotRefusal?> setEnabled(BotScope s, bool on) async {
    if (on) {
      final BotRefusal? r = refusalFor(s);
      if (r != null) return r;
    }
    await _mutate(s, (BotBinding b) => b.copyWith(enabled: on));
    return null;
  }

  Future<void> setMode(BotScope s, BotMode m) =>
      _mutate(s, (BotBinding b) => b.copyWith(mode: m), resetResponder: true);

  Future<void> setSeed(BotScope s, int seed) =>
      _mutate(s, (BotBinding b) => b.copyWith(seed: seed),
          resetResponder: true);

  /// Replace the rulepack for [s]; null restores the shipped default.
  Future<void> setRulepack(BotScope s, String? source) => _mutate(
        s,
        (BotBinding b) => b.copyWith(
            rulepackSource: source, clearRulepack: source == null),
        resetResponder: true,
      );

  String rulepackSourceFor(BotScope s) =>
      bindingFor(s).rulepackSource ?? kDefaultRulepack;

  /// Parse errors in this scope's pack, for Diagnostics.
  List<String> rulepackErrorsFor(BotScope s) =>
      errorsIn(rulepackSourceFor(s));

  /// Parse errors in an arbitrary source, for the editor to report on
  /// a draft that has not been saved yet.
  static List<String> errorsIn(String source) =>
      RulepackParser().parse(source).errors;

  BotCounters countersFor(BotScope s) => bindingFor(s).counters;

  int remainingBudgetFor(BotScope s) =>
      _throttleFor(s).remainingAt(_now());

  Future<void> resetCounters(BotScope s) async {
    bindingFor(s).counters.reset();
    _throttles.remove(resolveKey(s));
    notifyListeners();
    await _save();
  }

  /// A soak report: every scope with a binding, its configuration and
  /// its counters, as pretty JSON.
  ///
  /// The point of R59 is that a soak run produces *evidence* rather
  /// than a claim, and evidence has to leave the phone. Includes the
  /// seed and mode alongside the counts, because a result nobody can
  /// replay is not a result — with these three fields plus the
  /// rulepack, a run is reproducible.
  String exportReport({DateTime? at}) {
    final Map<String, Object?> out = <String, Object?>{
      'generatedAt': (at ?? _now()).toUtc().toIso8601String(),
      if (ownPubKeyHex != null) 'self': ownPubKeyHex,
      'scopes': <Map<String, Object?>>[
        for (final MapEntry<String, BotBinding> e in _bindings.entries)
          <String, Object?>{
            'scope': e.key,
            'enabled': e.value.enabled,
            'mode': e.value.mode.id,
            'seed': e.value.seed,
            'replyCounter': e.value.counter,
            'customRulepack': e.value.rulepackSource != null,
            'counters': e.value.counters.toJson(),
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(out);
  }

  /// Totals across every scope, for an at-a-glance line.
  BotCounters totals() {
    final BotCounters t = BotCounters();
    for (final BotBinding b in _bindings.values) {
      t.received += b.counters.received;
      t.replied += b.counters.replied;
      t.suppressedOwn += b.counters.suppressedOwn;
      t.suppressedLoop += b.counters.suppressedLoop;
      t.suppressedRate += b.counters.suppressedRate;
      t.noMatch += b.counters.noMatch;
      t.refused += b.counters.refused;
    }
    return t;
  }

  /// Decide what, if anything, to send in reply to [text] on [scope].
  ///
  /// Returns the **labelled** outbound text, or null. Every null path
  /// increments a counter, so silence is always explainable.
  String? handleInbound({
    required BotScope scope,
    required String text,
    String? fromPubKeyHex,
  }) {
    final BotBinding b = bindingFor(scope);
    if (!b.enabled) return null;

    final BotCounters c = b.counters;
    c.received++;

    // Re-check on every message, not just at bind time. A slot's key
    // can be changed on the device after the bot was switched on, and
    // the binding must not outlive the privacy it was granted under.
    //
    // Counted, not returned silently. This check used to sit above
    // `received++`, so a scope that stopped qualifying produced total
    // silence and left no trace — indistinguishable from "no traffic
    // arrived", which is the one thing the counters exist to tell
    // apart.
    if (refusalFor(scope) != null) {
      c.countSuppression(BotSuppression.refused);
      notifyListeners();
      unawaited(_save());
      return null;
    }

    BotSuppression? suppress;
    final String? own = ownPubKeyHex;
    if (own != null &&
        fromPubKeyHex != null &&
        _sameNode(own, fromPubKeyHex)) {
      suppress = BotSuppression.ownMessage;
    } else if (looksLikeBot(text)) {
      suppress = BotSuppression.loopBreaker;
    }

    final DateTime now = _now();
    final BotThrottle th = _throttleFor(scope);
    suppress ??= th.checkAt(now);

    if (suppress != null) {
      c.countSuppression(suppress);
      notifyListeners();
      return null;
    }

    final BotResponder r = _responderFor(scope, b);
    final String? reply = r.respondTo(text);
    if (reply == null) {
      c.countSuppression(BotSuppression.noMatch);
      notifyListeners();
      return null;
    }

    th.recordAt(now);
    c.replied++;
    _bindings[resolveKey(scope)] = b.copyWith(counter: r.counter);
    notifyListeners();
    unawaited(_save());
    return labelAsBot(reply);
  }

  /// Prefix-tolerant node comparison — a DM may carry the full 64-hex
  /// pubkey or only a 12-hex prefix, and "is this us?" must be right
  /// in both cases or the bot answers itself.
  static bool _sameNode(String a, String b) {
    final String x = a.toLowerCase();
    final String y = b.toLowerCase();
    return x == y || x.startsWith(y) || y.startsWith(x);
  }

  BotThrottle _throttleFor(BotScope s) => _throttles.putIfAbsent(
      resolveKey(s), () => BotThrottle(limit: _rateLimit));

  BotResponder _responderFor(BotScope s, BotBinding b) =>
      _responders.putIfAbsent(resolveKey(s), () {
        final Rulepack pack = _parser.parse(rulepackSourceFor(s));
        return BotResponder(
          pack: pack,
          mode: b.mode,
          seed: b.seed,
          counter: b.counter,
        );
      });

  Future<void> _mutate(
    BotScope s,
    BotBinding Function(BotBinding) edit, {
    bool resetResponder = false,
  }) async {
    final String k = resolveKey(s);
    _bindings[k] = edit(bindingFor(s));
    // Mode, seed and rules all change how replies are chosen, so the
    // cached responder must go — otherwise a seed change would be
    // accepted by the UI and quietly ignored by the engine.
    if (resetResponder) _responders.remove(k);
    notifyListeners();
    await _save();
  }
}
