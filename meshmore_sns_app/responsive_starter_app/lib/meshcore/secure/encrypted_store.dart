// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'record_cipher.dart';

/// The store does not open: a foreign or damaged file, or a different key.
/// Callers must treat this as "no data", never as "empty history", so that a
/// corrupt file is reported once instead of being silently overwritten.
class EncryptedStoreCorrupt implements Exception {
  const EncryptedStoreCorrupt(this.reason);
  final String reason;
  @override
  String toString() => 'EncryptedStoreCorrupt($reason)';
}

/// No key, so nothing can be written. The caller keeps its data where it was.
class EncryptedStoreUnavailable implements Exception {
  const EncryptedStoreUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'EncryptedStoreUnavailable($reason)';
}

/// One encrypted key/value file for everything the app must keep on the phone
/// and must not leak: chat history today, places, drafts and the block list as
/// those stores move onto it.
///
/// The whole record map is serialised to JSON, sealed as one blob, and written
/// atomically (write to a sibling file, then rename), so a crash mid-write
/// leaves the previous file intact rather than a half-sealed one.
///
/// On-disk layout: `MMS1` | one byte format version | sealed payload. The
/// payload is JSON `{name: base64(bytes)}`.
class EncryptedStore {
  EncryptedStore({RecordCipher? cipher, Future<Directory> Function()? directory})
      : _cipher = cipher ?? const KeystoreRecordCipher(),
        _directory = directory ?? getApplicationSupportDirectory;

  final RecordCipher _cipher;
  final Future<Directory> Function() _directory;

  static const String fileName = 'mm_store.bin';
  static const String tempName = 'mm_store.bin.new';
  static const List<int> magic = <int>[0x4D, 0x4D, 0x53, 0x31]; // 'MMS1'
  static const int formatVersion = 1;

  /// Writes are serialised per file, not per instance: two messages arriving
  /// together must not read the same map, each add one entry, and lose one of
  /// them.
  ///
  /// The lock lives on the file path because several stores write this one
  /// file (history, drafts, the block list) and each of them builds its own
  /// instance per operation. A chain held on the instance would therefore
  /// serialise nothing in the app: a draft save and a chat save would both read
  /// the map, each set its own record, and the later write would take the
  /// earlier one's record with it. Keyed by path, two files stay independent,
  /// which keeps a test's temporary directory out of another's way.
  static final Map<String, Future<void>> _chains = <String, Future<void>>{};

  Future<T> _serial<T>(Future<T> Function() action) async {
    final String key = (await _dir()).path;
    final Future<void> previous = _chains[key] ?? Future<void>.value();
    final Future<T> next = previous.then((_) => action());
    final Future<void> tail = next.then((_) {}, onError: (Object _) {});
    _chains[key] = tail;
    // Drop the entry once nothing is queued behind it, so a process that
    // touches many directories (a test suite) does not grow the map forever.
    tail.whenComplete(() {
      if (identical(_chains[key], tail)) _chains.remove(key);
    });
    return next;
  }

  /// A host with no platform path provider (a plain unit test, or a platform
  /// the app does not support) has nowhere to put the store: report it as
  /// unavailable so the caller keeps working rather than crashing a startup.
  Future<Directory> _dir() async {
    try {
      return await _directory();
    } on MissingPluginException {
      throw const EncryptedStoreUnavailable('no app-support directory');
    } on PlatformException catch (e) {
      throw EncryptedStoreUnavailable(e.code);
    }
  }

  Future<File> _file() async =>
      File('${(await _dir()).path}${Platform.pathSeparator}$fileName');

  Future<File> _temp() async =>
      File('${(await _dir()).path}${Platform.pathSeparator}$tempName');

  /// Every record, or an empty map when the file does not exist yet.
  Future<Map<String, Uint8List>> readAll() => _serial(_readAll);

  Future<Map<String, Uint8List>> _readAll() async {
    final File f = await _file();
    if (!f.existsSync()) return <String, Uint8List>{};
    final Uint8List raw = await f.readAsBytes();
    if (raw.length < magic.length + 1) {
      throw const EncryptedStoreCorrupt('shorter than a header');
    }
    for (int i = 0; i < magic.length; i++) {
      if (raw[i] != magic[i]) {
        throw const EncryptedStoreCorrupt('not this app\'s store');
      }
    }
    final int version = raw[magic.length];
    if (version != formatVersion) {
      throw EncryptedStoreCorrupt('format version $version');
    }
    final Uint8List sealed = raw.sublist(magic.length + 1);
    final Uint8List plain;
    try {
      plain = await _cipher.open(sealed);
    } on SealedDataCorrupt catch (e) {
      throw EncryptedStoreCorrupt(e.reason);
    } on RecordCipherUnavailable catch (e) {
      throw EncryptedStoreUnavailable(e.reason);
    }
    try {
      final Object? decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map<String, Object?>) {
        throw const EncryptedStoreCorrupt('payload is not a map');
      }
      return <String, Uint8List>{
        for (final MapEntry<String, Object?> e in decoded.entries)
          e.key: base64Decode(e.value! as String),
      };
    } on FormatException catch (e) {
      throw EncryptedStoreCorrupt('payload not decodable: ${e.message}');
    } on TypeError {
      throw const EncryptedStoreCorrupt('payload has a non-string value');
    }
  }

  Future<Uint8List?> read(String name) async => (await readAll())[name];

  Future<void> write(String name, Uint8List bytes) =>
      _serial(() async {
        final Map<String, Uint8List> all = await _readAll();
        all[name] = bytes;
        await _writeAll(all);
      });

  Future<void> remove(String name) => _serial(() async {
        final Map<String, Uint8List> all = await _readAll();
        if (all.remove(name) == null) return;
        await _writeAll(all);
      });

  Future<void> clear() => _serial(() async {
        final File f = await _file();
        if (f.existsSync()) await f.delete();
      });

  Future<void> _writeAll(Map<String, Uint8List> all) async {
    final Uint8List plain = Uint8List.fromList(utf8.encode(jsonEncode(
        <String, String>{
      for (final MapEntry<String, Uint8List> e in all.entries)
        e.key: base64Encode(e.value),
    })));
    final Uint8List sealed;
    try {
      sealed = await _cipher.seal(plain);
    } on RecordCipherUnavailable catch (e) {
      throw EncryptedStoreUnavailable(e.reason);
    }
    final File temp = await _temp();
    await temp.writeAsBytes(
        <int>[...magic, formatVersion, ...sealed],
        flush: true);
    await temp.rename((await _file()).path);
  }
}
