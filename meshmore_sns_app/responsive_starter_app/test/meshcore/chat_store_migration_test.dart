// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/chat_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/encrypted_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// APP-E1/N5 — history is sealed with a device key, and the plaintext that
/// shipped before it moves once and is removed only after the sealed copy has
/// been read back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String legacyKey = 'mm.chat.v1';
  late Directory dir;
  late MemoryRecordCipher cipher;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mm_chat');
    cipher = MemoryRecordCipher.random();
    ChatStore.cipherOverride = cipher;
    ChatStore.directoryOverride = dir;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    ChatStore.cipherOverride = null;
    ChatStore.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String encode(List<ChatMessage> messages) =>
      jsonEncode(messages.map((ChatMessage m) => m.toJson()).toList());

  List<ChatMessage> seed(int n) => <ChatMessage>[
        for (int i = 0; i < n; i++)
          ChatMessage(
            channelIdx: 0,
            text: 'line $i',
            outgoing: i.isEven,
            at: DateTime.utc(2026, 11, 5, 12, i),
          ),
      ];

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  test('a plaintext history moves into the sealed store and is deleted',
      () async {
    final List<ChatMessage> messages = seed(3);
    SharedPreferences.setMockInitialValues(<String, Object>{
      legacyKey: encode(messages),
    });

    final List<ChatMessage> loaded = await ChatStore.load();
    expect(loaded.map((ChatMessage m) => m.text), <String>['line 0', 'line 1', 'line 2']);

    final SharedPreferences p = await prefs();
    expect(p.getString(legacyKey), isNull,
        reason: 'the plaintext is removed only after the sealed copy verified');
    expect(p.getInt('mm.chat.storeV'), ChatStore.formatVersion);
    expect(
        File('${dir.path}/${EncryptedStore.fileName}').readAsBytesSync(),
        isNotEmpty);
  });

  test('the sealed file is not readable as text, and holds the history',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      legacyKey: encode(seed(2)),
    });
    await ChatStore.load();
    final Uint8List onDisk =
        File('${dir.path}/${EncryptedStore.fileName}').readAsBytesSync();
    expect(utf8.decode(onDisk, allowMalformed: true), isNot(contains('line 0')));

    // A second launch reads it back without the plaintext being present.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mm.chat.storeV': ChatStore.formatVersion,
    });
    final List<ChatMessage> again = await ChatStore.load();
    expect(again.map((ChatMessage m) => m.text), <String>['line 0', 'line 1']);
  });

  test('a second migration is a no-op', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      legacyKey: encode(seed(2)),
    });
    await ChatStore.migrate();
    final String sealedBefore =
        base64Encode(File('${dir.path}/${EncryptedStore.fileName}').readAsBytesSync());
    expect(await ChatStore.migrate(), isTrue);
    final String sealedAfter =
        base64Encode(File('${dir.path}/${EncryptedStore.fileName}').readAsBytesSync());
    expect(sealedAfter, sealedBefore);
  });

  test('a store that cannot seal leaves the plaintext in place and usable',
      () async {
    final List<ChatMessage> messages = seed(2);
    SharedPreferences.setMockInitialValues(<String, Object>{
      legacyKey: encode(messages),
    });
    ChatStore.cipherOverride = const _NoCipher();

    expect(await ChatStore.migrate(), isFalse);
    final SharedPreferences p = await prefs();
    expect(p.getString(legacyKey), isNotNull,
        reason: 'history is not thrown away when the key is unavailable');
    expect(p.getInt('mm.chat.storeV'), isNull);
    // ...and the app keeps working on the old path.
    expect((await ChatStore.load()).length, 2);
    await ChatStore.save(seed(4));
    expect((await ChatStore.load()).length, 4);
  });

  test('a sealed file that opens as garbage leaves the plaintext alone',
      () async {
    // Wrong key: the sealed copy exists but cannot be read back, so the
    // migration must refuse to delete the plaintext.
    final List<ChatMessage> messages = seed(2);
    SharedPreferences.setMockInitialValues(<String, Object>{
      legacyKey: encode(messages),
    });
    ChatStore.cipherOverride = MemoryRecordCipher.random();
    await ChatStore.migrate(); // sealed with key A, plaintext removed
    SharedPreferences.setMockInitialValues(<String, Object>{
      legacyKey: encode(messages),
    });
    ChatStore.cipherOverride = MemoryRecordCipher.random(); // key B

    expect(await ChatStore.migrate(), isFalse);
    expect((await prefs()).getString(legacyKey), isNotNull);
  });

  test('save caps to the newest messages and clear empties both', () async {
    await ChatStore.save(seed(ChatStore.cap + 5));
    expect((await ChatStore.load()).length, ChatStore.cap);
    await ChatStore.clear();
    expect(await ChatStore.load(), isEmpty);
  });
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
