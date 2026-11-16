// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/chat_store.dart';
import 'package:meshmore_sns_app/meshcore/history_export.dart';
import 'package:meshmore_sns_app/meshcore/secure/store_export.dart';

/// B4/B5 — an export is only worth writing if it can come back, and the key
/// stretching must not run on the frame thread.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String passphrase = 'correct horse battery staple';
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mm_history_import');
    ChatStore.directoryOverride = dir;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ChatStore.resetStatus();
  });

  tearDown(() {
    ChatStore.directoryOverride = null;
    ChatStore.resetStatus();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<ChatMessage> rows() => <ChatMessage>[
        ChatMessage(
            channelIdx: 0,
            text: 'first',
            outgoing: true,
            at: DateTime.utc(2026, 11, 1, 10)),
        ChatMessage(
            channelIdx: 0,
            text: 'second',
            outgoing: false,
            at: DateTime.utc(2026, 11, 1, 11)),
      ];

  test('an exported thread decodes back into the same rows', () async {
    final Uint8List bytes = await HistoryExport.encodeThreadAsync(
      key: HistoryExport.channelKey(0),
      messages: rows(),
      passphrase: passphrase,
      iterations: 1000, // the floor the format accepts; keeps the test quick
    );
    final List<ChatMessage> back = await HistoryExport.decodeFileAsync(
      bytes: bytes,
      passphrase: passphrase,
    );
    expect(back.map((ChatMessage m) => m.text), <String>['first', 'second']);
    expect(back.every((ChatMessage m) => m.channelIdx == 0), isTrue);
  });

  test('a wrong passphrase is a named refusal, not a crash', () async {
    final Uint8List bytes = await HistoryExport.encodeThreadAsync(
      key: HistoryExport.channelKey(0),
      messages: rows(),
      passphrase: passphrase,
      iterations: 1000,
    );
    await expectLater(
      HistoryExport.decodeFileAsync(bytes: bytes, passphrase: 'wrong'),
      throwsA(isA<ExportRefused>()),
    );
  });

  test('the accepted iteration count is capped', () {
    // A crafted header claiming minutes of stretching is refused before the
    // KDF runs, not after.
    expect(StoreExport.maxAcceptedIterations,
        lessThanOrEqualTo(StoreExport.defaultIterations * 8));
    final Uint8List bytes = StoreExport.encode(
        <String, Uint8List>{'thread:ch:0': Uint8List.fromList(<int>[1])},
        passphrase,
        iterations: 1000);
    expect(() => StoreExport.decode(bytes, passphrase),
        returnsNormally);
  });
}
