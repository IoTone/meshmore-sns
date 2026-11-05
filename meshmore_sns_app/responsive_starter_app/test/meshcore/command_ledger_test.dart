// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/command_ledger.dart';

void main() {
  group('CommandLedger', () {
    test('a reply claims the oldest command of its own kind', () {
      final CommandLedger l = CommandLedger();
      l.register('a', CommandAnswer.ok);
      l.register('b', CommandAnswer.ok);
      expect(l.claim(CommandAnswer.ok)?.id, 'a');
      expect(l.claim(CommandAnswer.ok)?.id, 'b');
      expect(l.isEmpty, isTrue);
      expect(l.unclaimed, 0);
    });

    test('a SENT never claims a channel text', () {
      final CommandLedger l = CommandLedger();
      l.register('chan', CommandAnswer.ok);
      expect(l.claim(CommandAnswer.sent), isNull);
      expect(l.unclaimed, 1, reason: 'a reply nobody asked for is recorded');
      expect(l.isPending('chan'), isTrue,
          reason: 'and it must not be spent on the wrong kind');
    });

    test('two commands of one kind cannot swap: the oldest is answered first',
        () {
      final CommandLedger l = CommandLedger();
      l.register('first', CommandAnswer.sent);
      l.register('second', CommandAnswer.sent);
      expect(l.claim(CommandAnswer.sent)?.id, 'first');
      expect(l.pendingIds, <String>['second']);
    });

    test('a duplicate answer is unclaimed, not spent twice', () {
      final CommandLedger l = CommandLedger();
      l.register('a', CommandAnswer.ok);
      expect(l.claim(CommandAnswer.ok)?.id, 'a');
      expect(l.claim(CommandAnswer.ok), isNull);
      expect(l.unclaimed, 1);
    });

    test('an entry that outlives the timeout is expired, then its answer is '
        'unclaimed', () {
      DateTime now = DateTime(2026, 11, 5, 12);
      final CommandLedger l = CommandLedger(
        timeout: const Duration(seconds: 10),
        clock: () => now,
      );
      l.register('slow', CommandAnswer.ok);
      expect(l.expire(), isEmpty);
      now = now.add(const Duration(seconds: 11));
      expect(l.expire(), <String>['slow']);
      expect(l.unanswered, 1);
      expect(l.claim(CommandAnswer.ok), isNull);
      expect(l.unclaimed, 1, reason: 'the late answer credits nothing');
    });

    test('expiry only clears the head, so a fresh command keeps its place',
        () {
      DateTime now = DateTime(2026, 11, 5, 12);
      final CommandLedger l = CommandLedger(
        timeout: const Duration(seconds: 10),
        clock: () => now,
      );
      l.register('old', CommandAnswer.ok);
      now = now.add(const Duration(seconds: 5));
      l.register('fresh', CommandAnswer.ok);
      now = now.add(const Duration(seconds: 6));
      expect(l.expire(), <String>['old']);
      expect(l.pendingIds, <String>['fresh']);
    });

    test('an error takes the head whatever kind it waits for', () {
      final CommandLedger l = CommandLedger();
      l.register('dm', CommandAnswer.sent);
      l.register('text', CommandAnswer.ok);
      expect(l.takeHead()?.id, 'dm');
      expect(l.takeHead()?.id, 'text');
      expect(l.unclaimed, 0);
    });

    test('an abandoned command is not counted as unanswered', () {
      final CommandLedger l = CommandLedger();
      l.register('gone', CommandAnswer.ok);
      expect(l.drop('gone'), isTrue);
      expect(l.unanswered, 0);
      expect(l.isEmpty, isTrue);
    });

    test('one id cannot wait twice', () {
      final CommandLedger l = CommandLedger();
      l.register('m1', CommandAnswer.ok);
      expect(() => l.register('m1', CommandAnswer.ok), throwsStateError);
    });

    test('a new link forgets what the old one was waiting for', () {
      final CommandLedger l = CommandLedger();
      l.register('a', CommandAnswer.ok);
      l.register('b', CommandAnswer.sent);
      l.reset();
      expect(l.isEmpty, isTrue);
      expect(l.claim(CommandAnswer.ok), isNull);
    });
  });
}
