// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../meshcore/secure/encrypted_store.dart';
import '../meshcore/secure/record_cipher.dart';

/// APP-E7 — unsent composer text, kept per channel and per direct thread.
///
/// A draft is the one piece of user text the app holds that is neither a sent
/// message nor a UI preference, so it lives in the same sealed store as history
/// ([EncryptedStore]) rather than in `SharedPreferences`. The key is nested:
/// the radio first, then the conversation. A phone that meets a second radio
/// must not offer the first radio's drafts to it — a draft is aimed at a mesh,
/// and peer keys and channel slots belong to the radio they came from.
///
/// Nothing here throws to a caller: a store that cannot open reads as "no
/// drafts", because losing the recall of a draft must never block the composer.
/// The three operations the composer needs, so a widget test can drive the
/// debounce in fake time instead of waiting on real file I/O.
abstract interface class DraftSink {
  Future<String> read(String key);
  Future<void> save(String key, String text);
  Future<void> clear(String key);
}

abstract final class DraftStore {
  /// The record's name inside the store file.
  static const String recordName = 'drafts';

  /// Namespace for a radio that has not answered yet. Distinct from a real key
  /// so an unknown radio cannot inherit somebody else's drafts.
  static const String noRadio = 'noradio';

  /// Debounce for a keystroke: long enough that a fast typist writes once per
  /// phrase, short enough that a process kill keeps the sentence.
  static const Duration debounce = Duration(milliseconds: 700);

  /// Test seam: when set, [read], [save] and [clear] go here instead of the
  /// sealed file. `test/screens/chat_screen_test.dart` uses it because a
  /// debounced write is a timer, and a timer only fires in fake time.
  @visibleForTesting
  static DraftSink? sinkOverride;

  @visibleForTesting
  static RecordCipher? cipherOverride;

  @visibleForTesting
  static Directory? directoryOverride;

  /// The overrides are read here, not in the directory callback: a debounced
  /// save can complete after whatever set the override has torn down, and a
  /// callback that dereferenced the static then would throw on null instead of
  /// writing the record it was asked to write.
  static EncryptedStore _store() {
    final RecordCipher? cipher = cipherOverride;
    final Directory? dir = directoryOverride;
    return EncryptedStore(
      cipher: cipher,
      directory: dir == null ? null : () async => dir,
    );
  }

  /// The radio namespace: the first eight hex of its public key, which is how
  /// the rest of the app already names a radio (`_hex(pub).substring(0, 8)`).
  static String radioScope(List<int>? publicKey) {
    if (publicKey == null || publicKey.isEmpty) return noRadio;
    final StringBuffer b = StringBuffer();
    for (final int byte in publicKey.take(4)) {
      b.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  /// The key for one conversation: either a channel slot or a peer key.
  static String keyFor(String radioScope, {int? channelIdx, String? peerHex}) {
    if (channelIdx != null) return '$radioScope|ch:$channelIdx';
    if (peerHex != null) return '$radioScope|dm:${peerHex.toLowerCase()}';
    throw ArgumentError('a draft belongs to a channel or a peer');
  }

  /// One store per operation: a save reads the record and then writes it, and
  /// resolving the directory twice would let a teardown between the two send
  /// the write somewhere else (or into a null seam).
  static Future<Map<String, String>> _read([EncryptedStore? store]) async {
    try {
      final Uint8List? raw = await (store ?? _store()).read(recordName);
      if (raw == null) return <String, String>{};
      final Object? decoded = jsonDecode(utf8.decode(raw));
      if (decoded is! Map) return <String, String>{};
      final Map<String, String> out = <String, String>{};
      decoded.forEach((Object? k, Object? v) {
        if (k is String && v is String) out[k] = v;
      });
      return out;
    } on EncryptedStoreUnavailable {
      return <String, String>{};
    } on EncryptedStoreCorrupt {
      return <String, String>{};
    } on FormatException {
      return <String, String>{};
    }
  }

  static Future<void> _write(Map<String, String> drafts,
      [EncryptedStore? store]) async {
    try {
      await (store ?? _store())
          .write(recordName, utf8.encode(jsonEncode(drafts)));
    } on EncryptedStoreUnavailable {
      // No key: the composer keeps working, the draft is simply not kept.
    } on EncryptedStoreCorrupt {
      // Refuse to overwrite a file this install cannot read.
    }
  }

  /// Every draft for [radioScope] and nothing else.
  static Future<Map<String, String>> forRadio(String radioScope) async {
    final Map<String, String> all = await _read();
    final String prefix = '$radioScope|';
    final Map<String, String> out = <String, String>{};
    all.forEach((String k, String v) {
      if (k.startsWith(prefix)) out[k] = v;
    });
    return out;
  }

  /// The draft for one conversation, or empty.
  static Future<String> read(String key) async =>
      sinkOverride?.read(key) ?? (await _read())[key] ?? '';

  /// Store [text] as the draft for [key]; blank text removes the entry, so an
  /// emptied composer leaves no row behind.
  static Future<void> save(String key, String text) async {
    final DraftSink? sink = sinkOverride;
    if (sink != null) {
      await sink.save(key, text);
      return;
    }
    final EncryptedStore store = _store();
    final Map<String, String> all = await _read(store);
    if (text.trim().isEmpty) {
      if (all.remove(key) == null) return;
    } else {
      if (all[key] == text) return;
      all[key] = text;
    }
    await _write(all, store);
  }

  /// Forget one draft (after a send, or when the user clears it).
  static Future<void> clear(String key) async {
    final DraftSink? sink = sinkOverride;
    if (sink != null) {
      await sink.clear(key);
      return;
    }
    await save(key, '');
  }

  /// Drop every draft for a radio that is no longer attached. Kept for the
  /// identity-replacement path (D8.7): a new radio key is a new radio and must
  /// not inherit the old one's drafts.
  static Future<void> clearRadio(String radioScope) async {
    final EncryptedStore store = _store();
    final Map<String, String> all = await _read(store);
    final String prefix = '$radioScope|';
    final int before = all.length;
    all.removeWhere((String k, String _) => k.startsWith(prefix));
    if (all.length == before) return;
    await _write(all, store);
  }
}
