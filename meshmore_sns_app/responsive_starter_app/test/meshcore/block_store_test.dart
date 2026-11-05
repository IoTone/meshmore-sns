// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/encrypted_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';

/// The store is the whole filter's authority, so the rules that matter are the
/// ones a mistake would quietly break: a key that is not 32 bytes is not an
/// identity, a full list refuses rather than evicts, and the list survives a
/// restart because it lives in the sealed file.
void main() {
  String hex(String fill) => fill * 64;

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('block_store_test');
    BlockStore.cipherOverride = MemoryRecordCipher.random();
    BlockStore.directoryOverride = dir;
  });

  tearDown(() {
    BlockStore.cipherOverride = null;
    BlockStore.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a block needs the full 32-byte key', () async {
    final BlockStore store = BlockStore();
    expect(() => store.block(const BlockedKey(pubKeyHex: 'abcd', sinceMs: 1)),
        throwsArgumentError);
    expect(() => store.block(BlockedKey(pubKeyHex: 'z' * 64, sinceMs: 1)),
        throwsArgumentError);
    expect(await store.block(BlockedKey(pubKeyHex: hex('a'), sinceMs: 1)), isTrue);
    expect(store.isBlocked(hex('a')), isTrue);
  });

  test('a radio prefix matches a blocked full key, a prefix never creates one',
      () async {
    final BlockStore store = BlockStore();
    await store.block(BlockedKey(pubKeyHex: hex('b'), sinceMs: 1));
    expect(store.isBlocked(hex('b').substring(0, 12)), isTrue,
        reason: 'a legacy DM frame carries 6 bytes of the key');
    expect(store.isBlocked('b' * 8), isFalse,
        reason: 'too short to be a prefix of anything');
  });

  test('a name pins a key only when exactly one blocked entry carries it',
      () async {
    final BlockStore store = BlockStore();
    await store.block(
        BlockedKey(pubKeyHex: hex('c'), sinceMs: 1, name: 'Mallory'));
    expect(store.isBlockedName('Mallory'), isTrue);
    expect(store.isBlockedName('mallory'), isFalse,
        reason: 'names are display strings, not normalised identities');
    await store.block(
        BlockedKey(pubKeyHex: hex('d'), sinceMs: 2, name: 'Mallory'));
    expect(store.isBlockedName('Mallory'), isFalse,
        reason: 'a shared name pins nothing');
  });

  test('a full list refuses rather than dropping the oldest silently',
      () async {
    // Seeded rather than filled: one block is one whole-file rewrite, and the
    // rule under test is the refusal, not the write.
    final BlockStore store = BlockStore(seed: <String, BlockedKey>{
      for (int i = 0; i < BlockStore.capacity; i++)
        i.toRadixString(16).padLeft(64, '0'):
            BlockedKey(pubKeyHex: i.toRadixString(16).padLeft(64, '0'), sinceMs: i),
    });
    expect(store.atCapacity, isTrue);
    final bool added = await store
        .block(BlockedKey(pubKeyHex: 'f' * 64, sinceMs: 999));
    expect(added, isFalse);
    expect(store.count, BlockStore.capacity);
  });

  test('the list survives a restart through the sealed store', () async {
    final BlockStore first = BlockStore();
    await first.block(BlockedKey(
        pubKeyHex: hex('e'), sinceMs: 7, name: 'Eve', notifySuppressed: false));

    final BlockStore second = BlockStore();
    await second.load();

    expect(second.count, 1);
    expect(second.persisted, isTrue);
    final BlockedKey row = second.all.single;
    expect(row.pubKeyHex, hex('e'));
    expect(row.name, 'Eve');
    expect(row.notifySuppressed, isFalse);
    expect(row.reason, BlockReason.user);
  });

  test('unblocking removes the row and persists the removal', () async {
    final BlockStore store = BlockStore();
    await store.block(BlockedKey(pubKeyHex: hex('f'), sinceMs: 1));
    await store.unblock(hex('f'));

    final BlockStore reopened = BlockStore();
    await reopened.load();
    expect(reopened.count, 0);
    expect(reopened.isBlocked(hex('f')), isFalse);
  });

  test('a corrupt entry is skipped, not allowed to poison the list', () async {
    final BlockStore store = BlockStore(
        seed: <String, BlockedKey>{
          hex('1'): BlockedKey(pubKeyHex: hex('1'), sinceMs: 1),
        });
    expect(BlockedKey.fromJson(<String, Object?>{'pubKeyHex': 'short'}),
        isNull);
    expect(store.count, 1);
  });

  test('a store that cannot be opened is reported unreadable, not empty', () async {
    // A file that is not this app's store: the magic does not match, which is
    // the shape a damaged or foreign file takes.
    final File file =
        File('${dir.path}${Platform.pathSeparator}${EncryptedStore.fileName}');
    file.writeAsBytesSync(<int>[0, 1, 2, 3, 4, 5, 6, 7]);

    final BlockStore store = BlockStore();
    await store.load();

    expect(store.count, 0, reason: 'nothing is blocked this session');
    expect(store.persisted, isFalse);
    expect(store.unreadable, isTrue,
        reason: 'the list existed and could not be read, which is not the '
            'same as never having been saved');

    // The damaged bytes survive the session: a later write must not be the
    // moment the evidence disappears.
    final File copy = File(
        '${dir.path}${Platform.pathSeparator}${EncryptedStore.corruptName}');
    expect(copy.existsSync(), isTrue);
    expect(copy.readAsBytesSync(), file.readAsBytesSync());

    // And a new block still saves normally, because the copy kept the damage.
    expect(await store.block(BlockedKey(pubKeyHex: hex('a'), sinceMs: 1)),
        isTrue);
    expect(store.persisted, isTrue);
  });
}
