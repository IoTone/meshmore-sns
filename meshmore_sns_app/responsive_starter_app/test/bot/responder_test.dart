// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/bot/responder.dart';
import 'package:meshmore_sns_app/bot/rule.dart';
import 'package:meshmore_sns_app/bot/rulepack_parser.dart';

Rulepack pack(String src) => RulepackParser().parse(src);

void main() {
  group('R59 deterministic mode', () {
    // The property that makes a soak trace diffable.
    test('identical input yields identical output, run after run', () {
      String run() {
        final BotResponder b = BotResponder(
          pack: pack('''
reply(ping, "pong").
reply(a, "1").
reply(a, "2").
'''),
        );
        return <String?>[
          b.respondTo('ping'),
          b.respondTo('a'),
          b.respondTo('a'),
        ].join('|');
      }

      expect(run(), run());
      expect(run(), 'pong|1|1', reason: 'first matching clause always wins');
    });

    test('file order decides, not specificity', () {
      final BotResponder b = BotResponder(pack: pack('''
reply(Anything..., "catch-all").
reply(ping, "pong").
'''));
      // A catch-all placed first shadows everything after it. That is
      // the documented rule, and it is the operator's lever.
      expect(b.respondTo('ping'), 'catch-all');
    });

    test('no matching clause means no reply at all', () {
      final BotResponder b = BotResponder(pack: pack('reply(ping, "pong").'));
      expect(b.respondTo('something else'), isNull);
    });

    test('empty and whitespace-only input never replies', () {
      final BotResponder b =
          BotResponder(pack: pack('reply(X..., "always").'));
      expect(b.respondTo(''), isNull);
      expect(b.respondTo('   '), isNull);
    });
  });

  group('R59 the monotonic counter', () {
    test('counts replies, not attempts', () {
      final BotResponder b = BotResponder(pack: pack('''
reply(ping, "pong {N}").
'''));
      expect(b.respondTo('ping'), 'pong 1');
      expect(b.respondTo('nope'), isNull); // no match: must not advance
      expect(b.respondTo('ping'), 'pong 2');
      expect(b.counter, 2);
    });

    // Drops show as gaps, duplicates as a repeat, reordering as
    // out-of-sequence numbers — all from one read of the transcript.
    test('the default pack echoes with a sequence number', () {
      final BotResponder b =
          BotResponder(pack: pack(kDefaultRulepack));
      expect(b.respondTo('ping'), 'pong 1');
      expect(b.respondTo('status'), 'ok 2');
      expect(b.respondTo('hello there'), '#3 hello there');
    });

    test('the default pack always answers something', () {
      final BotResponder b = BotResponder(pack: pack(kDefaultRulepack));
      for (final String s in <String>['x', 'a b c', '???', 'PING']) {
        expect(b.respondTo(s), isNotNull, reason: s);
      }
    });

    test('a resumed run continues its numbering', () {
      final BotResponder b =
          BotResponder(pack: pack('reply(p, "{N}").'), counter: 41);
      expect(b.respondTo('p'), '42');
    });
  });

  group('R59 random mode', () {
    const String multi = '''
reply(hi, "one").
reply(hi, "two").
reply(hi, "three").
''';

    // "Random" must stay reproducible from its seed, or a soak failure
    // is undebuggable.
    test('the same seed and inputs replay the same outputs', () {
      List<String?> run() {
        final BotResponder b = BotResponder(
            pack: pack(multi), mode: BotMode.random, seed: 12345);
        return <String?>[for (int i = 0; i < 12; i++) b.respondTo('hi')];
      }

      expect(run(), run());
    });

    test('a different seed gives a different sequence', () {
      List<String?> runWith(int seed) {
        final BotResponder b = BotResponder(
            pack: pack(multi), mode: BotMode.random, seed: seed);
        return <String?>[for (int i = 0; i < 12; i++) b.respondTo('hi')];
      }

      expect(runWith(1), isNot(equals(runWith(2))));
    });

    test('it really does choose among all matches, not just the first',
        () {
      final BotResponder b = BotResponder(
          pack: pack(multi), mode: BotMode.random, seed: 7);
      final Set<String?> seen = <String?>{
        for (int i = 0; i < 40; i++) b.respondTo('hi'),
      };
      expect(seen.length, greaterThan(1));
      expect(seen, everyElement(isIn(<String>['one', 'two', 'three'])));
    });

    test('the seed is exposed so a run can be replayed', () {
      final BotResponder b = BotResponder(
          pack: pack(multi), mode: BotMode.random, seed: 99);
      expect(b.seed, 99);
    });

    test('a single match is not made random by the mode', () {
      final BotResponder b = BotResponder(
          pack: pack('reply(only, "answer").'),
          mode: BotMode.random,
          seed: 3);
      expect(b.respondTo('only'), 'answer');
    });
  });

  group('R59 tokenizing', () {
    test('punctuation stays attached to its word', () {
      // Stripping it would make `ping?` match `reply(ping, ...)`, which
      // is a surprise in the wrong direction for a determinism tool.
      final BotResponder b = BotResponder(pack: pack('reply(ping, "p").'));
      expect(b.respondTo('ping'), 'p');
      expect(b.respondTo('ping?'), isNull);
    });

    test('runs of whitespace collapse', () {
      expect(BotResponder.tokenize('a   b\t\tc'), <String>['a', 'b', 'c']);
    });
  });
}
