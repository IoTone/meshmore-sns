// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/sos/sos_message.dart';

void main() {
  group('the request id', () {
    test('is six lowercase hex from nonce and key', () {
      final String id = sosIdFor(
        nonce: List<int>.filled(16, 7),
        pubkey: List<int>.generate(32, (int i) => i),
      );
      expect(id, hasLength(6));
      expect(RegExp(r'^[0-9a-f]{6}$').hasMatch(id), isTrue);
    });

    test('is stable for one nonce and different for the next', () {
      final List<int> key = List<int>.generate(32, (int i) => i);
      final String a = sosIdFor(nonce: List<int>.filled(16, 1), pubkey: key);
      final String b = sosIdFor(nonce: List<int>.filled(16, 1), pubkey: key);
      final String c = sosIdFor(nonce: List<int>.filled(16, 2), pubkey: key);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('refuses a nonce that is not sixteen bytes', () {
      expect(
        () => sosIdFor(nonce: const <int>[1, 2, 3], pubkey: const <int>[9]),
        throwsArgumentError,
      );
    });
  });

  group('the position token', () {
    test('truncates at six decimals and keeps the point', () {
      expect(formatPosition(39.739200, -104.990300), '39.7392,-104.9903');
      expect(formatPosition(39.0, -104.0), '39.0,-104.0');
      // Truncated, never rounded: 39.7392999 is 39.739299, not 39.7393.
      expect(formatPosition(39.7392999, 0.0), '39.739299,0.0');
    });
  });

  group('encode and parse', () {
    final List<int> nonce = List<int>.filled(16, 3);
    final DateTime now = DateTime.utc(2026, 11, 5, 12);
    const String id = 'a1b2c3';
    const String callsign = 'W1ABC';

    test('an SOS with a fresh fix carries the position', () {
      final ({String? text, SosMessageRefusal? refusal}) r = encodeSos(
        id: id,
        callsign: callsign,
        words: 'Allergic to bees',
        fixAt: now.subtract(const Duration(minutes: 5)),
        now: now,
        lat: 39.7392,
        lon: -104.9903,
        nonce: nonce,
        index: 1,
      );
      expect(r.refusal, isNull);
      expect(r.text, startsWith('[SOS:$id] 39.7392,-104.9903 $callsign '));
      final SosMessage parsed = parseSos(r.text!)!;
      expect(parsed, isA<SosRequestMessage>());
      final SosRequestMessage sos = parsed as SosRequestMessage;
      expect(sos.id, id);
      expect(sos.callsign, callsign);
      expect(sos.lat, 39.7392);
      expect(sos.lon, -104.9903);
      expect(sos.text, contains('Allergic to bees'));
    });

    test('a fix older than an hour goes out as NOFIX, with no coordinate', () {
      final ({String? text, SosMessageRefusal? refusal}) r = encodeSos(
        id: id,
        callsign: callsign,
        words: 'trail washed out',
        fixAt: now.subtract(const Duration(hours: 2)),
        now: now,
        lat: 39.7392,
        lon: -104.9903,
        nonce: nonce,
        index: 1,
      );
      expect(r.text, contains(' NOFIX $callsign '));
      expect(r.text, isNot(contains('39.7392')));
      final SosRequestMessage parsed = parseSos(r.text!)! as SosRequestMessage;
      expect(parsed.hasFix, isFalse);
    });

    test('no fix at all is the NOFIX form, not a missing field', () {
      final ({String? text, SosMessageRefusal? refusal}) r = encodeSos(
        id: id,
        callsign: callsign,
        words: 'help',
        fixAt: null,
        now: now,
        nonce: nonce,
        index: 1,
      );
      expect(r.text, contains('NOFIX'));
      expect(parseSos(r.text!)! as SosRequestMessage, isNotNull);
    });

    test('every send of one alarm carries different bytes', () {
      String at(int i) => encodeSos(
            id: id,
            callsign: callsign,
            words: 'Allergic to bees',
            fixAt: now,
            now: now,
            lat: 39.7392,
            lon: -104.9903,
            nonce: nonce,
            index: i,
          ).text!;
      expect(at(1), isNot(at(2)));
      expect(at(2), isNot(at(3)));
    });

    test('an over-long message is refused with a count, never truncated', () {
      final ({String? text, SosMessageRefusal? refusal}) r = encodeSos(
        id: id,
        callsign: callsign,
        words: 'x' * 120,
        fixAt: now,
        now: now,
        lat: 39.7392,
        lon: -104.9903,
        nonce: nonce,
        index: 1,
      );
      expect(r.text, isNull);
      expect(r.refusal, SosMessageRefusal.tooLong);
    });

    test('the whole message fits 160 bytes including the sender prefix', () {
      // The longest legal shape: a callsign at its ceiling, worst-case
      // coordinates and the free text at its own ceiling.
      final ({String? text, SosMessageRefusal? refusal}) r = encodeSos(
        id: 'ffffff',
        callsign: 'c' * callsignBytes,
        words: 'w' * 77, // the salt tail " ~abcd" adds five bytes
        fixAt: now,
        now: now,
        lat: -89.999999,
        lon: -179.999999,
        nonce: nonce,
        index: 1,
      );
      expect(r.refusal, isNull, reason: 'this shape must be sendable');
      expect(channelTextCost(r.text!), lessThanOrEqualTo(channelTextBytes));
    });

    test('a byte past the ceiling is refused', () {
      final ({String? text, SosMessageRefusal? refusal}) r = encodeSos(
        id: 'ffffff',
        callsign: 'c' * callsignBytes,
        words: 'w' * 78,
        fixAt: now,
        now: now,
        lat: -89.999999,
        lon: -179.999999,
        nonce: nonce,
        index: 1,
      );
      expect(r.refusal, SosMessageRefusal.tooLong);
      expect(utf8.encode(r.text ?? ''), isEmpty);
    });

    test('ACK, SAFE and CHK round-trip', () {
      final String ack = encodeAck(id: id, callsign: callsign, words: 'on my way').text!;
      final SosAckMessage a = parseSos(ack)! as SosAckMessage;
      expect(a.id, id);
      expect(a.callsign, callsign);
      expect(a.text, 'on my way');

      final String safe = encodeSafe(id: id, callsign: callsign).text!;
      expect(safe, '[SAFE:$id] $callsign');
      expect(parseSos(safe)! as SosSafeMessage, isNotNull);

      final DateTime until = DateTime(2026, 11, 5, 18, 40);
      final String chk = encodeCheckin(
        id: id,
        callsign: callsign,
        until: until,
        now: now,
        fixAt: now,
        lat: 39.7392,
        lon: -104.9903,
      ).text!;
      expect(chk, contains('until 2026-11-05 18:40'));
      final CheckinMessage c = parseSos(chk)! as CheckinMessage;
      expect(c.id, id);
      expect(c.until, until);
      expect(c.callsign, callsign);
    });

    test('an ordinary chat line is not a malformed SOS', () {
      expect(parseSos('meet at the ford 18:30'), isNull);
      expect(parseSos(''), isNull);
    });

    test('a malformed tag is not read as a request', () {
      expect(parseSos('[SOS:ABC123] 39.7,-104.9 W1ABC hi'), isNull);
      expect(parseSos('[SOS:a1b2c3]'), isNull);
      expect(parseSos('[CHK:a1b2c3] 39.7,-104.9 W1ABC'), isNull);
      expect(parseSos('[CHK:a1b2c3] 39.7,-104.9 W1ABC until not-a-time'), isNull);
    });

    test('a callsign over its ceiling, or an empty one, is refused', () {
      expect(
        encodeSafe(id: id, callsign: 'c' * (callsignBytes + 1)).refusal,
        SosMessageRefusal.badCallsign,
      );
      expect(
        encodeSafe(id: id, callsign: '   ').refusal,
        SosMessageRefusal.badCallsign,
      );
    });
  });
}
