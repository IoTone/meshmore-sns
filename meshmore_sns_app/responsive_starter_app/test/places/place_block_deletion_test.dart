// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/places/place_wiring.dart';

/// Blocking a reporter deletes their stored places (`meshmore-places-spec.md`
/// §10).
///
/// The store can delete rows by key, but deleting is only a rule if something
/// calls it: the read-time filter hides a blocked reporter from every list, and
/// a hidden row that is still on disk is still in the ledger and still in the
/// export. This is the join between the two stores, so it is tested as a join.
void main() {
  final DateTime now = DateTime(2026, 11, 5, 12);

  Uint8List bytesOf(String hex) => Uint8List.fromList(<int>[
        for (int i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);

  Place place({
    required String id,
    required String label,
    String? key,
    String reporter = 'Ana',
  }) =>
      Place(
        id: id,
        reporterKey: key == null ? null : bytesOf(key),
        reporterName: reporter,
        type: PlaceType.water,
        typeToken: PlaceType.water.token,
        label: label,
        latE6: 51500741,
        lonE6: -124596,
        decimals: 6,
        provenance: PlaceProvenance.received,
        ttl: PlaceTtl.d2,
        sentAt: now,
        expiresAt: now.add(PlaceTtl.d2.life),
        lastSeen: now,
      );

  late Directory dir;
  late BlockStore blocks;
  late PlaceStore places;
  late void Function() detach;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = Directory.systemTemp.createTempSync('place_block_deletion_test');
    BlockStore.cipherOverride = MemoryRecordCipher.random();
    BlockStore.directoryOverride = dir;
    blocks = BlockStore();
    places = PlaceStore(clock: () => now, isBlocked: blocks.isBlocked);
    detach = attachPlaceBlockDeletion(blocks, places);
  });

  tearDown(() {
    detach();
    BlockStore.cipherOverride = null;
    BlockStore.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('blocking a key deletes the rows it reported and keeps the rest',
      () async {
    const String key = 'aabbccddeeff00112233445566778899'
        'aabbccddeeff00112233445566778899';
    places
      ..upsert(place(id: 'aaaa0001', label: 'Water at the ford', key: key))
      ..upsert(place(id: 'bbbb0002', label: 'Bridge out'));

    expect(places.all, hasLength(2));

    expect(await blocks.block(BlockedKey(pubKeyHex: key, sinceMs: 1)), isTrue);

    expect(places.all.map((Place p) => p.id), <String>['bbbb0002'],
        reason: 'the blocked reporter\'s row is gone from disk, not filtered');
    await places.settled;
  });

  test('a row that arrives already blocked is never stored', () async {
    const String key = 'ccdd00112233445566778899aabbccdd'
        'ccdd00112233445566778899aabbccdd';
    await blocks.block(BlockedKey(pubKeyHex: key, sinceMs: 1));

    places.upsert(place(id: 'cccc0003', label: 'Fuel here', key: key));

    expect(places.all, isEmpty);
  });

  test('the delete is idempotent and leaves the other rows alone', () async {
    const String key = '00112233445566778899aabbccddeeff'
        '00112233445566778899aabbccddeeff';
    places
      ..upsert(place(id: 'aaaa0001', label: 'Water', key: key))
      ..upsert(place(id: 'bbbb0002', label: 'Bridge out'));

    await blocks.block(BlockedKey(pubKeyHex: key, sinceMs: 1));
    await blocks.unblock(key);
    await blocks.block(BlockedKey(pubKeyHex: key, sinceMs: 2));

    expect(places.all.map((Place p) => p.id), <String>['bbbb0002']);
  });

  test('a detached listener no longer deletes', () async {
    const String key = 'ffeeddccbbaa99887766554433221100'
        'ffeeddccbbaa99887766554433221100';
    places.upsert(place(id: 'dddd0004', label: 'Camp', key: key));
    detach();

    await blocks.block(BlockedKey(pubKeyHex: key, sinceMs: 1));

    expect(places.all.map((Place p) => p.id), <String>['dddd0004'],
        reason: 'the caller asked to stop listening, so nothing deleted');
  });
}
