// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:petitparser/petitparser.dart';

import 'rule.dart';

/// R59 — parses a rulepack into [BotRule]s.
///
/// Grammar, one clause per line:
/// ```
///   % a comment
///   reply(ping, "pong").
///   reply(hello Name, "hi {Name}").
///   reply(echo Rest..., "[bot #{N}] {Rest}").
/// ```
///
/// Parsed **line by line** rather than as one big grammar so a single
/// bad clause costs exactly that clause. A rulepack is user-editable
/// and the driving use case is an unattended soak run; taking the
/// whole bot down because line 12 lost a quote would be the wrong
/// trade.
class RulepackParser {
  RulepackParser() : _clause = _buildClause();

  final Parser<BotRule Function(int)> _clause;

  static Parser<BotRule Function(int)> _buildClause() {
    final Parser<String> ws = whitespace().star().flatten();

    // A double-quoted string with \" and \\ escapes.
    final Parser<String> quoted = (char('"') &
            (char(r'\') & any() | pattern('^"\\')).star().flatten() &
            char('"'))
        .map((List<Object?> v) => _unescape(v[1]! as String));

    // Pattern terms. Order matters: RestVar before Var so `X...` is
    // not read as `X` followed by junk.
    final Parser<PatternTerm> restVar =
        (pattern('A-Z') & pattern('A-Za-z0-9_').star() & string('...'))
            .flatten()
            .map((String s) =>
                RestVar(s.substring(0, s.length - 3)));

    final Parser<PatternTerm> variable =
        (pattern('A-Z') & pattern('A-Za-z0-9_').star())
            .flatten()
            .map((String s) => Var(s));

    // A bare atom is any run of non-space, non-comma, non-paren text.
    // Quoted atoms let a literal contain spaces or a comma.
    final Parser<PatternTerm> quotedAtom = quoted.map((String s) => Atom(s));
    final Parser<PatternTerm> bareAtom =
        pattern('^ \t,()').plus().flatten().map((String s) => Atom(s));

    final Parser<PatternTerm> term =
        (restVar | variable | quotedAtom | bareAtom).cast<PatternTerm>();

    final Parser<List<PatternTerm>> patternList =
        term.plusSeparated(ws).map((SeparatedList<PatternTerm, String> l) =>
            l.elements.toList());

    final Parser<BotRule Function(int)> clause = (ws &
            string('reply') &
            ws &
            char('(') &
            ws &
            patternList &
            ws &
            char(',') &
            ws &
            quoted &
            ws &
            char(')') &
            ws &
            char('.') &
            ws)
        .end()
        .map((List<Object?> v) {
      final List<PatternTerm> pat = v[5]! as List<PatternTerm>;
      final String resp = v[9]! as String;
      return (int line) =>
          BotRule(pattern: pat, response: resp, sourceLine: line);
    });

    return clause;
  }

  static String _unescape(String s) =>
      s.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');

  /// Parse [source]. Never throws: unparseable lines land in
  /// [Rulepack.errors] and the rest still load.
  Rulepack parse(String source) {
    final List<BotRule> rules = <BotRule>[];
    final List<String> errors = <String>[];
    final List<String> lines = source.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final String raw = lines[i];
      final String line = raw.trim();
      if (line.isEmpty || line.startsWith('%')) continue;

      final Result<BotRule Function(int)> r = _clause.parse(line);
      if (r is Failure) {
        errors.add('line ${i + 1}: ${r.message} — "$line"');
        continue;
      }
      final BotRule rule = r.value(i + 1);
      final String? problem = _validate(rule);
      if (problem != null) {
        errors.add('line ${i + 1}: $problem');
        continue;
      }
      rules.add(rule);
    }
    return Rulepack(rules: rules, errors: errors);
  }

  /// Structural checks the grammar cannot express.
  static String? _validate(BotRule r) {
    if (r.pattern.isEmpty) return 'empty pattern';
    for (int i = 0; i < r.pattern.length; i++) {
      if (r.pattern[i] is RestVar && i != r.pattern.length - 1) {
        // Matching a rest-variable anywhere but the end needs
        // backtracking, and a soak rulepack does not earn that.
        return 'a "..." variable must be last in the pattern';
      }
    }
    return null;
  }
}
