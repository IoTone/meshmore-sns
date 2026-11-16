// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart' show kPublicChannelPsk;
import 'package:meshmore_sns_app/bot/bot_controller.dart';
import 'package:meshmore_sns_app/bot/bot_guards.dart';
import 'package:meshmore_sns_app/bot/bot_scope.dart';
import 'package:meshmore_sns_app/bot/responder.dart';
import 'package:shared_preferences/shared_preferences.dart';

const BotScope priv = ChannelScope(2);
final BotScope dm = DmScope('cd' * 32);

BotController make() => BotController(
      pskFor: (int _) =>
          List<int>.generate(kPublicChannelPsk.length, (int i) => i + 1),
      now: () => DateTime.utc(2026, 3, 4, 5, 6, 7),
      rateLimit: const BotRateLimit(
          minInterval: Duration.zero, maxPerWindow: 1000),
    );

Map<String, Object?> report(BotController c) =>
    json.decode(c.exportReport()) as Map<String, Object?>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('R59 soak report', () {
    test('an unused bot reports no scopes rather than failing', () {
      final Map<String, Object?> r = report(make());
      expect(r['scopes'], isEmpty);
      expect(r['generatedAt'], isNotNull);
    });

    // A result nobody can replay is not a result: mode, seed and the
    // reply counter have to travel with the counts.
    test('the report carries everything needed to replay a run',
        () async {
      final BotController c = make();
      await c.setEnabled(priv, true);
      await c.setMode(priv, BotMode.random);
      await c.setSeed(priv, 4242);
      c.handleInbound(scope: priv, text: 'ping');

      final Map<String, Object?> scope =
          (report(c)['scopes']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(scope['scope'], 'ch:2');
      expect(scope['enabled'], isTrue);
      expect(scope['mode'], 'random');
      expect(scope['seed'], 4242);
      expect(scope['replyCounter'], 1);
      expect((scope['counters']! as Map<String, Object?>)['replied'], 1);
    });

    test('a custom rulepack is flagged, not dumped', () async {
      // The pack can be long and is already in the editor; what the
      // reader needs to know is whether the default was in play.
      final BotController c = make();
      await c.setEnabled(priv, true);
      expect(
        ((report(c)['scopes']! as List<Object?>).single!
            as Map<String, Object?>)['customRulepack'],
        isFalse,
      );
      await c.setRulepack(priv, 'reply(x, "y").');
      expect(
        ((report(c)['scopes']! as List<Object?>).single!
            as Map<String, Object?>)['customRulepack'],
        isTrue,
      );
    });

    test('a disabled scope is still reported', () async {
      // "It was bound but switched off" and "it was never bound" are
      // different findings after a soak.
      final BotController c = make();
      await c.setEnabled(priv, true);
      await c.setEnabled(priv, false);
      final Map<String, Object?> scope =
          (report(c)['scopes']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(scope['enabled'], isFalse);
    });

    test('our own key is included when known', () async {
      final BotController c = make();
      c.ownPubKeyHex = 'ab' * 32;
      expect(report(c)['self'], 'ab' * 32);
    });

    test('the report is valid, re-parseable JSON', () async {
      final BotController c = make();
      await c.setEnabled(priv, true);
      await c.setEnabled(dm, true);
      c.handleInbound(scope: dm, text: 'ping');
      expect(() => json.decode(c.exportReport()), returnsNormally);
      expect((report(c)['scopes']! as List<Object?>), hasLength(2));
    });
  });

  group('R59 totals', () {
    test('sum across scopes, each bucket kept separate', () async {
      final BotController c = make();
      await c.setEnabled(priv, true);
      await c.setEnabled(dm, true);
      c.handleInbound(scope: priv, text: 'ping');
      c.handleInbound(scope: dm, text: 'ping');
      c.handleInbound(scope: dm, text: '[bot] loop');

      final BotCounters t = c.totals();
      expect(t.received, 3);
      expect(t.replied, 2);
      expect(t.suppressedLoop, 1);
    });

    test('totals of nothing are zero, not an error', () {
      expect(make().totals().toJson().values, everyElement(0));
    });
  });
}
