// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/sos/sos_engine.dart';
import 'package:meshmore_sns_app/sos/sos_message.dart';
import 'package:meshmore_sns_app/sos/sos_schedule.dart';

/// A clock the test moves by hand: the whole point of the engine is that a
/// 3600-second scenario costs no wall time.
class _Clock {
  _Clock(this.now);
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  final DateTime raisedAt = DateTime.utc(2026, 11, 5, 12);
  final List<int> nonce = List<int>.filled(16, 9);
  final List<int> targetKey = List<int>.generate(32, (int i) => i);
  final List<int> strangerKey = List<int>.generate(32, (int i) => 255 - i);

  SosRaise raiseFor(DateTime at, {List<List<int>>? keys, String words = 'trail washed out'}) =>
      SosRaise(
        id: 'a1b2c3',
        nonce: nonce,
        raisedAt: at,
        callsign: 'W1ABC',
        words: words,
        targets: SosTargets(
          channelId: 'ch-emergency',
          contactKeys: keys ?? <List<int>>[targetKey],
        ),
        lat: 39.7392,
        lon: -104.9903,
        fixAt: at.subtract(const Duration(minutes: 5)),
      );

  /// Raises, waits out the hold and confirms; the common start of a test.
  SosEngine active({_Clock? clock, SosRaise? request}) {
    final _Clock c = clock ?? _Clock(raisedAt);
    final SosEngine e = SosEngine(clock: () => c.now);
    final SosRefusal? refused = e.raise(request ?? raiseFor(raisedAt));
    expect(refused, isNull);
    c.advance(SosEngine.hold);
    expect(e.confirm(), isNull);
    expect(e.state, SosState.active);
    return e;
  }

  group('arming', () {
    test('the hold is three seconds, and confirming early is refused', () {
      final _Clock clock = _Clock(raisedAt);
      final SosEngine e = SosEngine(clock: () => clock.now);
      expect(e.raise(raiseFor(raisedAt)), isNull);
      expect(e.state, SosState.arming);
      expect(e.confirm(), SosRefusal.holdNotComplete);
      clock.advance(const Duration(seconds: 2));
      expect(e.confirm(), SosRefusal.holdNotComplete);
      clock.advance(const Duration(seconds: 1));
      expect(e.confirm(), isNull);
      expect(e.state, SosState.active);
    });

    test('aborting the hold raises nothing at all', () {
      final _Clock clock = _Clock(raisedAt);
      final SosEngine e = SosEngine(clock: () => clock.now);
      e.raise(raiseFor(raisedAt));
      e.abort();
      expect(e.state, SosState.idle);
      clock.advance(const Duration(minutes: 10));
      expect(e.advanceTo(clock.now), isEmpty);
    });

    test('a second raise while one is running is refused', () {
      final SosEngine e = active();
      expect(e.raise(raiseFor(raisedAt)), SosRefusal.alreadyActive);
    });

    test('a raise with nowhere to go, no words, no id or too many words is refused', () {
      final SosEngine e = SosEngine(clock: () => raisedAt);
      expect(
        e.raise(SosRaise(
          id: 'a1b2c3',
          nonce: nonce,
          raisedAt: raisedAt,
          callsign: 'W1ABC',
          words: 'help',
          targets: SosTargets(),
        )),
        SosRefusal.noDestination,
      );
      expect(
        e.raise(SosRaise(
          id: 'a1b2c3',
          nonce: nonce,
          raisedAt: raisedAt,
          callsign: 'W1ABC',
          words: '   ',
          targets: SosTargets(channelId: 'ch'),
        )),
        SosRefusal.noWords,
      );
      expect(
        e.raise(SosRaise(
          id: 'nope',
          nonce: nonce,
          raisedAt: raisedAt,
          callsign: 'W1ABC',
          words: 'help',
          targets: SosTargets(channelId: 'ch'),
        )),
        SosRefusal.noIdentity,
      );
      expect(
        e.raise(raiseFor(raisedAt, words: 'x' * 200)),
        SosRefusal.tooLong,
      );
      expect(e.state, SosState.idle);
    });
  });

  group('the schedule on a fake clock', () {
    test('twelve sends at 0-660 s, ten beacons at 720-3420 s, then the stop', () {
      final _Clock clock = _Clock(raisedAt);
      final SosEngine e = active(clock: clock);

      final List<SosSend> first = e.advanceTo(clock.now);
      expect(first, hasLength(1));
      expect(first.single.packet.kind, SosPacketKind.send);
      expect(first.single.packet.index, 1);

      int sends = 1;
      int beacons = 0;
      for (int second = 1; second <= 3600; second++) {
        clock.advance(const Duration(seconds: 1));
        final List<SosSend> due = e.advanceTo(clock.now);
        final int elapsed = clock.now.difference(raisedAt).inSeconds;
        for (final SosSend s in due) {
          if (s.packet.kind == SosPacketKind.send) {
            sends++;
            expect(elapsed, 60 * (s.packet.index - 1),
                reason: 'send ${s.packet.index} leaves at t=${60 * (s.packet.index - 1)}s');
          } else {
            beacons++;
            expect(elapsed, 720 + 300 * (s.packet.index - 1),
                reason: 'beacon ${s.packet.index} leaves at its five-minute mark');
          }
        }
        if (second == 3600) {
          expect(due, isEmpty, reason: 'the hard stop emits nothing');
        }
      }
      expect(sends, 12);
      expect(beacons, 10);
      expect(e.state, SosState.expired);
    });

    test('nothing is emitted after the hard stop', () {
      final _Clock clock = _Clock(raisedAt);
      final SosEngine e = active(clock: clock);
      clock.advance(const Duration(seconds: 3600));
      expect(e.advanceTo(clock.now), isEmpty);
      expect(e.state, SosState.expired);
      clock.advance(const Duration(hours: 2));
      expect(e.advanceTo(clock.now), isEmpty);
    });

    test('a clock that jumps backwards does not replay the schedule', () {
      final _Clock clock = _Clock(raisedAt);
      final SosEngine e = active(clock: clock);
      e.advanceTo(clock.now);
      clock.now = raisedAt.subtract(const Duration(hours: 1));
      expect(e.advanceTo(clock.now), isEmpty);
    });

    test('two sends of one alarm never carry the same bytes', () {
      final _Clock clock = _Clock(raisedAt);
      final SosEngine e = active(clock: clock);
      final String a = e.advanceTo(clock.now).single.text;
      clock.advance(const Duration(seconds: 60));
      final String b = e.advanceTo(clock.now).single.text;
      expect(a, isNot(b));
      expect(a, contains('[SOS:a1b2c3]'));
    });

    test('a stale fix sends NOFIX and the schedule still runs 22 packets', () {
      final _Clock clock = _Clock(raisedAt);
      final SosRaise r = SosRaise(
        id: 'a1b2c3',
        nonce: nonce,
        raisedAt: raisedAt,
        callsign: 'W1ABC',
        words: 'trail washed out',
        targets: SosTargets(channelId: 'ch-emergency'),
        lat: 39.7392,
        lon: -104.9903,
        fixAt: raisedAt.subtract(const Duration(hours: 3)),
      );
      final SosEngine e = active(clock: clock, request: r);
      final SosSend first = e.advanceTo(clock.now).single;
      expect(first.text, contains('NOFIX'));
      expect(first.text, isNot(contains('39.7392')));
      expect(first.fixAge, isNull);

      int emitted = 1;
      for (int second = 1; second <= 3420; second++) {
        clock.advance(const Duration(seconds: 1));
        emitted += e.advanceTo(clock.now).length;
      }
      expect(emitted, 22);
    });
  });

  group('acknowledgement attribution', () {
    SosAckMessage ack({String id = 'a1b2c3', String name = 'W2XYZ'}) =>
        SosAckMessage(id: id, callsign: name, text: 'on my way');

    test('a channel ACK is claimed, and the alarm keeps going', () {
      final _Clock clock = _Clock(raisedAt);
      final SosEngine e = active(clock: clock);
      expect(
        e.recordAck(ack(), direct: false),
        SosAckOutcome.claimed,
      );
      expect(e.state, SosState.active);
      clock.advance(const Duration(seconds: 60));
      // Nothing was drained yet, so both due sends come out: t=0 and t=60.
      expect(e.advanceTo(clock.now), hasLength(2));
    });

    test('a direct ACK from an addressed key stops the alarm', () {
      final _Clock clock = _Clock(raisedAt);
      final SosEngine e = active(clock: clock);
      expect(
        e.recordAck(ack(), direct: true, fromKey: targetKey),
        SosAckOutcome.stopped,
      );
      expect(e.state, SosState.acknowledged);
      clock.advance(const Duration(seconds: 120));
      expect(e.advanceTo(clock.now), isEmpty);
    });

    test('a direct ACK from a stranger is counted and does not stop it', () {
      final _Clock clock = _Clock(raisedAt);
      final SosEngine e = active(clock: clock);
      expect(
        e.recordAck(ack(), direct: true, fromKey: strangerKey),
        SosAckOutcome.countedNotAddressed,
      );
      expect(e.state, SosState.active);
      clock.advance(const Duration(seconds: 60));
      expect(e.advanceTo(clock.now), hasLength(2));
    });

    test('the same key twice is one row', () {
      final SosEngine e = active();
      expect(e.recordAck(ack(), direct: true, fromKey: targetKey),
          SosAckOutcome.stopped);
      // A second ACK after the stop is not a second row and changes nothing.
      expect(e.recordAck(ack(), direct: true, fromKey: targetKey),
          SosAckOutcome.ignored);
    });

    test('an ACK for another request, or after the stop, is ignored', () {
      final _Clock clock = _Clock(raisedAt);
      final SosEngine e = active(clock: clock);
      expect(e.recordAck(ack(id: 'ffffff'), direct: true, fromKey: targetKey),
          SosAckOutcome.ignored);
      expect(e.state, SosState.active);
      clock.advance(const Duration(seconds: 3600));
      e.advanceTo(clock.now);
      expect(e.state, SosState.expired);
      expect(e.recordAck(ack(), direct: true, fromKey: targetKey),
          SosAckOutcome.ignored);
    });
  });

  group('stopping on purpose', () {
    test('"I am safe" sends one SAFE and stops both loops', () {
      final _Clock clock = _Clock(raisedAt);
      final SosEngine e = active(clock: clock);
      final ({String? text, SosMessageRefusal? refusal})? safe = e.iAmSafe();
      expect(safe, isNotNull);
      expect(safe!.text, '[SAFE:a1b2c3] W1ABC');
      expect(e.state, SosState.cancelled);
      expect(e.iAmSafe(), isNull, reason: 'exactly one SAFE per alarm');
      clock.advance(const Duration(seconds: 120));
      expect(e.advanceTo(clock.now), isEmpty);
    });

    test('cancel ends the schedule; the row survives for the record', () {
      final _Clock clock = _Clock(raisedAt);
      final SosEngine e = active(clock: clock);
      e.cancel();
      expect(e.state, SosState.cancelled);
      clock.advance(const Duration(seconds: 120));
      expect(e.advanceTo(clock.now), isEmpty);
      expect(e.snapshot()!.raise.id, 'a1b2c3');
    });

    test('dismissing moves an ended alarm to closed', () {
      final SosEngine e = active();
      e.cancel();
      e.dismiss();
      expect(e.state, SosState.closed);
    });
  });

  group('process death', () {
    test('a restored alarm resumes the remainder with fresh sends, not a replay', () {
      final _Clock clock = _Clock(raisedAt);
      final SosEngine first = active(clock: clock);
      // Seven sends went out before the process died at t=400 s.
      final Set<String> issued = <String>{
        for (int i = 1; i <= 7; i++) 'send#$i',
      };
      final SosSnapshot snapshot = SosSnapshot(
        state: SosState.active,
        raise: first.activeRequest!,
        issued: issued,
      );

      clock.now = raisedAt.add(const Duration(seconds: 400));
      final SosEngine restored = SosEngine(clock: () => clock.now);
      restored.restore(snapshot);
      expect(restored.state, SosState.active);
      expect(restored.advanceTo(clock.now), isEmpty,
          reason: 'nothing is due between sends');

      clock.now = raisedAt.add(const Duration(seconds: 420));
      final List<SosSend> due = restored.advanceTo(clock.now);
      expect(due, hasLength(1));
      expect(due.single.packet.index, 8);
      expect(due.single.text, contains('[SOS:a1b2c3]'));
    });

    test('a restored alarm whose hour passed is expired, not resumed', () {
      final _Clock clock = _Clock(raisedAt);
      final SosEngine first = active(clock: clock);
      final SosSnapshot snapshot = SosSnapshot(
        state: SosState.active,
        raise: first.activeRequest!,
        issued: const <String>{},
      );
      clock.now = raisedAt.add(const Duration(hours: 2));
      final SosEngine restored = SosEngine(clock: () => clock.now);
      restored.restore(snapshot);
      expect(restored.advanceTo(clock.now), isEmpty);
      expect(restored.state, SosState.expired);
    });
  });
}
