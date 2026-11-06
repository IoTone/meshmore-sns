// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/history_export.dart';
import 'package:meshmore_sns_app/meshcore/secure/store_export.dart';

/// APP-E3 / register §2 "History threads, export, truncation visibility":
/// a conversation leaves the phone as its own passphrase-encrypted file, and
/// only that conversation.
void main() {
  // A test-sized KDF cost: the format, not the wall clock, is the subject.
  const int iterations = 1500;

  List<ChatMessage> channelRows(int idx, int n) => <ChatMessage>[
        for (int i = 0; i < n; i++)
          ChatMessage(
            channelIdx: idx,
            text: 'channel $idx message $i',
            outgoing: i.isEven,
            at: DateTime.fromMillisecondsSinceEpoch(1700000000000 + i),
          ),
      ];

  List<ChatMessage> peerRows(String peer, int n) => <ChatMessage>[
        for (int i = 0; i < n; i++)
          ChatMessage(
            channelIdx: -1,
            peerPubKeyHex: peer,
            text: 'dm $i',
            outgoing: i.isEven,
          ),
      ];

  test('a channel thread round-trips through the passphrase', () {
    final List<ChatMessage> rows = channelRows(2, 4);
    final Uint8List file = HistoryExport.encodeThread(
      key: HistoryExport.channelKey(2),
      messages: rows,
      passphrase: 'correct horse',
      iterations: iterations,
    );

    final List<ChatMessage> back = HistoryExport.decodeThread(
      bytes: file,
      passphrase: 'correct horse',
      key: HistoryExport.channelKey(2),
    );
    expect(back, hasLength(4));
    expect(back.map((ChatMessage m) => m.text),
        rows.map((ChatMessage m) => m.text));
    expect(back.every((ChatMessage m) => m.channelIdx == 2), isTrue);
  });

  test('a DM thread round-trips under its peer key', () {
    const String peer = 'aabbccddeeff00112233';
    final Uint8List file = HistoryExport.encodeThread(
      key: HistoryExport.peerKey(peer),
      messages: peerRows(peer, 3),
      passphrase: 'pw',
      iterations: iterations,
    );
    expect(HistoryExport.peerKey(peer), 'thread:dm:aabbccddeeff');
    final List<ChatMessage> back = HistoryExport.decodeThread(
      bytes: file,
      passphrase: 'pw',
      key: HistoryExport.peerKey(peer),
    );
    expect(back, hasLength(3));
    expect(back.first.peerPubKeyHex, peer);
  });

  test('the export carries only the thread it was asked for', () {
    // One channel's rows in, nothing of another channel or a DM out.
    final List<ChatMessage> mine = channelRows(1, 2);
    final Uint8List file = HistoryExport.encodeThread(
      key: HistoryExport.channelKey(1),
      messages: mine,
      passphrase: 'pw',
      iterations: iterations,
    );
    final Map<String, Uint8List> records = StoreExport.decode(file, 'pw');
    expect(records.keys, <String>['thread:ch:1']);
    expect(utf8.decode(records.values.single), isNot(contains('channel 0')));
  });

  test('a row from another thread is refused, not silently included', () {
    final List<ChatMessage> mixed = <ChatMessage>[
      ...channelRows(1, 1),
      ...peerRows('aabbccddeeff00112233', 1),
    ];
    expect(
      () => HistoryExport.encodeThread(
        key: HistoryExport.channelKey(1),
        messages: mixed,
        passphrase: 'pw',
        iterations: iterations,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a wrong passphrase is refused as a named outcome', () {
    final Uint8List file = HistoryExport.encodeThread(
      key: HistoryExport.channelKey(0),
      messages: channelRows(0, 1),
      passphrase: 'right',
      iterations: iterations,
    );
    expect(
      () => HistoryExport.decodeThread(
        bytes: file,
        passphrase: 'wrong',
        key: HistoryExport.channelKey(0),
      ),
      throwsA(isA<ExportRefused>()),
    );
  });

  test('an altered byte is refused', () {
    final Uint8List file = HistoryExport.encodeThread(
      key: HistoryExport.channelKey(0),
      messages: channelRows(0, 1),
      passphrase: 'pw',
      iterations: iterations,
    );
    final Uint8List tampered = Uint8List.fromList(file);
    tampered[tampered.length - 1] ^= 0xFF;
    expect(
      () => HistoryExport.decodeThread(
        bytes: tampered,
        passphrase: 'pw',
        key: HistoryExport.channelKey(0),
      ),
      throwsA(isA<ExportRefused>()),
    );
  });

  test('a file that holds a different conversation is refused by name', () {
    final Uint8List file = HistoryExport.encodeThread(
      key: HistoryExport.channelKey(0),
      messages: channelRows(0, 1),
      passphrase: 'pw',
      iterations: iterations,
    );
    expect(
      () => HistoryExport.decodeThread(
        bytes: file,
        passphrase: 'pw',
        key: HistoryExport.channelKey(3),
      ),
      throwsA(isA<ExportRefused>().having((ExportRefused e) => e.reason,
          'reason', contains('different conversation'))),
    );
  });

  test('the exported file does not show the message text', () {
    final Uint8List file = HistoryExport.encodeThread(
      key: HistoryExport.channelKey(0),
      messages: channelRows(0, 2),
      passphrase: 'pw',
      iterations: iterations,
    );
    expect(utf8.decode(file, allowMalformed: true),
        isNot(contains('channel 0 message')));
  });

  group('the whole history', () {
    test('every thread comes back out of one file', () {
      final List<ChatMessage> rows = <ChatMessage>[
        ...channelRows(0, 3),
        ...channelRows(5, 2),
        ...peerRows('ab' * 32, 4),
      ];
      final Uint8List file = HistoryExport.encodeHistory(
        messages: rows,
        passphrase: 'pw',
        iterations: iterations,
      );
      final List<ChatMessage> back = HistoryExport.decodeFile(
        bytes: file,
        passphrase: 'pw',
      );
      expect(back.length, rows.length);
      expect(
        back.map((ChatMessage m) => HistoryExport.threadKeyOf(m)).toSet(),
        <String>{
          HistoryExport.channelKey(0),
          HistoryExport.channelKey(5),
          HistoryExport.peerKey('ab' * 32),
        },
        reason: 'one record per thread, keyed the way a single export is',
      );
    });

    test('a backup holds every conversation, not the first one', () {
      final Uint8List file = HistoryExport.encodeHistory(
        messages: <ChatMessage>[
          ...channelRows(0, 1),
          ...channelRows(1, 1),
        ],
        passphrase: 'pw',
        iterations: iterations,
      );
      final List<ChatMessage> back =
          HistoryExport.decodeFile(bytes: file, passphrase: 'pw');
      expect(back.map((ChatMessage m) => m.channelIdx).toSet(), <int>{0, 1});
    });

    test('an empty history is refused rather than written', () {
      expect(
        () => HistoryExport.encodeHistory(
          messages: const <ChatMessage>[],
          passphrase: 'pw',
          iterations: iterations,
        ),
        throwsA(isA<ExportRefused>().having(
            (ExportRefused e) => e.reason, 'reason', contains('no history'))),
      );
    });

    test('the whole-history file is sealed like one thread', () {
      final Uint8List file = HistoryExport.encodeHistory(
        messages: <ChatMessage>[
          ...channelRows(0, 1),
          ...peerRows('cd' * 32, 1),
        ],
        passphrase: 'pw',
        iterations: iterations,
      );
      expect(utf8.decode(file, allowMalformed: true),
          isNot(contains('channel 0 message')));
      expect(
        () => HistoryExport.decodeFile(bytes: file, passphrase: 'wrong'),
        throwsA(isA<ExportRefused>()),
      );
    });
  });
}
