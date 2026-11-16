// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'secure/encrypted_store.dart';
import 'secure/record_cipher.dart';

/// Why a key was blocked. Display and diagnostics only — the filter treats
/// every reason the same, because the spec's promise is the same for all
/// three: the app shows nothing from the key, the radio still carries it.
enum BlockReason { user, report, imported }

/// One blocked public key.
///
/// The 32-byte key is the authority. [name] is a snapshot for display and may
/// be stale or wrong; nothing matches on it except the one-time pin in
/// [BlockStore.isBlockedName], which requires the name to be unique.
@immutable
class BlockedKey {
  const BlockedKey({
    required this.pubKeyHex,
    required this.sinceMs,
    this.name,
    this.reason = BlockReason.user,
    this.notifySuppressed = true,
  });

  /// Lower-case hex of the full 32-byte public key (64 characters).
  final String pubKeyHex;
  final int sinceMs;
  final String? name;
  final BlockReason reason;

  /// The app stops raising its own notifications for this key. It cannot stop
  /// the radio's buzzer, which is why the copy says so.
  final bool notifySuppressed;

  Map<String, Object?> toJson() => <String, Object?>{
        'pubKeyHex': pubKeyHex,
        'sinceMs': sinceMs,
        if (name != null) 'name': name,
        'reason': reason.name,
        'notifySuppressed': notifySuppressed,
      };

  static BlockedKey? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final Object? hex = raw['pubKeyHex'];
    final Object? since = raw['sinceMs'];
    if (hex is! String || since is! num) return null;
    if (!isFullKeyHex(hex)) return null;
    return BlockedKey(
      pubKeyHex: hex,
      sinceMs: since.toInt(),
      name: raw['name'] as String?,
      reason: BlockReason.values.firstWhere(
        (BlockReason r) => r.name == raw['reason'],
        orElse: () => BlockReason.user,
      ),
      notifySuppressed: raw['notifySuppressed'] as bool? ?? true,
    );
  }

  /// A block keyed by anything but the full 32-byte key is refused, because
  /// four hex characters are not an identity: a stranger whose name matched a
  /// prefix was once taken for the operator's own hardware across 350 contacts.
  static bool isFullKeyHex(String hex) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(hex);
}

/// The block list: an app-side store, keyed by the full public key.
///
/// No firmware read has a per-sender block, and none is needed: the filter is
/// the app's, every surface reads it, and the radio's own copy of anything is
/// untouched. There is no cross-device sync because there is no radio-side
/// record to share (D8.12).
///
/// It lives in the same sealed file as history, in its own record, so a copy
/// of the file is useless on another device and the list survives a restart.
class BlockStore extends ChangeNotifier {
  BlockStore({Map<String, BlockedKey>? seed})
      : _byKey = <String, BlockedKey>{...?seed};

  /// A list that silently drops entries is worse than no list, so the bound is
  /// explicit and [atCapacity] lets the UI say so.
  static const int capacity = 500;

  /// The record's name inside [EncryptedStore].
  static const String recordName = 'blocks';

  /// Test seams, mirroring `ChatStore`.
  @visibleForTesting
  static RecordCipher? cipherOverride;
  @visibleForTesting
  static Directory? directoryOverride;

  final Map<String, BlockedKey> _byKey;

  /// False when the sealed store cannot be opened (no key, wiped keystore).
  /// The list still filters for this session; it just will not survive.
  bool _persisted = true;
  bool get persisted => _persisted;

  /// True when the sealed list existed but could not be read. Different from
  /// "nothing is saved yet": the list the user had is not in force this
  /// session, and a damaged copy is kept beside the store.
  bool _unreadable = false;
  bool get unreadable => _unreadable;

  bool _loaded = false;
  bool get loaded => _loaded;

  /// Read at call time, not in the callback: a write in flight must not
  /// dereference an override that has since been cleared.
  EncryptedStore _store() {
    final RecordCipher? cipher = cipherOverride;
    final Directory? dir = directoryOverride;
    return EncryptedStore(
      cipher: cipher,
      directory: dir == null ? null : () async => dir,
    );
  }

  Iterable<BlockedKey> get all => _byKey.values;
  int get count => _byKey.length;
  bool get atCapacity => count >= capacity;

  /// True when [keyHex] is blocked. Accepts the short prefix the radio sends
  /// for a legacy contact frame, because a blocked full key's prefix is still
  /// that key; a prefix is never used to *create* a block.
  bool isBlocked(String? keyHex) {
    if (keyHex == null || keyHex.isEmpty) return false;
    final String k = keyHex.toLowerCase();
    if (_byKey.containsKey(k)) return true;
    if (k.length >= 12 && k.length < 64) {
      for (final String full in _byKey.keys) {
        if (full.startsWith(k)) return true;
      }
    }
    return false;
  }

  /// The one legitimate use of a name: a message whose author key the wire did
  /// not carry still shows a display name, and if exactly one blocked entry
  /// carries that name, this is that key. A name shared by two entries pins
  /// nothing.
  bool isBlockedName(String? name) {
    if (name == null) return false;
    final String n = name.trim();
    if (n.isEmpty) return false;
    int matches = 0;
    String? only;
    for (final BlockedKey b in _byKey.values) {
      if (b.name == n) {
        matches++;
        only = b.pubKeyHex;
      }
    }
    return matches == 1 && only != null;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    Uint8List? raw;
    try {
      raw = await _store().read(recordName);
      if (raw == null) return;
      final Object? decoded = jsonDecode(utf8.decode(raw));
      if (decoded is! List) return;
      for (final Object? entry in decoded) {
        final BlockedKey? key = BlockedKey.fromJson(entry);
        if (key != null) _byKey[key.pubKeyHex] = key;
      }
    } on EncryptedStoreUnavailable {
      _persisted = false;
    } on EncryptedStoreCorrupt {
      // A damaged list is not an empty list; keep it empty this session but
      // say the list could not be read rather than pretending it is clean.
      _persisted = false;
      _unreadable = true;
      await _dropDamagedFile();
    } on FormatException {
      // The file opened and decrypted; only this record's JSON is bad. Drop the
      // record, not the file: the other nine records in it are intact, and
      // deleting them because one block entry is malformed is a data loss the
      // reader never asked for.
      _persisted = false;
      _unreadable = true;
      await _dropDamagedRecord(raw);
    }
    notifyListeners();
  }

  /// Removes a store file that cannot be opened, so the next block can be
  /// saved. The store copied the damaged bytes aside while it detected them,
  /// which is what makes deleting the original safe: the evidence survives the
  /// session and the user can block again.
  ///
  /// Only for [EncryptedStoreCorrupt], where the file itself is unreadable.
  Future<void> _dropDamagedFile() async {
    try {
      await _store().clear();
    } on EncryptedStoreCorrupt {
      // Nothing more to do: the read already failed and the copy is made.
    }
  }

  /// Removes this record, and only this record, when its JSON is malformed.
  ///
  /// The bytes are kept first, in a `blocks.bad` record: the message the reader
  /// sees promises that a copy of the damaged data is kept, and on this path
  /// nothing else made one.
  Future<void> _dropDamagedRecord(Uint8List? raw) async {
    try {
      if (raw != null) await _store().write('$recordName.bad', raw);
      await _store().remove(recordName);
    } on EncryptedStoreCorrupt {
      // The file went bad between the read and the write; the copy is made.
    } on EncryptedStoreUnavailable {
      // Nothing to remove.
    }
  }

  /// Blocks [key]. Refuses a key that is not the full 32 bytes and refuses a
  /// list that is full, rather than dropping the oldest entry silently.
  Future<bool> block(BlockedKey key) async {
    if (!BlockedKey.isFullKeyHex(key.pubKeyHex)) {
      throw ArgumentError.value(
          key.pubKeyHex, 'pubKeyHex', 'a block needs the full 32-byte key');
    }
    if (_byKey.containsKey(key.pubKeyHex)) return false;
    if (atCapacity) return false;
    _byKey[key.pubKeyHex] = key;
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> unblock(String keyHex) async {
    final String k = keyHex.toLowerCase();
    if (_byKey.remove(k) == null) return;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final List<Map<String, Object?>> rows = _byKey.values
        .map((BlockedKey b) => b.toJson())
        .toList(growable: false);
    try {
      await _store().write(
        recordName,
        Uint8List.fromList(utf8.encode(jsonEncode(rows))),
      );
      _persisted = true;
    } on EncryptedStoreUnavailable {
      _persisted = false;
    } on EncryptedStoreCorrupt {
      _persisted = false;
    }
  }
}
