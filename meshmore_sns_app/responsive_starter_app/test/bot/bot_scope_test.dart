// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart' show kPublicChannelPsk;
import 'package:meshmore_sns_app/bot/bot_scope.dart';

List<int> privatePsk() =>
    List<int>.generate(kPublicChannelPsk.length, (int i) => (i * 7 + 3) & 0xff);

void main() {
  group('R59 the bot never binds to Public', () {
    // The single most important rule in the feature. Enforced in the
    // binding path so a UI that forgot to grey out a switch, a
    // preference restored from an older build, or a future call site
    // that never heard of Public all hit the same gate.
    test('slot 0 is refused whatever key it currently holds', () {
      expect(
        botRefusalFor(const ChannelScope(0), (int _) => privatePsk()),
        BotRefusal.publicSlot,
      );
    });

    test('any slot still holding the public PSK is refused', () {
      // Renaming slot 3 to "Ops" while leaving the stock key protects
      // nothing — everything sent there is readable by every stock
      // radio on the mesh.
      expect(
        botRefusalFor(const ChannelScope(3), (int _) => kPublicChannelPsk),
        BotRefusal.publicPsk,
      );
    });

    test('an unseen key is refused until we can prove it is private', () {
      // Safe direction: a wrong "no" costs a delay, a wrong "yes" puts
      // a bot on Public.
      expect(
        botRefusalFor(const ChannelScope(2), (int _) => null),
        BotRefusal.unknownPsk,
      );
    });

    test('a private slot is allowed', () {
      expect(
        botRefusalFor(const ChannelScope(2), (int _) => privatePsk()),
        isNull,
      );
    });

    test('a DM is always allowed — there is no public equivalent', () {
      expect(botRefusalFor(DmScope('ab' * 32), (int _) => null), isNull);
    });

    test('a PSK of the wrong length is not mistaken for public', () {
      expect(pskIsPublic(<int>[1, 2, 3]), isFalse);
      expect(pskIsPublic(kPublicChannelPsk), isTrue);
    });
  });

  group('R59 scope keys round-trip', () {
    test('channel and DM keys survive persistence', () {
      const BotScope ch = ChannelScope(3);
      final BotScope dm = DmScope('AB' * 32);
      expect(BotScope.fromKey(ch.key), ch);
      expect(BotScope.fromKey(dm.key), dm);
    });

    test('pubkeys are normalised so one peer is one scope', () {
      expect(DmScope('AABB'), DmScope('aabb'));
      expect(DmScope('AABB').key, 'dm:aabb');
    });

    test('a malformed key yields null rather than a bogus scope', () {
      expect(BotScope.fromKey('nonsense'), isNull);
      expect(BotScope.fromKey('ch:notanumber'), isNull);
      expect(BotScope.fromKey('dm:'), isNull);
    });

    test('scopes of different kinds never collide', () {
      expect(const ChannelScope(1).key, isNot(DmScope('1').key));
    });
  });
}
