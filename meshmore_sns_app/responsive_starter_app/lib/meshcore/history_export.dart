// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'chat_message.dart';
import 'secure/store_export.dart';

/// One thread's history as a passphrase-encrypted file.
///
/// The message store's key never leaves the Android Keystore, so a copy of
/// `mm_store.bin` is unreadable anywhere else. History leaves the phone only
/// through [StoreExport]'s `MMEX` file, which carries its own KDF id and
/// parameters so an import years later still opens: a user passphrase is the
/// one secret that can travel with the file.
///
/// A thread is exported on its own (one channel slot or one peer) because
/// exporting this conversation must not hand over the rest of them.
abstract final class HistoryExport {
  static String channelKey(int channelIdx) => 'thread:ch:$channelIdx';

  /// Keyed by the 12-hex prefix the rows store, because that is what
  /// identifies a peer thread.
  static String peerKey(String peerPubKeyHex) =>
      'thread:dm:${_peerPrefix(peerPubKeyHex)}';

  /// Spelled the same way [ChatStore] counts dropped rows.
  static String threadKeyOf(ChatMessage m) => m.channelIdx >= 0
      ? channelKey(m.channelIdx)
      : peerKey(m.peerPubKeyHex ?? '');

  static Uint8List encodeThread({
    required String key,
    required List<ChatMessage> messages,
    required String passphrase,
    int iterations = StoreExport.defaultIterations,
  }) {
    for (final ChatMessage m in messages) {
      if (threadKeyOf(m) != key) {
        throw ArgumentError.value(
            threadKeyOf(m), 'messages', 'row belongs to another thread');
      }
    }
    final Uint8List payload = Uint8List.fromList(
      utf8.encode(
        jsonEncode(messages.map((ChatMessage m) => m.toJson()).toList()),
      ),
    );
    return StoreExport.encode(
      <String, Uint8List>{key: payload},
      passphrase,
      iterations: iterations,
    );
  }

  /// A wrong passphrase, an altered file and a file holding a different
  /// conversation are all [ExportRefused]: a named outcome a caller can put
  /// in front of a user, never a stack trace.
  static List<ChatMessage> decodeThread({
    required Uint8List bytes,
    required String passphrase,
    required String key,
  }) {
    final Map<String, Uint8List> records =
        StoreExport.decode(bytes, passphrase);
    final Uint8List? payload = records[key];
    if (payload == null) {
      throw const ExportRefused('the file holds a different conversation');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(payload));
    } on FormatException {
      throw const ExportRefused('the thread payload is not readable');
    }
    if (decoded is! List) {
      throw const ExportRefused('the thread payload is not a message list');
    }
    return decoded
        .whereType<Map<String, Object?>>()
        .map(ChatMessage.fromJson)
        .toList(growable: false);
  }

  /// Every conversation an export file holds, decoded together. A file may
  /// carry one thread (what this app writes today) or several (a future
  /// whole-history export), and a restore should not have to ask which.
  static List<ChatMessage> decodeFile({
    required Uint8List bytes,
    required String passphrase,
  }) {
    final Map<String, Uint8List> records =
        StoreExport.decode(bytes, passphrase);
    final List<ChatMessage> out = <ChatMessage>[];
    for (final MapEntry<String, Uint8List> e in records.entries) {
      if (!e.key.startsWith('thread:')) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(e.value));
      } on FormatException {
        throw const ExportRefused('the thread payload is not readable');
      }
      if (decoded is! List) {
        throw const ExportRefused('the thread payload is not a message list');
      }
      out.addAll(decoded
          .whereType<Map<String, Object?>>()
          .map(ChatMessage.fromJson));
    }
    if (out.isEmpty) {
      throw const ExportRefused('the file holds no conversation');
    }
    return out;
  }

  // Isolate wrappers: the KDF is deliberately expensive, and both directions
  // would otherwise run it on the frame thread.
  static Future<Uint8List> encodeThreadAsync({
    required String key,
    required List<ChatMessage> messages,
    required String passphrase,
    int iterations = StoreExport.defaultIterations,
  }) =>
      Isolate.run(() => encodeThread(
            key: key,
            messages: messages,
            passphrase: passphrase,
            iterations: iterations,
          ));

  static Future<List<ChatMessage>> decodeFileAsync({
    required Uint8List bytes,
    required String passphrase,
  }) =>
      Isolate.run(() => decodeFile(bytes: bytes, passphrase: passphrase));

  static String _peerPrefix(String peerPubKeyHex) =>
      peerPubKeyHex.length >= 12
          ? peerPubKeyHex.substring(0, 12)
          : peerPubKeyHex;
}
