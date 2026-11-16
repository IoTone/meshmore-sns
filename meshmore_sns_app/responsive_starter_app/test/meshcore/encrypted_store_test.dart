// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/secure/encrypted_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('mm_store'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  EncryptedStore store(RecordCipher cipher) =>
      EncryptedStore(cipher: cipher, directory: () async => dir);

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  test('a missing file reads as empty, not as an error', () async {
    expect(await store(MemoryRecordCipher.random()).readAll(), isEmpty);
  });

  test('what is written is what is read, and nothing plaintext is on disk',
      () async {
    final MemoryRecordCipher cipher = MemoryRecordCipher.random();
    await store(cipher).write('chat', bytes('hello mesh'));

    expect(utf8.decode((await store(cipher).read('chat'))!), 'hello mesh');

    final Uint8List onDisk =
        File('${dir.path}/${EncryptedStore.fileName}').readAsBytesSync();
    expect(utf8.decode(onDisk, allowMalformed: true), isNot(contains('hello')));
    expect(onDisk.sublist(0, 4), EncryptedStore.magic);
    expect(onDisk[4], EncryptedStore.formatVersion);
  });

  test('a different key cannot open the store', () async {
    await store(MemoryRecordCipher.random()).write('chat', bytes('secret'));
    expect(
      () => store(MemoryRecordCipher.random()).readAll(),
      throwsA(isA<EncryptedStoreCorrupt>()),
    );
  });

  test('a truncated file is a corrupt store, not an empty one', () async {
    final MemoryRecordCipher cipher = MemoryRecordCipher.random();
    await store(cipher).write('chat', bytes('secret'));
    final File f = File('${dir.path}/${EncryptedStore.fileName}');
    final Uint8List whole = f.readAsBytesSync();
    f.writeAsBytesSync(whole.sublist(0, whole.length - 4));
    expect(
      () => store(cipher).readAll(),
      throwsA(isA<EncryptedStoreCorrupt>()),
    );
  });

  test('a foreign file is refused rather than overwritten', () async {
    File('${dir.path}/${EncryptedStore.fileName}')
        .writeAsBytesSync(utf8.encode('not this app'));
    final EncryptedStore s = store(MemoryRecordCipher.random());
    expect(() => s.readAll(), throwsA(isA<EncryptedStoreCorrupt>()));
  });

  test('two concurrent writes keep both records', () async {
    final MemoryRecordCipher cipher = MemoryRecordCipher.random();
    final EncryptedStore s = store(cipher);
    await Future.wait(<Future<void>>[
      s.write('a', bytes('one')),
      s.write('b', bytes('two')),
    ]);
    final Map<String, Uint8List> all = await s.readAll();
    expect(all.keys.toSet(), <String>{'a', 'b'});
  });

  test('a cipher that cannot seal leaves the old file intact', () async {
    final MemoryRecordCipher cipher = MemoryRecordCipher.random();
    await store(cipher).write('chat', bytes('kept'));
    await expectLater(
      store(const _NoCipher()).write('chat', bytes('lost')),
      throwsA(isA<EncryptedStoreUnavailable>()),
    );
    expect(utf8.decode((await store(cipher).read('chat'))!), 'kept');
  });

  test('remove drops one record and clear drops the file', () async {
    final MemoryRecordCipher cipher = MemoryRecordCipher.random();
    final EncryptedStore s = store(cipher);
    await s.write('a', bytes('one'));
    await s.write('b', bytes('two'));
    await s.remove('a');
    expect((await s.readAll()).keys.toList(), <String>['b']);
    await s.clear();
    expect(File('${dir.path}/${EncryptedStore.fileName}').existsSync(), isFalse);
  });
}

/// A host with no keystore: every seal attempt fails.
class _NoCipher implements RecordCipher {
  const _NoCipher();
  @override
  Future<Uint8List> seal(Uint8List plain) async =>
      throw const RecordCipherUnavailable('no key');
  @override
  Future<Uint8List> open(Uint8List sealed) async =>
      throw const RecordCipherUnavailable('no key');
}
