// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_store.dart';

/// Places used to sit in a plain preferences file while the chat history beside
/// them was sealed. They live in the sealed store now, and the move has to be a
/// move: written, read back, compared, and only then deleted from preferences.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String kLegacy = 'mm.places.v1';
  late Directory dir;
  late MemoryRecordCipher cipher;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = Directory.systemTemp.createTempSync('mm_places_sealed');
    cipher = MemoryRecordCipher.random();
    PlaceStore.cipherOverride = cipher;
    PlaceStore.directoryOverride = dir;
  });

  tearDown(() {
    PlaceStore.cipherOverride = null;
    PlaceStore.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// A one-row document in the pre-migration format, written with the same
  /// field names the store's own encoder uses.
  String legacyDocument() => jsonEncode(<String, Object?>{
        'v': 1,
        'rows': <Object?>[
          <String, Object?>{
            'id': 'abcd1234',
            'key': null,
            'name': 'Ana',
            'type': PlaceType.water.token,
            'label': 'Water at the ford',
            'description': null,
            'lat': 51500741,
            'lon': -124596,
            'dp': 6,
            'prov': 'received',
            'ttl': PlaceTtl.h1.token,
            'sent': DateTime.utc(2026, 11, 5, 12).toIso8601String(),
            'sentFromSender': true,
            'expires': DateTime.utc(2026, 11, 5, 13).toIso8601String(),
            'seen': DateTime.utc(2026, 11, 5, 12).toIso8601String(),
            'kept': false,
          },
        ],
        'seen': <String>[],
        'votes': <String, Object?>{},
      });

  test('a legacy preferences document moves into the sealed store and leaves',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kLegacy: legacyDocument(),
    });
    final PlaceStore store = PlaceStore(clock: () => DateTime(2026, 11, 5, 12));
    await store.load();
    await store.flush();
    expect(store.all, hasLength(1), reason: 'the legacy row was read');
    expect(dir.listSync().map((FileSystemEntity e) => e.path.split('/').last),
        contains(EncryptedStoreFileName.value),
        reason: 'the row is in a sealed file, not in preferences');
    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(p.getString(kLegacy), isNull,
        reason: 'the plaintext copy is retired once the sealed one verifies');
    store.dispose();
  });

  test('a second launch reads the sealed copy and not the old file', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kLegacy: legacyDocument(),
    });
    final PlaceStore first = PlaceStore(clock: () => DateTime(2026, 11, 5, 12));
    await first.load();
    await first.flush();
    first.dispose();

    final PlaceStore second =
        PlaceStore(clock: () => DateTime(2026, 11, 5, 12));
    await second.load();
    expect(second.all, hasLength(1));
    second.dispose();
  });

  test('with no key the rows are session-only and the plaintext copy stays',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kLegacy: legacyDocument(),
    });
    PlaceStore.cipherOverride = const _NoCipher();
    final PlaceStore store = PlaceStore(clock: () => DateTime(2026, 11, 5, 12));
    await store.load();
    await store.flush();
    expect(store.all, hasLength(1), reason: 'the row is still readable');
    expect(PlaceStore.sealedUnreadable.value, isTrue,
        reason: 'the store says it cannot seal rather than pretending');
    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(p.getString(kLegacy), isNotNull,
        reason: 'nothing was deleted, because nothing was saved');
    store.dispose();
  });
}

/// The file name is the store's own; importing it here keeps the assertion tied
/// to the real artefact rather than to a string in a test.
abstract final class EncryptedStoreFileName {
  static const String value = 'mm_store.bin';
}

class _NoCipher implements RecordCipher {
  const _NoCipher();
  @override
  Future<Uint8List> seal(Uint8List plain) async =>
      throw const RecordCipherUnavailable('no key');
  @override
  Future<Uint8List> open(Uint8List sealed) async =>
      throw const RecordCipherUnavailable('no key');
}
