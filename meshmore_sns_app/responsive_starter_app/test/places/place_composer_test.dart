// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_codec.dart';
import 'package:meshmore_sns_app/places/place_confirmation.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_sender.dart';
import 'package:meshmore_sns_app/places/place_store.dart';

final class _FakeSender implements PlaceSender {
  String name = 'Ana';
  Uint8List? key;

  final List<String> sent = <String>[];

  @override
  String get reporterName => name;

  @override
  Uint8List? get reporterKey => key;

  @override
  Future<void> sendPlaceText(String text) async => sent.add(text);
}

void main() {
  late DateTime now;
  late PlaceStore store;
  late PlaceReportBudget budget;
  late _FakeSender sender;
  late PlaceComposer composer;

  setUp(() {
    now = DateTime(2026, 11, 5, 12);
    store = PlaceStore(clock: () => now);
    budget = PlaceReportBudget(clock: () => now);
    sender = _FakeSender();
    composer = PlaceComposer(
      store: store,
      budget: budget,
      sender: sender,
      clock: () => now,
    );
  });

  tearDown(() => store.dispose());

  group('the report that goes out', () {
    test('is the text form, with the type and the life the composer chose',
        () async {
      final PlaceComposeResult r = await composer.compose(
        latitude: 51.500741,
        longitude: -0.124596,
        label: 'Water at the ford',
        type: PlaceType.water,
        ttl: PlaceTtl.d2,
      );
      expect(r.sent, isTrue);
      expect(sender.sent.single,
          '[PLACE]51.500741,-0.124596 Water at the ford [water] [TTL:2d]');
      final PlaceParseOutcome parsed = parsePlace(
        sender.sent.single,
        receivedAt: now,
        reporterName: 'Ana',
      );
      expect(parsed.place!.label, 'Water at the ford');
      expect(parsed.place!.type, PlaceType.water);
    });

    test('is stored as our own row, seen, and keyed when the radio has a key',
        () async {
      sender.key = Uint8List.fromList(List<int>.filled(32, 7));
      final PlaceComposeResult r = await composer.compose(
        latitude: 51.5,
        longitude: -0.12,
        label: 'Ford',
        type: PlaceType.water,
        ttl: PlaceTtl.h1,
      );
      expect(store.live().single.id, r.place!.id);
      expect(store.isSeen(r.place!.id), isTrue);
      expect(r.place!.isUnkeyed, isFalse);
    });

    test('snaps before it hashes, so the id matches the digits sent', () async {
      final PlaceComposeResult r = await composer.compose(
        latitude: 51.5007412,
        longitude: -0.1245963,
        label: 'Ford',
        type: PlaceType.water,
        ttl: PlaceTtl.h1,
        precision: PlacePrecision.snapped100m,
      );
      expect(r.place!.decimals, 3);
      expect(sender.sent.single, startsWith('[PLACE]51.501,-0.125 '));
      // A receiver that parses the same bytes computes the same id.
      final Place reparsed = parsePlace(
        sender.sent.single,
        receivedAt: now,
        reporterName: 'Ana',
      ).place!;
      expect(reparsed.latE6, r.place!.latE6);
      expect(reparsed.lonE6, r.place!.lonE6);
    });
  });

  group('refusals are explained, never silent', () {
    test('an empty label', () async {
      final PlaceComposeResult r = await composer.compose(
        latitude: 51.5,
        longitude: -0.12,
        label: '   ',
        type: PlaceType.water,
        ttl: PlaceTtl.h1,
      );
      expect(r.refusal, PlaceComposeRefusal.label);
      expect(r.labelProblem, PlaceLabelProblem.empty);
      expect(sender.sent, isEmpty);
    });

    test('a label carrying a TTL token', () async {
      final PlaceComposeResult r = await composer.compose(
        latitude: 51.5,
        longitude: -0.12,
        label: 'Ford [TTL:2d]',
        type: PlaceType.water,
        ttl: PlaceTtl.h1,
      );
      expect(r.labelProblem, PlaceLabelProblem.carriesTtl);
      expect(sender.sent, isEmpty);
    });

    test('no radio identity at all', () async {
      sender.name = '';
      sender.key = null;
      final PlaceComposeResult r = await composer.compose(
        latitude: 51.5,
        longitude: -0.12,
        label: 'Ford',
        type: PlaceType.water,
        ttl: PlaceTtl.h1,
      );
      expect(r.refusal, PlaceComposeRefusal.identity);
      expect(sender.sent, isEmpty);
    });

    test('the burst budget, with the time the next one may go', () async {
      Future<PlaceComposeResult> send() => composer.compose(
            latitude: 51.5,
            longitude: -0.12,
            label: 'Ford',
            type: PlaceType.water,
            ttl: PlaceTtl.h1,
          );
      expect((await send()).sent, isTrue);
      now = now.add(const Duration(minutes: 1));
      expect((await send()).sent, isTrue);
      now = now.add(const Duration(minutes: 1));
      final PlaceComposeResult third = await send();
      expect(third.refusal, PlaceComposeRefusal.budget);
      expect(third.allowedAt,
          DateTime(2026, 11, 5, 12).add(PlaceReportBudget.burstWindow));
      expect(sender.sent, hasLength(2), reason: 'the third never left');
    });

    test('coordinates outside the globe', () async {
      final PlaceComposeResult r = await composer.compose(
        latitude: 91,
        longitude: 0,
        label: 'Nowhere',
        type: PlaceType.look,
        ttl: PlaceTtl.h1,
      );
      expect(r.refusal, PlaceComposeRefusal.coordinates);
      expect(sender.sent, isEmpty);
    });
  });

  group('replies', () {
    test('a confirmation shares the place budget and carries the id', () async {
      final PlaceComposeResult r = await composer.compose(
        latitude: 51.5,
        longitude: -0.12,
        label: 'Ford',
        type: PlaceType.water,
        ttl: PlaceTtl.h1,
      );
      final PlaceReplySendResult reply =
          await composer.reply(r.place!, kind: PlaceReplyKind.confirm);
      expect(reply.sent, isTrue);
      expect(sender.sent.last, '[CONFIRM:${r.place!.id}] Ana');
      // The budget now holds both, so a third inside five minutes is refused.
      now = now.add(const Duration(minutes: 1));
      final PlaceReplySendResult third =
          await composer.reply(r.place!, kind: PlaceReplyKind.refute);
      expect(third.sent, isFalse);
      expect(third.allowedAt, isNotNull);
    });
  });

  group('a reply addressed to the sender', () {
    Future<Place> report({Uint8List? key}) async {
      sender.key = key;
      final PlaceComposeResult r = await composer.compose(
        latitude: 51.5,
        longitude: -0.12,
        label: 'Ford',
        type: PlaceType.water,
        ttl: PlaceTtl.h1,
      );
      // Only the reply matters from here: the report itself went to the
      // channel by design.
      sender.sent.clear();
      return r.place!;
    }

    test('goes out as a direct message, and says it binds', () async {
      final Uint8List key = Uint8List.fromList(List<int>.filled(32, 3));
      final Place place = await report(key: key);

      Uint8List? toKey;
      String? sentText;
      final PlaceReplySendResult? r = await composer.replyKeyed(place,
          kind: PlaceReplyKind.confirm,
          callsign: 'Ana',
          sendDirect: (Uint8List k, String text) async {
        toKey = k;
        sentText = text;
        return true;
      });
      expect(r!.sent, isTrue);
      expect(toKey, key, reason: 'addressed to the reporter, not the channel');
      // The grammar is the same; the attribution is what changed.
      expect(sentText, startsWith('[CONFIRM:${place.id}]'));
      // The `reporterKeyHex` argument is what decides the attribution: a
      // direct message names a key, a channel message only a name.
      final PlaceReplyOutcome parsed = parsePlaceReply(sentText!,
          reporterKeyHex: '03' * 32);
      expect(parsed.reply!.attribution, PlaceReplyAttribution.keyBound);
      expect(sender.sent, isEmpty, reason: 'nothing went to the channel');
    });

    test('is not offered without a key, and says so instead of guessing',
        () async {
      final Place place = await report();
      expect(place.reporterKey, isNull);
      expect(
          await composer.replyKeyed(place,
              kind: PlaceReplyKind.confirm,
              callsign: 'Ana',
              sendDirect: (Uint8List k, String t) async => true),
          isNull,
          reason: 'nobody to address, so no channel fallback');
    });

    test('shares the place budget like every other place message', () async {
      final Uint8List key = Uint8List.fromList(List<int>.filled(32, 9));
      final Place place = await report(key: key);
      await composer.replyKeyed(place,
          kind: PlaceReplyKind.confirm,
          callsign: 'Ana',
          sendDirect: (Uint8List k, String t) async => true);
      final PlaceReplySendResult? second = await composer.replyKeyed(place,
          kind: PlaceReplyKind.refute,
          callsign: 'Ana',
          sendDirect: (Uint8List k, String t) async => true);
      expect(second!.sent, isFalse);
      expect(second.allowedAt, isNotNull);
    });
  });
}
