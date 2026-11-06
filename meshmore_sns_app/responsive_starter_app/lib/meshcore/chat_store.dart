// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_errors.dart';
import 'chat_message.dart';
import 'secure/encrypted_store.dart';
import 'secure/record_cipher.dart';
import '../util/prefs.dart';

/// Local persistence for channel chat history.
///
/// MeshCore's companion protocol has **no history-fetch** — the
/// device's message queue is drained destructively via
/// `SYNC_NEXT_MESSAGE`. So, like the official app, history is kept
/// on the phone: previously-sent/received messages survive app
/// restarts and reconnects.
///
/// The history lives in [EncryptedStore]: one sealed file whose key the
/// Android Keystore holds and cannot export, so a copy of the file is
/// useless anywhere else. It used to be plain JSON in
/// `SharedPreferences` (`mm.chat.v1`); [migrate] moves it once and removes
/// the plaintext only after reading the sealed copy back and comparing it.
abstract final class ChatStore {
  static const String _kLegacyKey = 'mm.chat.v1';

  /// Present and equal to [formatVersion] once the sealed copy is proven
  /// readable. Its absence means "the plaintext is still the truth".
  static const String _kMigratedKey = 'mm.chat.storeV';
  static const int formatVersion = 1;

  /// The record's name inside the store file.
  static const String recordName = 'chat';

  /// Where the per-thread count of rows the cap has already dropped lives.
  /// A separate record, not a new message payload shape: the history file
  /// keeps its format, and a missing count reads as zero.
  static const String droppedRecordName = 'chat.dropped';

  /// Hard cap on persisted messages (oldest dropped first).
  static const int cap = 250;

  /// True when the sealed history is on disk but this device can no longer
  /// open it: the Keystore key that sealed it is gone (a restore onto a new
  /// device, a credential reset, a cleared Keystore). The file is left
  /// untouched, so the history is not lost — only unreadable here — and the
  /// UI says so instead of showing an empty thread list.
  static final ValueNotifier<bool> unreadable = ValueNotifier<bool>(false);

  /// The last write that did not reach the sealed store, as one of
  /// `keyLost`, `unavailable`, `corrupt`, `noSpace`. Null when the last write
  /// succeeded. A message that is shown but not persisted is a lie the app
  /// should not tell silently, and Diagnostics reads this.
  static final ValueNotifier<String?> lastWriteFailure =
      ValueNotifier<String?>(null);

  /// Test seam: a notifier outlives a test, so the next one starts clean.
  @visibleForTesting
  static void resetStatus() {
    unreadable.value = false;
    lastWriteFailure.value = null;
  }

  /// The key a dropped row is counted under: a channel slot, or a DM peer.
  static String threadKeyOf(ChatMessage m) => m.channelIdx >= 0
      ? 'ch:${m.channelIdx}'
      : 'dm:${m.peerPubKeyHex?.substring(0, 12) ?? ''}';

  /// How many older rows the cap has already dropped, per thread. A store
  /// that drops rows without saying so makes "where did it go" unanswerable,
  /// so the count outlives the rows it counts.
  static Future<Map<String, int>> loadDropped() async {
    try {
      if (!await _ensureSealed()) return <String, int>{};
      final Uint8List? raw = await _store().read(droppedRecordName);
      if (raw == null) return <String, int>{};
      final Object? decoded = jsonDecode(utf8.decode(raw));
      if (decoded is! Map<String, Object?>) return <String, int>{};
      return <String, int>{
        for (final MapEntry<String, Object?> e in decoded.entries)
          if (e.value is num) e.key: (e.value! as num).toInt(),
      };
    } on EncryptedStoreUnavailable {
      return <String, int>{};
    } on EncryptedStoreCorrupt {
      return <String, int>{};
    } on FormatException {
      return <String, int>{};
    }
  }

  static Future<void> saveDropped(Map<String, int> counts) async {
    final Map<String, int> kept = <String, int>{
      for (final MapEntry<String, int> e in counts.entries)
        if (e.value > 0) e.key: e.value,
    };
    try {
      if (!await _ensureSealed()) return;
      await _store().write(droppedRecordName,
          Uint8List.fromList(utf8.encode(jsonEncode(kept))));
    } on EncryptedStoreUnavailable {
      // No key: the count is session-only, like the history itself would be.
    }
  }

  /// Test seams. The app leaves both null: the real store seals through the
  /// Android Keystore and lives in the app-support directory.
  @visibleForTesting
  static RecordCipher? cipherOverride;
  @visibleForTesting
  static Directory? directoryOverride;

  static EncryptedStore _store() {
    // Capture the seams now. A closure that reads the mutable static later
    // throws if a test clears it while an unawaited save is still in flight,
    // which is exactly when the writes are queued.
    final Directory? dir = directoryOverride;
    return EncryptedStore(
      cipher: cipherOverride,
      directory: dir == null ? null : () async => dir,
    );
  }

  static Future<List<ChatMessage>> load() async {
    if (await _ensureSealed()) {
      try {
        final Uint8List? raw = await _store().read(recordName);
        unreadable.value = false;
        if (raw == null) return <ChatMessage>[];
        return _decode(utf8.decode(raw));
      } on EncryptedStoreUnavailable {
        // No platform key at all (a host without a Keystore). Nothing was ever
        // sealed here, so there is nothing to report.
        return <ChatMessage>[];
      } on EncryptedStoreKeyLost {
        unreadable.value = true;
        return <ChatMessage>[];
      } on EncryptedStoreCorrupt {
        return <ChatMessage>[];
      }
    }
    // The sealed copy could not be written or verified. The plaintext is
    // still there, so the app keeps working instead of losing history.
    final SharedPreferences p = await SharedPreferences.getInstance();
    return _decode(p.getString(_kLegacyKey) ?? '');
  }

  static Future<void> save(List<ChatMessage> messages) async {
    final List<ChatMessage> tail = messages.length > cap
        ? messages.sublist(messages.length - cap)
        : messages;
    final SharedPreferences p = await SharedPreferences.getInstance();
    final bool sealed = await _ensureSealed();
    if (sealed) {
      try {
        await _store().write(
            recordName, Uint8List.fromList(utf8.encode(_encode(tail))));
        lastWriteFailure.value = null;
        return;
      } on EncryptedStoreKeyLost {
        // The key is gone: writing would mint a new one and seal the new rows
        // under it while the old file stays unreadable. Keep the old copy, say
        // so, and persist nothing.
        unreadable.value = true;
        lastWriteFailure.value = 'keyLost';
        AppErrors.record('history store: key lost under a sealed file', null);
        return;
      } on EncryptedStoreUnavailable {
        lastWriteFailure.value = 'unavailable';
        AppErrors.record('history store: unavailable', null);
        return;
      } on EncryptedStoreCorrupt {
        lastWriteFailure.value = 'corrupt';
        AppErrors.record('history store: corrupt', null);
        return;
      } on FileSystemException catch (e) {
        lastWriteFailure.value = 'noSpace';
        AppErrors.record(e, null, where: 'history store');
        return;
      }
    }
    // The sealed store is the truth once the marker is set. Writing plaintext
    // behind it would create a second history nothing reads, and would put the
    // rows in the clear while the app says they are sealed.
    if (p.getInt(_kMigratedKey) == formatVersion) {
      lastWriteFailure.value = 'unavailable';
      return;
    }
    await Prefs.setString(p, _kLegacyKey, _encode(tail));
  }

  static Future<void> clear() async {
    try {
      await _store().clear();
      unreadable.value = false;
      lastWriteFailure.value = null;
    } on EncryptedStoreUnavailable {
      // Nothing sealed to clear; the legacy key below is the whole record.
    } on EncryptedStoreKeyLost {
      // The file is unreadable here; clearing it is the user's explicit
      // choice to start over, so the bytes go.
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.remove(_kMigratedKey);
      unreadable.value = false;
    }
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.remove(_kLegacyKey);
  }

  /// Moves the plaintext history into the sealed store, once.
  ///
  /// Idempotent: the version marker makes a second run a no-op. Resumable:
  /// the marker is written only after the sealed copy has been read back and
  /// compared message-for-message, so an interrupted or failed run leaves the
  /// plaintext in place and the next launch tries again.
  ///
  /// Returns true when the sealed store is the truth.
  static Future<bool> migrate() => _ensureSealed();

  static Future<bool> _ensureSealed() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    if (p.getInt(_kMigratedKey) == formatVersion) return true;
    final String? legacy = p.getString(_kLegacyKey);
    final List<ChatMessage> messages = _decode(legacy ?? '');
    try {
      if (legacy != null) {
        await _store()
            .write(recordName, Uint8List.fromList(utf8.encode(_encode(messages))));
        final Uint8List? back = await _store().read(recordName);
        if (back == null) throw const EncryptedStoreCorrupt('read back empty');
        final List<ChatMessage> verified = _decode(utf8.decode(back));
        if (!_sameMessages(messages, verified)) {
          throw const EncryptedStoreCorrupt('read back differs');
        }
      } else {
        // Nothing to migrate, but the marker may only be set once the store is
        // proven readable: on a host with no keystore it never is, and the
        // plaintext path has to stay the truth there.
        await _store().readAll();
      }
      await Prefs.setInt(p, _kMigratedKey, formatVersion);
      // Only now is the plaintext redundant.
      if (legacy != null) await p.remove(_kLegacyKey);
      return true;
    } on EncryptedStoreUnavailable {
      return false;
    } on EncryptedStoreKeyLost {
      // Nothing to migrate and nothing to write: the key that sealed the
      // existing file is gone. The marker is left alone so a later launch
      // says the same thing instead of starting a second history.
      if (legacy == null) unreadable.value = true;
      return false;
    } on EncryptedStoreCorrupt {
      return false;
    } on FileSystemException {
      return false;
    }
  }

  /// Compares each row the way it is written down, not by the two fields a
  /// reader happens to notice. A migration that dropped a timestamp, a
  /// delivery state or a fail reason would pass an id-and-text comparison and
  /// then delete the only copy that still had them.
  static bool _sameMessages(List<ChatMessage> a, List<ChatMessage> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (jsonEncode(a[i].toJson()) != jsonEncode(b[i].toJson())) return false;
    }
    return true;
  }

  static String _encode(List<ChatMessage> messages) =>
      jsonEncode(messages.map((ChatMessage m) => m.toJson()).toList());

  static List<ChatMessage> _decode(String raw) {
    if (raw.isEmpty) return <ChatMessage>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <ChatMessage>[];
      return decoded
          .whereType<Map<String, Object?>>()
          .map(ChatMessage.fromJson)
          .toList();
    } catch (_) {
      return <ChatMessage>[];
    }
  }
}
