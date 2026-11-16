// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/bot/rule.dart';
import 'package:meshmore_sns_app/bot/rulepack_parser.dart';

void main() {
  final RulepackParser p = RulepackParser();

  group('R59 rulepack grammar', () {
    test('a bare clause parses to an atom pattern', () {
      final Rulepack pack = p.parse('reply(ping, "pong").');
      expect(pack.errors, isEmpty);
      expect(pack.rules, hasLength(1));
      expect(pack.rules.single.pattern.single, isA<Atom>());
      expect((pack.rules.single.pattern.single as Atom).text, 'ping');
      expect(pack.rules.single.response, 'pong');
    });

    test('an initial capital makes a variable, lowercase an atom', () {
      final Rulepack pack = p.parse('reply(hello Name, "hi {Name}").');
      expect(pack.errors, isEmpty);
      final List<PatternTerm> t = pack.rules.single.pattern;
      expect(t[0], isA<Atom>());
      expect(t[1], isA<Var>());
      expect((t[1] as Var).name, 'Name');
    });

    test('"..." makes a rest-variable, and keeps its name', () {
      final Rulepack pack = p.parse('reply(echo Rest..., "{Rest}").');
      expect(pack.errors, isEmpty);
      final PatternTerm last = pack.rules.single.pattern.last;
      expect(last, isA<RestVar>());
      expect((last as RestVar).name, 'Rest');
    });

    test('comments and blank lines are skipped, not errors', () {
      final Rulepack pack = p.parse('''
% a soak pack

reply(ping, "pong").

% trailing comment
''');
      expect(pack.errors, isEmpty);
      expect(pack.rules, hasLength(1));
    });

    test('clause order is preserved — determinism depends on it', () {
      final Rulepack pack = p.parse('''
reply(a, "1").
reply(b, "2").
reply(c, "3").
''');
      expect(pack.rules.map((BotRule r) => r.response), <String>['1', '2', '3']);
      expect(pack.rules.map((BotRule r) => r.sourceLine), <int>[1, 2, 3]);
    });

    // A rulepack is user-editable and the driving use case is an
    // unattended soak run. One bad line must not take the bot down.
    test('a bad line is carried as an error; good lines still load', () {
      final Rulepack pack = p.parse('''
reply(ping, "pong").
reply(oops, "unterminated).
reply(status, "ok").
''');
      expect(pack.rules, hasLength(2));
      expect(pack.errors, hasLength(1));
      expect(pack.errors.single, contains('line 2'));
    });

    test('a "..." anywhere but last is refused with a reason', () {
      final Rulepack pack = p.parse('reply(X... tail, "no").');
      expect(pack.rules, isEmpty);
      expect(pack.errors.single, contains('must be last'));
    });

    test('quoted atoms allow spaces and commas in a literal', () {
      final Rulepack pack = p.parse('reply("hello, world", "hi").');
      expect(pack.errors, isEmpty);
      expect((pack.rules.single.pattern.single as Atom).text, 'hello, world');
    });

    test('escaped quotes survive into the response', () {
      final Rulepack pack = p.parse(r'reply(q, "say \"hi\"").');
      expect(pack.errors, isEmpty);
      expect(pack.rules.single.response, 'say "hi"');
    });

    test('an empty pack is empty, not an error', () {
      final Rulepack pack = p.parse('');
      expect(pack.rules, isEmpty);
      expect(pack.errors, isEmpty);
      expect(pack.isEmpty, isTrue);
    });
  });

  group('R59 unification', () {
    List<String> tok(String s) => s.split(RegExp(r'\s+'))
      ..removeWhere((String t) => t.isEmpty);

    test('an atom pattern matches exactly, not as a prefix', () {
      final BotRule r = p.parse('reply(ping, "pong").').rules.single;
      expect(r.match(tok('ping')), isNotNull);
      // Without this, `ping` would fire on "ping the repeater".
      expect(r.match(tok('ping the repeater')), isNull);
      expect(r.match(tok('pin')), isNull);
    });

    test('atoms match case-insensitively', () {
      final BotRule r = p.parse('reply(ping, "pong").').rules.single;
      expect(r.match(tok('PING')), isNotNull);
      expect(r.match(tok('Ping')), isNotNull);
    });

    test('a variable binds exactly one token', () {
      final BotRule r = p.parse('reply(hello Name, "hi").').rules.single;
      expect(r.match(tok('hello alpha')), <String, String>{'Name': 'alpha'});
      expect(r.match(tok('hello')), isNull);
      expect(r.match(tok('hello alpha beta')), isNull);
    });

    test('a rest-variable binds the remainder, including nothing', () {
      final BotRule r = p.parse('reply(echo Rest..., "x").').rules.single;
      expect(r.match(tok('echo a b c')),
          <String, String>{'Rest': 'a b c'});
      expect(r.match(tok('echo')), <String, String>{'Rest': ''});
    });

    // Prolog semantics: the same variable twice must bind consistently.
    test('a repeated variable must bind the same token', () {
      final BotRule r = p.parse('reply(X X, "twice").').rules.single;
      expect(r.match(tok('ho ho')), isNotNull);
      expect(r.match(tok('ho hum')), isNull);
    });

    test('render interpolates bindings and the counter', () {
      final BotRule r =
          p.parse('reply(echo Rest..., "[bot #{N}] {Rest}").').rules.single;
      final Map<String, String>? b = r.match(tok('echo hello there'));
      expect(r.render(b!, 7), '[bot #7] hello there');
    });

    // A rulepack typo must not take the bot down mid-soak.
    test('an unknown placeholder renders empty rather than throwing', () {
      final BotRule r = p.parse('reply(ping, "a{Nope}b").').rules.single;
      expect(r.render(<String, String>{}, 1), 'ab');
    });
  });
}
