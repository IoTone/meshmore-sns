// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'encrypted_store.dart';
import 'record_cipher.dart';

/// A JSON document that belongs in the sealed store rather than in a
/// world-readable preferences file.
///
/// Three stores used to keep location data in the clear next to a sealed chat
/// history: places (`PlaceStore`, which carries its own failure states), the
/// movement trail and the geofences. This is the shared move-then-read shape for
/// the last two, so the migration rule exists once:
///
/// * read the sealed record first;
/// * if it is absent and a legacy preferences document exists, write it sealed,
///   read it back, compare, and only then delete the plaintext copy — a crash
///   between those steps leaves a duplicate, never a loss;
/// * a failure to seal is reported to the caller, which decides what to say.
final class SealedDocument {
  const SealedDocument._();

  /// Test seams, as in `ChatStore`: the app leaves both null and the real store
  /// seals through the Android Keystore in the app-support directory.
  @visibleForTesting
  static RecordCipher? cipherOverride;
  @visibleForTesting
  static Directory? directoryOverride;

  static EncryptedStore _store() {
    final Directory? dir = directoryOverride;
    return EncryptedStore(
      cipher: cipherOverride,
      directory: dir == null ? null : () async => dir,
    );
  }

  /// The document, or null when nothing has been stored yet.
  ///
  /// [legacyKey] is the pre-migration preferences key, read once and retired.
  /// Every sealed-store failure is reported as null with [sealedUnreadable] set,
  /// because in each case there is no document to hand back and the caller must
  /// not read that as "empty".
  static Future<String?> read(String record,
      {String? legacyKey, ValueNotifier<bool>? sealedUnreadable}) async {
    try {
      final Uint8List? sealed = await _store().read(record);
      if (sealed != null) return utf8.decode(sealed);
    } on EncryptedStoreKeyLost {
      sealedUnreadable?.value = true;
      return null;
    } on EncryptedStoreCorrupt {
      sealedUnreadable?.value = true;
      return null;
    } on EncryptedStoreUnavailable {
      // No app-support directory or no platform key. The store degrades to
      // "session only" rather than throwing at a caller that has nothing to do
      // with the failure; a legacy copy is still read so nothing is lost.
      sealedUnreadable?.value = true;
    }
    if (legacyKey == null) return null;
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? legacy = p.getString(legacyKey);
    if (legacy == null || legacy.isEmpty) return null;
    final bool moved = await write(record, legacy);
    if (moved) await p.remove(legacyKey);
    return legacy;
  }

  /// Writes, then reads back to prove the write, before returning true.
  ///
  /// A caller that gets false still has its data in memory: this is a write that
  /// did not land, not a lost document.
  static Future<bool> write(String record, String document) async {
    final Uint8List bytes = Uint8List.fromList(utf8.encode(document));
    try {
      await _store().write(record, bytes);
      final Uint8List? back = await _store().read(record);
      return back != null && utf8.decode(back) == document;
    } on EncryptedStoreKeyLost {
      return false;
    } on EncryptedStoreUnavailable {
      return false;
    } on EncryptedStoreCorrupt {
      return false;
    } on FileSystemException {
      return false;
    }
  }

  /// Removes the sealed record and any legacy copy.
  static Future<void> clear(String record, {String? legacyKey}) async {
    try {
      await _store().write(record, Uint8List(0));
    } on EncryptedStoreUnavailable {
      // No key: nothing was sealed, so there is nothing to clear.
    } on EncryptedStoreKeyLost {
      // Same: the file it cannot open is not a document this store wrote today.
    }
    if (legacyKey == null) return;
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.remove(legacyKey);
  }
}
