// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// R59 — the term language a bot rulepack is written in.
///
/// Prolog-shaped rather than LISP-shaped on purpose: a responder rule
/// *is* a unification — match the inbound text against a pattern,
/// binding variables as you go, then render a response from those
/// bindings. Nothing here evaluates or recurses; a rulepack is a flat
/// ordered list of `reply(Pattern, Response).` clauses.
library;

/// One element of a pattern.
sealed class PatternTerm {
  const PatternTerm();
}

/// A literal word. Matches one token, case-insensitively — operators
/// type `ping`, not `Ping`, and a soak rule that missed on capitalism
/// would be a nuisance rather than a feature.
class Atom extends PatternTerm {
  const Atom(this.text);
  final String text;

  @override
  String toString() => 'Atom($text)';
}

/// A variable binding exactly one token. Written with an initial
/// capital, as in Prolog: `reply(hello Name, "hi {Name}").`
class Var extends PatternTerm {
  const Var(this.name);
  final String name;

  @override
  String toString() => 'Var($name)';
}

/// A variable binding *the rest* of the message, zero tokens included.
/// Written `Name...`. At most one per pattern, and only in final
/// position — anywhere else it would need backtracking, and a soak
/// rulepack is not worth a backtracking engine.
class RestVar extends PatternTerm {
  const RestVar(this.name);
  final String name;

  @override
  String toString() => 'RestVar($name)';
}

/// One `reply(Pattern, Response).` clause.
class BotRule {
  const BotRule({
    required this.pattern,
    required this.response,
    required this.sourceLine,
  });

  final List<PatternTerm> pattern;

  /// Response template. `{Name}` interpolates a binding; `{N}` the
  /// responder's monotonic counter. Unknown names render empty rather
  /// than throwing — a rulepack typo must not take the bot down
  /// mid-soak.
  final String response;

  /// 1-based line in the rulepack, for error reporting.
  final int sourceLine;

  /// Try to match [tokens], returning bindings or null.
  ///
  /// Greedy only in the trivial sense: [RestVar] is terminal, so there
  /// is exactly one way to match and no backtracking is possible.
  Map<String, String>? match(List<String> tokens) {
    final Map<String, String> out = <String, String>{};
    int i = 0;
    for (int p = 0; p < pattern.length; p++) {
      final PatternTerm term = pattern[p];
      switch (term) {
        case RestVar(name: final String n):
          out[n] = tokens.sublist(i).join(' ');
          return out; // terminal by construction
        case Var(name: final String n):
          if (i >= tokens.length) return null;
          // A repeated variable must bind consistently, as in Prolog:
          // `reply(X X, "you said {X} twice")`.
          final String v = tokens[i];
          final String? prior = out[n];
          if (prior != null && prior.toLowerCase() != v.toLowerCase()) {
            return null;
          }
          out[n] = v;
          i++;
        case Atom(text: final String a):
          if (i >= tokens.length) return null;
          if (tokens[i].toLowerCase() != a.toLowerCase()) return null;
          i++;
      }
    }
    // No RestVar consumed the tail, so the match must be exact —
    // otherwise `reply(ping, ...)` would fire on "ping the repeater".
    return i == tokens.length ? out : null;
  }

  /// Render [response] with [bindings], plus `{N}` → [counter].
  String render(Map<String, String> bindings, int counter) {
    return response.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (Match m) {
        final String key = m[1]!;
        if (key == 'N') return '$counter';
        return bindings[key] ?? '';
      },
    );
  }
}

/// A parsed rulepack: ordered clauses plus whatever failed to parse.
///
/// Parse errors are *carried*, not thrown. A rulepack is user-editable
/// and a soak run should not die because line 12 has a typo — the good
/// rules still load, and the bad lines surface in Diagnostics.
class Rulepack {
  const Rulepack({required this.rules, this.errors = const <String>[]});

  final List<BotRule> rules;
  final List<String> errors;

  bool get isEmpty => rules.isEmpty;
}
