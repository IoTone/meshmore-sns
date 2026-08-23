// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart' show kPublicChannelPsk;
import 'package:meshmore_sns_app/bot/bot_controller.dart';
import 'package:meshmore_sns_app/bot/bot_guards.dart';
import 'package:meshmore_sns_app/bot/bot_scope.dart';
import 'package:meshmore_sns_app/bot/responder.dart';
import 'package:shared_preferences/shared_preferences.dart';

const BotScope priv = ChannelScope(2);
final BotScope dm = DmScope('ab' * 32);

List<int> privatePsk() =>
    List<int>.generate(kPublicChannelPsk.length, (int i) => (i * 7 + 3) & 0xff);

/// A controller on a private slot, with a clock we drive by hand.
BotController make({
  DateTime? at,
  List<int>? Function(int)? pskFor,
  BotRateLimit rateLimit = const BotRateLimit(
      minInterval: Duration.zero, maxPerWindow: 1000),
}) {
  DateTime clock = at ?? DateTime.utc(2026, 1, 1, 12);
  return BotController(
    pskFor: pskFor ?? (int _) => privatePsk(),
    now: () => clock,
    rateLimit: rateLimit,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('R59 binding is refused for Public, structurally', () {
    test('enabling on slot 0 returns a refusal and does not bind', () async {
      final BotController c = make();
      expect(await c.setEnabled(const ChannelScope(0), true),
          BotRefusal.publicSlot);
      expect(c.isEnabled(const ChannelScope(0)), isFalse);
    });

    test('enabling on a slot still holding the public PSK is refused',
        () async {
      final BotController c = make(pskFor: (int _) => kPublicChannelPsk);
      expect(await c.setEnabled(priv, true), BotRefusal.publicPsk);
      expect(c.isEnabled(priv), isFalse);
    });

    test('enabling on a private slot works', () async {
      final BotController c = make();
      expect(await c.setEnabled(priv, true), isNull);
      expect(c.isEnabled(priv), isTrue);
    });

    // The binding must not outlive the privacy it was granted under.
    test('a slot that BECOMES public stops answering', () async {
      List<int> psk = privatePsk();
      final BotController c = BotController(
        pskFor: (int _) => psk,
        now: () => DateTime.utc(2026),
        rateLimit: const BotRateLimit(
            minInterval: Duration.zero, maxPerWindow: 1000),
      );
      await c.setEnabled(priv, true);
      expect(c.handleInbound(scope: priv, text: 'ping'), isNotNull);

      // Operator resets the slot to the stock key on the device.
      psk = List<int>.from(kPublicChannelPsk);
      expect(c.handleInbound(scope: priv, text: 'ping'), isNull,
          reason: 'the bot must stop the moment the slot goes public');

      // And says so. This check used to sit above `received++`, so a
      // scope that stopped qualifying went silent leaving no trace —
      // indistinguishable from "no traffic arrived", which is the one
      // thing the counters exist to tell apart.
      expect(c.countersFor(priv).received, 2);
      expect(c.countersFor(priv).refused, 1);
    });
  });

  group('R59 replying', () {
    test('off by default — an unbound scope never answers', () {
      final BotController c = make();
      expect(c.handleInbound(scope: priv, text: 'ping'), isNull);
    });

    test('an enabled scope answers, labelled as machine output',
        () async {
      final BotController c = make();
      await c.setEnabled(priv, true);
      expect(c.handleInbound(scope: priv, text: 'ping'), '[bot] pong 1');
    });

    test('the counter advances across messages and persists', () async {
      final BotController c = make();
      await c.setEnabled(priv, true);
      c.handleInbound(scope: priv, text: 'ping');
      c.handleInbound(scope: priv, text: 'ping');

      // A soak spanning a restart must keep numbering, or the
      // transcript looks like a duplicate storm.
      final BotController c2 = make();
      await c2.load();
      expect(c2.handleInbound(scope: priv, text: 'ping'), '[bot] pong 3');
    });

    test('DMs are eligible with no PSK knowledge at all', () async {
      final BotController c = make(pskFor: (int _) => null);
      expect(await c.setEnabled(dm, true), isNull);
      expect(c.handleInbound(scope: dm, text: 'ping'), '[bot] pong 1');
    });
  });

  group('R59 loop and self guards', () {
    test('the bot never answers its own traffic', () async {
      final BotController c = make();
      await c.setEnabled(dm, true);
      c.ownPubKeyHex = 'ab' * 32;

      expect(
        c.handleInbound(
            scope: dm, text: 'ping', fromPubKeyHex: 'ab' * 32),
        isNull,
      );
      expect(c.countersFor(dm).suppressedOwn, 1);
    });

    // A DM may carry the full 64-hex key or only a 12-hex prefix.
    test('own-message detection is prefix-tolerant', () async {
      final BotController c = make();
      await c.setEnabled(dm, true);
      c.ownPubKeyHex = 'ab' * 32;
      expect(
        c.handleInbound(scope: dm, text: 'ping', fromPubKeyHex: 'abababababab'),
        isNull,
        reason: 'a prefix of our own key is still us',
      );
    });

    // Two bots in one channel would otherwise ping-pong forever.
    test('labelled traffic is never answered', () async {
      final BotController c = make();
      await c.setEnabled(priv, true);
      expect(c.handleInbound(scope: priv, text: '[bot] pong 4'), isNull);
      expect(c.countersFor(priv).suppressedLoop, 1);
    });

    test('our own reply would not survive a round trip back to us',
        () async {
      final BotController c = make();
      await c.setEnabled(priv, true);
      final String? out = c.handleInbound(scope: priv, text: 'ping');
      expect(out, isNotNull);
      expect(c.handleInbound(scope: priv, text: out!), isNull);
    });
  });

  group('R59 airtime guards in situ', () {
    test('the minimum interval suppresses a burst', () async {
      final BotController c = make(
        rateLimit: const BotRateLimit(
            minInterval: Duration(minutes: 5), maxPerWindow: 100),
      );
      await c.setEnabled(priv, true);
      expect(c.handleInbound(scope: priv, text: 'ping'), isNotNull);
      expect(c.handleInbound(scope: priv, text: 'ping'), isNull);
      expect(c.countersFor(priv).suppressedRate, 1);
    });

    test('the window budget runs out and is visible before it does',
        () async {
      final BotController c = make(
        rateLimit: const BotRateLimit(
            minInterval: Duration.zero, maxPerWindow: 2),
      );
      await c.setEnabled(priv, true);
      expect(c.remainingBudgetFor(priv), 2);
      c.handleInbound(scope: priv, text: 'ping');
      expect(c.remainingBudgetFor(priv), 1);
      c.handleInbound(scope: priv, text: 'ping');
      expect(c.remainingBudgetFor(priv), 0);
      expect(c.handleInbound(scope: priv, text: 'ping'), isNull);
    });

    test('budgets are per scope, not global', () async {
      final BotController c = make(
        rateLimit: const BotRateLimit(
            minInterval: Duration.zero, maxPerWindow: 1),
      );
      await c.setEnabled(priv, true);
      await c.setEnabled(dm, true);
      expect(c.handleInbound(scope: priv, text: 'ping'), isNotNull);
      expect(c.handleInbound(scope: priv, text: 'ping'), isNull);
      expect(c.handleInbound(scope: dm, text: 'ping'), isNotNull,
          reason: 'a busy channel must not silence a DM');
    });
  });

  group('R59 DM scopes resolve prefix-tolerantly', () {
    // A DM carries the full 64-hex pubkey when the fabric can resolve
    // it and only a 12-hex prefix when it cannot, while the user binds
    // from a sheet that usually knows the full key. Exact lookup would
    // fail on exactly the frames where the fabric is least sure.
    test('a bot bound on the full key answers a prefix-only DM',
        () async {
      final BotController c = make();
      await c.setEnabled(DmScope('ab' * 32), true);
      expect(
        c.handleInbound(scope: DmScope('abababababab'), text: 'ping'),
        '[bot] pong 1',
      );
    });

    test('a bot bound on a prefix answers a full-key DM', () async {
      final BotController c = make();
      await c.setEnabled(DmScope('abababababab'), true);
      expect(
        c.handleInbound(scope: DmScope('ab' * 32), text: 'ping'),
        '[bot] pong 1',
      );
    });

    test('one peer keeps one counter and one budget, not two',
        () async {
      final BotController c = make(
        rateLimit: const BotRateLimit(
            minInterval: Duration.zero, maxPerWindow: 1),
      );
      await c.setEnabled(DmScope('ab' * 32), true);
      expect(c.handleInbound(scope: DmScope('ab' * 32), text: 'ping'),
          isNotNull);
      // Same peer, short form: must share the spent budget.
      expect(c.handleInbound(scope: DmScope('abababababab'), text: 'ping'),
          isNull,
          reason: 'a prefix must not get a fresh budget');
      expect(c.bindings.keys.length, 1, reason: 'one peer, one row');
    });

    test('a different peer is genuinely separate', () async {
      final BotController c = make();
      await c.setEnabled(DmScope('ab' * 32), true);
      expect(c.handleInbound(scope: DmScope('cd' * 32), text: 'ping'),
          isNull);
    });
  });

  group('R59 counters explain every silence', () {
    test('a no-match is counted distinctly from a rate limit', () async {
      final BotController c = make();
      await c.setEnabled(priv, true);
      await c.setRulepack(priv, 'reply(ping, "pong").');
      expect(c.handleInbound(scope: priv, text: 'unmatched'), isNull);
      expect(c.countersFor(priv).noMatch, 1);
      expect(c.countersFor(priv).suppressedRate, 0);
    });

    test('received counts everything the bot was offered', () async {
      final BotController c = make();
      await c.setEnabled(priv, true);
      await c.setRulepack(priv, 'reply(ping, "pong").');
      c.handleInbound(scope: priv, text: 'ping');
      c.handleInbound(scope: priv, text: 'nope');
      c.handleInbound(scope: priv, text: '[bot] loop');
      expect(c.countersFor(priv).received, 3);
      expect(c.countersFor(priv).replied, 1);
    });

    test('counters survive a reload for a long soak', () async {
      final BotController c = make();
      await c.setEnabled(priv, true);
      c.handleInbound(scope: priv, text: 'ping');

      final BotController c2 = make();
      await c2.load();
      expect(c2.countersFor(priv).replied, 1);
    });
  });

  group('R59 configuration', () {
    test('changing the seed actually reaches the engine', () async {
      // A cached responder would accept the UI change and quietly
      // ignore it.
      List<String?> runWithSeed(BotController c) => <String?>[
            for (int i = 0; i < 8; i++)
              c.handleInbound(scope: priv, text: 'hi')
          ];

      final BotController a = make();
      await a.setEnabled(priv, true);
      await a.setRulepack(priv, '''
reply(hi, "one").
reply(hi, "two").
reply(hi, "three").
''');
      await a.setMode(priv, BotMode.random);
      await a.setSeed(priv, 1);
      final List<String?> first = runWithSeed(a);

      await a.setSeed(priv, 999);
      final List<String?> second = runWithSeed(a);
      expect(first, isNot(equals(second)));
    });

    test('a null rulepack restores the shipped default', () async {
      final BotController c = make();
      await c.setRulepack(priv, 'reply(x, "y").');
      expect(c.rulepackSourceFor(priv), 'reply(x, "y").');
      await c.setRulepack(priv, null);
      expect(c.rulepackSourceFor(priv), kDefaultRulepack);
    });

    test('rulepack errors are reportable without breaking the bot',
        () async {
      final BotController c = make();
      await c.setEnabled(priv, true);
      await c.setRulepack(priv, '''
reply(ping, "pong").
reply(broken, "unterminated).
''');
      expect(c.rulepackErrorsFor(priv), hasLength(1));
      // The good clause still answers; only the broken line is lost.
      expect(c.handleInbound(scope: priv, text: 'ping'), '[bot] pong');
    });

    test('activeScopes lists what is running', () async {
      final BotController c = make();
      await c.setEnabled(priv, true);
      await c.setEnabled(dm, true);
      await c.setEnabled(dm, false);
      expect(c.activeScopes.map((BotScope s) => s.key), <String>[priv.key]);
    });

    test('a corrupt payload starts clean rather than throwing', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{BotController.kKey: 'not json'});
      final BotController c = make();
      await c.load();
      expect(c.bindings, isEmpty);
    });
  });
}
