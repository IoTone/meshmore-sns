// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_id.dart';
import 'package:meshmore_sns_app/places/place_store.dart';

Place _place({
  String id = 'abcd1234',
  PlaceType type = PlaceType.water,
  String label = 'Water at the ford',
  String reporter = 'Ana',
  int latE6 = 51500741,
  int lonE6 = -124596,
  int decimals = 6,
  PlaceTtl ttl = PlaceTtl.d2,
  required DateTime at,
  String? key,
}) =>
    Place(
      id: id,
      reporterKey: key == null ? null : _bytes(key),
      reporterName: reporter,
      type: type,
      typeToken: type.token,
      label: label,
      latE6: latE6,
      lonE6: lonE6,
      decimals: decimals,
      provenance: PlaceProvenance.received,
      ttl: ttl,
      sentAt: at,
      expiresAt: at.add(ttl.life),
      lastSeen: at,
    );

Uint8List _bytes(String hex) => Uint8List.fromList(<int>[
      for (int i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

void main() {
  late DateTime now;
  late PlaceStore store;
  late Directory dir;

  setUp(() {
    now = DateTime(2026, 11, 5, 12);
    // Places are sealed now, so a persistence test needs the store's own seams
    // rather than a preferences mock: the same arrangement `ChatStore`'s tests
    // use.
    dir = Directory.systemTemp.createTempSync('mm_places');
    PlaceStore.cipherOverride = MemoryRecordCipher.random();
    PlaceStore.directoryOverride = dir;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = PlaceStore(clock: () => now);
  });

  tearDown(() async {
    // The write is queued, not awaited: a test that deletes its temporary
    // directory has to wait for it or the store writes into a removed path.
    await store.flush();
    store.dispose();
    PlaceStore.cipherOverride = null;
    PlaceStore.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('renewal and expiry (spec §6, §15.6, §15.9)', () {
    test('a renewal moves the row forward and makes no second pin', () {
      expect(store.upsert(_place(at: now)), PlaceUpsert.added);
      expect(store.live(), hasLength(1));

      final DateTime later = now.add(const Duration(hours: 1));
      expect(store.upsert(_place(at: later, ttl: PlaceTtl.h24)),
          PlaceUpsert.renewed);
      expect(store.live(), hasLength(1));
      expect(store.all.single.lastSeen, later);
      expect(store.all.single.ttl, PlaceTtl.h24);
    });

    test('an older report of the same id does not rewind the row', () {
      store.upsert(_place(at: now));
      store.upsert(_place(at: now.subtract(const Duration(minutes: 5))));
      expect(store.all.single.lastSeen, now);
    });

    test('at expiry the pin leaves the layer and keeps its history row', () {
      store.upsert(_place(at: now, ttl: PlaceTtl.m15));
      final DateTime after = now.add(const Duration(minutes: 15));
      expect(store.live(after), isEmpty);
      expect(store.history(), hasLength(1));
      expect(store.filtered(liveOnly: true, now: after), isEmpty);
      expect(store.filtered(liveOnly: false), hasLength(1));
    });
  });

  group('id collision (spec §5)', () {
    test('the same id at a different point is kept as a second place', () {
      store.upsert(_place(at: now));
      final PlaceUpsert result = store.upsert(_place(at: now, lonE6: 9000000));
      expect(result, PlaceUpsert.collided);
      expect(store.live(), hasLength(2));
    });

    test('the same id inside the coarser precision is the same place', () {
      store.upsert(_place(at: now));
      store.upsert(_place(at: now, decimals: 3, latE6: 51501000));
      expect(store.live(), hasLength(1));
    });
  });

  group('blocking (spec §15.10)', () {
    test('a blocked reporter is absent and its stored rows are deleted', () {
      const String key = 'aabbccddeeff0011';
      store.upsert(_place(at: now, id: 'aaaa0001', key: key));
      store.upsert(_place(at: now, id: 'bbbb0002'));
      expect(store.filtered(liveOnly: true), hasLength(2));

      store.deleteByReporterKey(key);
      expect(store.all.map((Place p) => p.id), <String>['bbbb0002']);

      store
        ..setBlockFilter((String k) => k == key)
        ..upsert(_place(at: now, id: 'aaaa0001', key: key));
      expect(store.all.map((Place p) => p.id), <String>['bbbb0002'],
          reason: 'a blocked key cannot re-add a row');
    });
  });

  group('confirmations (spec §11)', () {
    test('one count per identity, and a key-bound refutation hides the pin',
        () {
      store.upsert(_place(at: now));
      expect(store.ingestReply('[CONFIRM:abcd1234] Ana'), isTrue);
      expect(store.ingestReply('[CONFIRM:abcd1234] Ana'), isFalse,
          reason: 'a repeat is the same voice, not a second one');
      expect(store.confirmationsFor('abcd1234').claimedConfirming, 1);

      expect(
          store.ingestReply('[REFUTE:abcd1234] Ana',
              reporterKeyHex: 'aa11bb22'),
          isTrue);
      expect(store.confirmationsFor('abcd1234').hidden, isTrue);
    });

    test('a blocked key counts for nothing', () {
      store.upsert(_place(at: now));
      store.setBlockFilter((String k) => k == 'deadbeef');
      expect(store.ingestReply('[CONFIRM:abcd1234] Z', reporterKeyHex: 'deadbeef'),
          isFalse);
      expect(store.confirmationsFor('abcd1234').totalConfirming, 0);
    });

    test('votes survive a restart and still count once per identity', () async {
      store.upsert(_place(at: now));
      store.ingestReply('[CONFIRM:abcd1234] Ana');
      await store.settled;

      final PlaceStore reopened = PlaceStore(clock: () => now);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.confirmationsFor('abcd1234').claimedConfirming, 1);
      expect(reopened.ingestReply('[CONFIRM:abcd1234] Ana'), isFalse);
    });
  });

  group('filters, search and the ledger (spec §10)', () {
    setUp(() {
      store.upsert(_place(at: now, id: 'aaaa0001', reporter: 'Ana'));
      store.upsert(_place(
          at: now,
          id: 'bbbb0002',
          label: 'Bridge out',
          type: PlaceType.hazard,
          reporter: 'Bo',
          latE6: 51600000,
          lonE6: -124000));
    });

    test('filters by type, by search and by keyed-only', () {
      expect(store.filtered(liveOnly: true), hasLength(2));
      expect(
          store
              .filtered(liveOnly: true, types: <PlaceType>{PlaceType.hazard})
              .single
              .reporterName,
          'Bo');
      expect(store.filtered(liveOnly: true, query: 'ford').single.id,
          'aaaa0001');
      expect(store.filtered(liveOnly: true, query: 'ana').single.id, 'aaaa0001');
      expect(store.filtered(liveOnly: true, keyedOnly: true), isEmpty,
          reason: 'an unkeyed place never matches keyed-only');
    });

    test('"expires within" means still live and running out inside it', () {
      // A short-lived report beside the two long ones: only it is inside an
      // hour, and an expired row is never inside any window.
      store.upsert(_place(
          at: now, id: 'cccc0003', label: 'Now', ttl: PlaceTtl.m15));
      expect(
          store
              .filtered(
                  liveOnly: true, expiresWithin: const Duration(hours: 1))
              .map((Place p) => p.id),
          <String>['cccc0003']);
      // Two hours on, the short report has expired and the two long ones are
      // still live but outside the window.
      now = now.add(const Duration(hours: 2));
      expect(
          store.filtered(
              liveOnly: false, expiresWithin: const Duration(hours: 1)),
          isEmpty,
          reason: 'an expired row has nothing left to expire');
      now = now.subtract(const Duration(hours: 2));
      expect(
          store.filtered(
              liveOnly: true, expiresWithin: const Duration(days: 7)),
          hasLength(3));
    });

  });

  group('persistence', () {
    test('rows and the seen mark survive a restart', () async {
      store.upsert(_place(at: now));
      store.markSeen('abcd1234');
      await store.settled;

      final PlaceStore reopened = PlaceStore(clock: () => now);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.all.single.label, 'Water at the ford');
      expect(reopened.isSeen('abcd1234'), isTrue);
    });

    test('a corrupt document starts clean instead of throwing', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'mm.places.v1': '{not json'});
      final PlaceStore reopened = PlaceStore(clock: () => now);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.all, isEmpty);
      expect(reopened.loaded, isTrue);
    });

    test('the store is bounded, expired rows leaving first', () {
      for (int i = 0; i < PlaceStore.capacity + 20; i++) {
        store.upsert(_place(
          id: i.toString().padLeft(8, '0'),
          at: now.subtract(Duration(hours: i)),
          ttl: i.isEven ? PlaceTtl.m15 : PlaceTtl.d7,
        ));
      }
      expect(store.all.length, PlaceStore.capacity);
      final DateTime at = now;
      expect(store.live(at).length, greaterThan(0),
          reason: 'the newest live rows are the ones kept');
    });
  });

  group('chat ingestion', () {
    test('a channel line becomes one unkeyed place', () {
      final ChatMessage m = ChatMessage(
        channelIdx: 0,
        text:
            'Ana: [PLACE]51.500741,-0.124596 Water at the ford [water] [TTL:2d]',
        outgoing: false,
        at: now,
      );
      final Place? place = store.ingestMessage(m);
      expect(place, isNotNull);
      expect(place!.isUnkeyed, isTrue);
      expect(place.reporterName, 'Ana');
      expect(store.live(), hasLength(1));
      store.ingestMessage(m);
      expect(store.live(), hasLength(1), reason: 'a duplicate is not a pin');
    });

    test('ordinary text is not a place', () {
      final ChatMessage m = ChatMessage(
        channelIdx: 0,
        text: 'Ana: anyone at the ford?',
        outgoing: false,
        at: now,
      );
      expect(store.ingestMessage(m), isNull);
      expect(store.all, isEmpty);
    });

    test('the id is derived from the digits that travelled', () {
      final ChatMessage m = ChatMessage(
        channelIdx: 0,
        text: 'Ana: [PLACE]51.500741,-0.124596 Ford [water] [TTL:2d]',
        outgoing: false,
        at: now,
      );
      final Place place = store.ingestMessage(m)!;
      expect(place.id, placeIdOf(place));
    });
  });
}
