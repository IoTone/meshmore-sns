// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/chat/composer_budget.dart';

void main() {
  group('ComposerBudget', () {
    test('counts the radio name in the same bytes as the encoder', () {
      // The firmware writes "<name>: " into the 160-byte buffer before the
      // text (BaseChatMesh.cpp:488-496), so the name is part of the budget.
      final ComposerBudget b = ComposerBudget.forSender('WIOld');
      expect(b.prefixBytes, ChannelTextLimits.bytesOf('WIOld: '));
      expect(b.prefixKnown, isTrue);
      expect(b.maxTextBytes, ChannelTextLimits.maxTextBytes - 7);

      const String text = 'hello mesh — メッシュ ✓';
      // The text half must come from the encoder's own counter, byte for byte.
      expect(b.usedFor(text),
          ChannelTextLimits.bytesOf(text) + b.prefixBytes);
    });

    test('an unknown name reserves the fallback and says so', () {
      final ComposerBudget b = ComposerBudget.forSender(null);
      expect(b.prefixKnown, isFalse);
      expect(b.prefixBytes, ComposerBudget.fallbackPrefixBytes);
      expect(ComposerBudget.forSender('').prefixBytes,
          ComposerBudget.fallbackPrefixBytes);
    });

    test('a long Japanese message is refused before an English one', () {
      final ComposerBudget b = ComposerBudget.forSender('WIOld');
      final String kana = 'あ' * 51;
      final String ascii = 'a' * 153;
      // Both are 153 text bytes; both fit exactly at maxTextBytes.
      expect(ChannelTextLimits.bytesOf(kana), 153);
      expect(b.stateFor(kana), isNot(ComposerState.over));
      expect(b.canSend(kana), isTrue);
      // One more kana (3 bytes) does not, while two more ASCII would.
      expect(b.stateFor('あ' * 52), ComposerState.over);
      expect(b.overBy('あ' * 52), 3);
      expect(b.canSend(ascii), isTrue);
      expect(b.canSend('${ascii}bb'), isFalse);
    });

    test('near is a warning, over is a refusal', () {
      final ComposerBudget b = ComposerBudget.forSender('abcd'); // 6 prefix
      expect(b.maxTextBytes, 154);
      expect(b.stateFor('a' * 100), ComposerState.ok);
      expect(b.stateFor('a' * 135), ComposerState.near); // 19 left
      expect(b.stateFor('a' * 140), ComposerState.near); // 14 left
      expect(b.stateFor('a' * 155), ComposerState.over);
      expect(b.canSend('a' * 154), isTrue);
      expect(b.canSend('a' * 155), isFalse);
      expect(b.canSend('   '), isFalse);
    });
  });
}
