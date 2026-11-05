// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/notifications/mention_matcher.dart';

/// D8.13 — a mention is the display name as a whole word or `@name`, and the
/// key suffix only when the user opts in. The near-misses matter more than
/// the hits: a false mention is an alert at 3 a.m.
void main() {
  group('whole word', () {
    test('matches the name on its own', () {
      expect(isMentioned('Sam', 'Sam'), isTrue);
    });

    test('matches after punctuation and before text', () {
      expect(isMentioned('Sam: are you there', 'Sam'), isTrue);
      expect(isMentioned('hi Sam, meet at 5', 'Sam'), isTrue);
      expect(isMentioned('SOS been hit, Sam needs help', 'Sam'), isTrue);
    });

    test('does not match a longer word that starts with the name', () {
      expect(isMentioned('Samantha took the truck', 'Sam'), isFalse);
      expect(isMentioned('Samsara is a word', 'Sam'), isFalse);
    });

    test('does not match a longer word that ends with the name', () {
      expect(isMentioned('I saw the samurai', 'Sam'), isFalse);
    });

    test('is case-insensitive', () {
      expect(isMentioned('sam is here', 'Sam'), isTrue);
    });

    test('an empty display name never matches', () {
      expect(isMentioned('anything', ''), isFalse);
      expect(isMentioned('anything', null), isFalse);
    });
  });

  group('@name', () {
    test('matches anywhere in the sentence', () {
      expect(isMentioned('ping @Sam please', 'Sam'), isTrue);
      expect(isMentioned('@Sam', 'Sam'), isTrue);
    });

    test('does not match a longer handle', () {
      expect(isMentioned('@Samantha hello', 'Sam'), isFalse);
    });
  });

  group('key suffix opt-in', () {
    test('is off by default even when the suffix appears', () {
      expect(
        isMentioned('abcd is a word', 'Zed', keySuffix: 'abcd'),
        isFalse,
      );
    });

    test('matches only when asked for', () {
      expect(
        isMentioned('abcd is a word', 'Zed',
            keySuffix: 'abcd', matchKeySuffix: true),
        isTrue,
      );
    });

    test('needs at least four hex characters to be considered', () {
      expect(
        isMentioned('abc appears', 'Zed',
            keySuffix: 'abc', matchKeySuffix: true),
        isFalse,
      );
    });
  });
}
