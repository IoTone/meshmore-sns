// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/places/place_confirmation.dart';

final DateTime _now = DateTime.utc(2026, 11, 5, 12);
const String _id = 'a1b2c3d4';

PlaceReply _reply(
  PlaceReplyKind kind, {
  String callsign = 'W1ABC',
  String? keyHex,
  String id = _id,
}) =>
    PlaceReply(
      kind: kind,
      id8: id,
      callsign: callsign,
      attribution: keyHex == null
          ? PlaceReplyAttribution.claimed
          : PlaceReplyAttribution.keyBound,
      reporterKeyHex: keyHex,
    );

void main() {
  group('the wire grammar', () {
    test('a confirmation parses from channel text as claimed', () {
      final PlaceReplyOutcome outcome =
          parsePlaceReply('[CONFIRM:$_id] W2XYZ');
      expect(outcome.isReply, isTrue);
      final PlaceReply reply = outcome.reply!;
      expect(reply.kind, PlaceReplyKind.confirm);
      expect(reply.id8, _id);
      expect(reply.callsign, 'W2XYZ');
      expect(reply.attribution, PlaceReplyAttribution.claimed);
      expect(reply.reporterKeyHex, isNull);
    });

    test('a refutation from a direct message is key-bound', () {
      final PlaceReplyOutcome outcome = parsePlaceReply(
          '[REFUTE:$_id] W2XYZ',
          reporterKeyHex: '00ff');
      expect(outcome.reply!.kind, PlaceReplyKind.refute);
      expect(outcome.reply!.attribution, PlaceReplyAttribution.keyBound);
      expect(outcome.reply!.reporterKeyHex, '00ff');
    });

    test('the callsign falls back to the message sender', () {
      final PlaceReplyOutcome outcome =
          parsePlaceReply('[CONFIRM:$_id]', senderName: 'W3QQQ');
      expect(outcome.reply!.callsign, 'W3QQQ');
    });

    test('an id in capitals is normalised', () {
      expect(parsePlaceReply('[CONFIRM:A1B2C3D4] W1ABC').reply!.id8, _id);
    });

    test('a message with no tag is not a reply', () {
      expect(parsePlaceReply('confirmation $_id').failure,
          PlaceReplyFailure.notAReply);
      expect(parsePlaceReply('[SAFE:$_id] W1ABC').failure,
          PlaceReplyFailure.notAReply);
    });

    test('an id that is not eight hex characters is refused', () {
      expect(parsePlaceReply('[CONFIRM:a1b2c3] W1ABC').failure,
          PlaceReplyFailure.badId);
      expect(parsePlaceReply('[CONFIRM:a1b2c3d4e5] W1ABC').failure,
          PlaceReplyFailure.badId);
      expect(parsePlaceReply('[CONFIRM:zzzzzzzz] W1ABC').failure,
          PlaceReplyFailure.badId);
      expect(parsePlaceReply('[CONFIRM:$_id').failure,
          PlaceReplyFailure.badId);
    });

    test('no callsign anywhere is refused', () {
      expect(parsePlaceReply('[CONFIRM:$_id]').failure,
          PlaceReplyFailure.emptyCallsign);
    });

    test('encoding is the line the parser reads back', () {
      final PlaceReply reply = _reply(PlaceReplyKind.refute, callsign: 'W9ZZZ');
      expect(encodePlaceReply(reply), '[REFUTE:$_id] W9ZZZ');
      expect(
          parsePlaceReply(encodePlaceReply(reply), senderName: 'x').reply,
          reply);
    });
  });

  group('the tally', () {
    test('one count per identity per id, however often it repeats', () {
      final PlaceConfirmationTally tally = PlaceConfirmationTally();
      expect(tally.record(_reply(PlaceReplyKind.confirm, keyHex: 'aa'), at: _now),
          isTrue);
      expect(
          tally.record(_reply(PlaceReplyKind.confirm, keyHex: 'aa'),
              at: _now.add(const Duration(minutes: 1))),
          isFalse);
      expect(tally.summaryFor(_id).confirming, 1);
    });

    test('claimed and key-bound confirmations are counted apart', () {
      final PlaceConfirmationTally tally = PlaceConfirmationTally();
      tally.record(_reply(PlaceReplyKind.confirm, keyHex: 'aa'), at: _now);
      tally.record(_reply(PlaceReplyKind.confirm, callsign: 'W2'), at: _now);
      tally.record(_reply(PlaceReplyKind.confirm, callsign: 'w2 '), at: _now);
      final PlaceConfirmationSummary summary = tally.summaryFor(_id);
      expect(summary.confirming, 1);
      expect(summary.claimedConfirming, 1);
      expect(summary.totalConfirming, 2);
    });

    test('five are shown and the rest are counted', () {
      final PlaceConfirmationTally tally = PlaceConfirmationTally();
      for (int i = 0; i < 12; i++) {
        tally.record(_reply(PlaceReplyKind.confirm, keyHex: 'k$i'), at: _now);
      }
      final PlaceConfirmationSummary summary = tally.summaryFor(_id);
      expect(summary.confirming, 12);
      expect(summary.shown, 5);
      expect(summary.more, 7);
    });

    test('a key-bound refutation hides the pin', () {
      final PlaceConfirmationTally tally = PlaceConfirmationTally();
      tally.record(_reply(PlaceReplyKind.confirm, keyHex: 'aa'), at: _now);
      expect(tally.summaryFor(_id).hidden, isFalse);
      tally.record(_reply(PlaceReplyKind.refute, keyHex: 'bb'), at: _now);
      expect(tally.summaryFor(_id).hidden, isTrue);
      expect(tally.summaryFor(_id).refuting, 1);
      // The row is still there: a refutation cannot delete another reporter's
      // place, only hide it on this device.
      expect(tally.summaryFor(_id).confirming, 1);
    });

    test('a claimed refutation only adds weight', () {
      final PlaceConfirmationTally tally = PlaceConfirmationTally();
      tally.record(_reply(PlaceReplyKind.refute, callsign: 'W2'), at: _now);
      final PlaceConfirmationSummary summary = tally.summaryFor(_id);
      expect(summary.hidden, isFalse);
      expect(summary.claimedRefuting, 1);
    });

    test('a blocked key neither counts nor appears', () {
      final PlaceConfirmationTally tally = PlaceConfirmationTally();
      bool isBlocked(String key) => key == 'bad';
      expect(
          tally.record(_reply(PlaceReplyKind.confirm, keyHex: 'bad'),
              at: _now, isBlocked: isBlocked),
          isFalse);
      expect(tally.summaryFor(_id).confirming, 0);
    });

    test('a change of mind replaces the vote instead of adding one', () {
      final PlaceConfirmationTally tally = PlaceConfirmationTally();
      tally.record(_reply(PlaceReplyKind.confirm, keyHex: 'aa'), at: _now);
      tally.record(_reply(PlaceReplyKind.refute, keyHex: 'aa'), at: _now);
      final PlaceConfirmationSummary summary = tally.summaryFor(_id);
      expect(summary.confirming, 0);
      expect(summary.refuting, 1);
    });

    test('forgetting a place drops its votes', () {
      final PlaceConfirmationTally tally = PlaceConfirmationTally();
      tally.record(_reply(PlaceReplyKind.confirm, keyHex: 'aa'), at: _now);
      tally.forget(_id);
      expect(tally.summaryFor(_id).totalConfirming, 0);
    });
  });
}
