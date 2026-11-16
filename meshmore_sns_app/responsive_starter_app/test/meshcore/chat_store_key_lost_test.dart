// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/chat_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/encrypted_store.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';

/// B1/B2 — a Keystore key that is gone is not a corrupt file and not an empty
/// history. The ciphertext stays, the app says it cannot open it here, and it
/// never starts a second history in the clear behind the sealed one.
/// A cipher whose platform key is gone: opening fails the way the Keystore
/// reports it, sealing would mint a new key.
final class _KeyLostCipher implements RecordCipher {
  @override
  Future<Uint8List> seal(Uint8List plain) async =>
      MemoryRecordCipher.random().seal(plain);

  @override
  Future<Uint8List> open(Uint8List sealed) async =>
      throw const RecordCipherKeyLost('no keystore key on this device');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String legacyKey = 'mm.chat.v1';
  const String markerKey = 'mm.chat.storeV';
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mm_chat_keylost');
    ChatStore.directoryOverride = dir;
    ChatStore.cipherOverride = MemoryRecordCipher.random();
    ChatStore.resetStatus();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    ChatStore.cipherOverride = null;
    ChatStore.directoryOverride = null;
    ChatStore.resetStatus();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<File> sealedFile() async =>
      File('${dir.path}${Platform.pathSeparator}${EncryptedStore.fileName}');

  test('a lost key reports unreadable history and keeps the ciphertext',
      () async {
    await ChatStore.save(<ChatMessage>[
      ChatMessage(channelIdx: 0, text: 'before', outgoing: true),
    ]);
    final File file = await sealedFile();
    expect(file.existsSync(), isTrue);
    final Uint8List before = file.readAsBytesSync();

    // The key is gone: same file, different cipher.
    ChatStore.cipherOverride = _KeyLostCipher();
    final List<ChatMessage> loaded = await ChatStore.load();

    expect(loaded, isEmpty);
    expect(ChatStore.unreadable.value, isTrue);
    expect(file.readAsBytesSync(), before,
        reason: 'the sealed file is evidence, not garbage');
  });

  test('a lost key never forks the history into plaintext', () async {
    await ChatStore.save(<ChatMessage>[
      ChatMessage(channelIdx: 0, text: 'before', outgoing: true),
    ]);
    ChatStore.cipherOverride = _KeyLostCipher();

    await ChatStore.save(<ChatMessage>[
      ChatMessage(channelIdx: 0, text: 'after', outgoing: true),
    ]);

    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(p.getString(legacyKey), isNull,
        reason: 'a sealed install must not grow a plaintext twin');
    expect(p.getInt(markerKey), ChatStore.formatVersion,
        reason: 'the marker still says the sealed store is the truth');
    expect(ChatStore.lastWriteFailure.value, 'keyLost');
  });

  test('a good read clears the unreadable flag', () async {
    ChatStore.unreadable.value = true;
    await ChatStore.save(<ChatMessage>[
      ChatMessage(channelIdx: 0, text: 'back', outgoing: false),
    ]);
    final List<ChatMessage> loaded = await ChatStore.load();
    expect(loaded.single.text, 'back');
    expect(ChatStore.unreadable.value, isFalse);
  });

  test('a plaintext-only install still writes plaintext', () async {
    // No keystore at all, and no marker: the old path is the truth here.
    ChatStore.cipherOverride = _KeyLostCipher();
    SharedPreferences.setMockInitialValues(<String, Object>{
      legacyKey: jsonEncode(<Map<String, Object?>>[
        ChatMessage(channelIdx: 0, text: 'old', outgoing: false).toJson(),
      ]),
    });
    await ChatStore.save(<ChatMessage>[
      ChatMessage(channelIdx: 0, text: 'new', outgoing: true),
    ]);
    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(p.getString(legacyKey), contains('new'));
  });
}
