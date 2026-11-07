// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/meshcore/contact_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/meshcore/secure/sealed_document.dart';

Contact _contact({
  int seed = 1,
  String name = 'HELTEC-BASE',
  int outPathLen = 0,
  int lastMod = 42,
}) {
  final Uint8List key = Uint8List(kPubKeySize);
  final Uint8List path = Uint8List(64);
  for (int i = 0; i < kPubKeySize; i++) {
    key[i] = (seed * 7 + i) & 0xFF;
  }
  for (int i = 0; i < 3; i++) {
    path[i] = 0xA0 + i;
  }
  return Contact(
    publicKey: key,
    type: kAdvTypeRepeater,
    flags: 0x05,
    outPathLen: outPathLen,
    outPath: path,
    name: name,
    lastAdvertTimestamp: 1700000000 + seed,
    latitudeMicros: 38925000 + seed,
    longitudeMicros: -104772826,
    lastMod: lastMod,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // The table is sealed, like the chat history and the trail: this needs the
    // store's own seams, not a preferences mock.
    dir = Directory.systemTemp.createTempSync('mm_contact_store');
    SealedDocument.cipherOverride = MemoryRecordCipher.random();
    SealedDocument.directoryOverride = dir;
  });

  tearDown(() {
    SealedDocument.cipherOverride = null;
    SealedDocument.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a contact survives a save and a load, field for field', () async {
    final Contact before = _contact(seed: 3, outPathLen: 0x41);
    await ContactStore.save(<Contact>[before]);
    final List<Contact> rows = await ContactStore.load();
    expect(rows.length, 1);
    final Contact after = rows.single;
    expect(after.publicKey, before.publicKey);
    expect(after.type, before.type);
    expect(after.flags, before.flags);
    expect(after.outPathLen, before.outPathLen);
    expect(after.outPath, before.outPath);
    expect(after.name, before.name);
    expect(after.lastAdvertTimestamp, before.lastAdvertTimestamp);
    expect(after.latitudeMicros, before.latitudeMicros);
    expect(after.longitudeMicros, before.longitudeMicros);
    expect(after.lastMod, before.lastMod);
  });

  test('a byte-exact round trip keeps the path a send would use', () {
    // The raw record is re-sent as ADD_UPDATE_CONTACT, so the path bytes and
    // the packed length have to come back exactly as the radio stated them.
    final Contact c = _contact(seed: 5, outPathLen: 0x41);
    final List<Contact> rows = ContactStore.decode(ContactStore.encode(<Contact>[c]));
    expect(rows.single.outPathLen, 0x41);
    expect(rows.single.outPath, c.outPath);
    expect(rows.single.directPath, c.directPath);
  });

  test('a row that cannot be read is dropped, not guessed at', () {
    expect(ContactStore.decode('not json'), isEmpty);
    expect(ContactStore.decode('{"k":"x"}'), isEmpty);
    expect(ContactStore.decode(null), isEmpty);
    // A short key is not a contact: the radio addresses 32 bytes.
    expect(
      ContactStore.decode(
          '[{"k":"aabb","ty":2,"fl":0,"pl":0,"p":"","n":"x","adv":1,"la":0,"lo":0,"lm":1}]'),
      isEmpty,
    );
    // Odd-length hex, a non-numeric field, and an impossible latitude.
    expect(ContactStore.decode('[{"k":"abc","ty":2,"fl":0,"pl":0,"p":"","n":"x",'
            '"adv":1,"la":0,"lo":0,"lm":1}]'),
        isEmpty);
    expect(ContactStore.decode('[{"k":"${'00' * 32}","ty":"2","fl":0,"pl":0,'
            '"p":"","n":"x","adv":1,"la":0,"lo":0,"lm":1}]'),
        isEmpty);
    expect(ContactStore.decode('[{"k":"${'00' * 32}","ty":2,"fl":0,"pl":0,'
            '"p":"","n":"x","adv":1,"la":90000001,"lo":0,"lm":1}]'),
        isEmpty);
  });

  test('the table is capped, so a corrupt document cannot grow without bound',
      () {
    final String row = ContactStore.encode(<Contact>[_contact()])
        .replaceFirst('[', '')
        .replaceFirst(']', '');
    final String doc =
        '[${List<String>.filled(ContactStore.capacity + 25, row).join(',')}]';
    expect(ContactStore.decode(doc).length, ContactStore.capacity);
  });

  test('clearing removes the table', () async {
    await ContactStore.save(<Contact>[_contact()]);
    expect(await ContactStore.load(), isNotEmpty);
    await ContactStore.clear();
    expect(await ContactStore.load(), isEmpty);
  });

  test('a store that cannot seal says so and keeps the session data', () async {
    SealedDocument.cipherOverride = null;
    SealedDocument.directoryOverride = Directory.systemTemp.createTempSync(
        'mm_contact_store_nokey');
    addTearDown(() {
      final Directory d = SealedDocument.directoryOverride!;
      if (d.existsSync()) d.deleteSync(recursive: true);
    });
    await ContactStore.save(<Contact>[_contact()]);
    expect(ContactStore.sealedUnreadable.value, isTrue,
        reason: 'a write that did not land is reported, not swallowed');
    expect(ContactStore.decode(ContactStore.encode(<Contact>[_contact()])),
        isNotEmpty,
        reason: 'the in-memory path is unaffected by a failed seal');
  });
}
