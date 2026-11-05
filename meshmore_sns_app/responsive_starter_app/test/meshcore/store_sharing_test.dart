// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/chat/draft_store.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/encrypted_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';

/// History, drafts and the block list are three records in one file, and every
/// write is a read-modify-write of the whole map. Each store builds its own
/// instance per operation, so a lock held on the instance would serialise
/// nothing: two writers would read the same map, each set its own record, and
/// the later write would drop the earlier one's record with no error.
///
/// The store therefore locks on the file path. These tests drive two stores
/// against one directory and require both records to survive every round.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late MemoryRecordCipher cipher;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('store_chain');
    cipher = MemoryRecordCipher.random();
    DraftStore.cipherOverride = cipher;
    DraftStore.directoryOverride = dir;
    BlockStore.cipherOverride = cipher;
    BlockStore.directoryOverride = dir;
  });

  tearDown(() async {
    DraftStore.cipherOverride = null;
    DraftStore.directoryOverride = null;
    BlockStore.cipherOverride = null;
    BlockStore.directoryOverride = null;
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  String keyFor(int i) =>
      (i + 0xa0).toRadixString(16).padLeft(2, '0').padRight(64, '0');

  test('a draft and a block written together both survive', () async {
    const int rounds = 10;
    // One block store: its in-memory list is what it writes, so a fresh store
    // per round would lose earlier keys for a reason unrelated to locking.
    final BlockStore blocks = BlockStore();
    for (int i = 0; i < rounds; i++) {
      await Future.wait(<Future<void>>[
        DraftStore.save('radio|ch:$i', 'draft $i'),
        blocks.block(BlockedKey(pubKeyHex: keyFor(i), sinceMs: i)),
      ]);
    }

    final Map<String, Uint8List> all = await EncryptedStore(
      cipher: cipher,
      directory: () async => dir,
    ).readAll();

    expect(all.containsKey(DraftStore.recordName), isTrue,
        reason: 'the drafts record survived the block writes');
    expect(all.containsKey(BlockStore.recordName), isTrue,
        reason: 'the block record survived the draft writes');

    final Map<String, String> drafts = <String, String>{};
    (jsonDecode(utf8.decode(all[DraftStore.recordName]!))
            as Map<String, Object?>)
        .forEach((String k, Object? v) => drafts[k] = v! as String);
    expect(drafts.length, rounds, reason: 'no round lost its draft');

    final List<Object?> rows =
        jsonDecode(utf8.decode(all[BlockStore.recordName]!)) as List<Object?>;
    expect(rows.length, rounds, reason: 'no round lost its block');
  });

  test('two directories are two files, so neither waits on the other', () async {
    final Directory other =
        await Directory.systemTemp.createTemp('store_other');
    addTearDown(() async {
      if (other.existsSync()) await other.delete(recursive: true);
    });
    // The lock is keyed by file path, so a second directory must not queue
    // behind the first: that is what keeps one test's directory out of the
    // next test's way.
    final EncryptedStore elsewhere =
        EncryptedStore(cipher: cipher, directory: () async => other);
    final EncryptedStore here =
        EncryptedStore(cipher: cipher, directory: () async => dir);
    await Future.wait(<Future<void>>[
      elsewhere.write('probe', Uint8List.fromList(<int>[1])),
      here.write('probe', Uint8List.fromList(<int>[2])),
    ]);
    expect(await elsewhere.read('probe'), <int>[1]);
    expect(await here.read('probe'), <int>[2]);
  });
}
