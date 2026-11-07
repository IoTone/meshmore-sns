// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:meshcore/meshcore.dart';

import 'secure/sealed_document.dart';

/// The radio's synced contact table, kept across restarts.
///
/// The table used to live only in memory while the incremental-sync token
/// (`mm.contacts.since`) was persisted. After a restart the app therefore
/// believed it already held every contact and asked the radio only for the ones
/// modified since that token, which is normally none, so the table stayed empty
/// for good: the dashboard read "contacts 193/350" from the radio's own count
/// while Ping, Trace and every telemetry tool said "no synced contacts yet".
///
/// Kept sealed, like the chat history, the trail and the fences: a contact is a
/// public key, a name and a position the owner of that key chose to advertise,
/// and the app should not leave a list of them in a world-readable preferences
/// file. A store that cannot seal degrades to session-only, which is the
/// behaviour that existed before.
final class ContactStore {
  ContactStore._();

  /// Record name in the app's sealed store.
  static const String recordName = 'contacts';

  /// A backstop, not a working limit: the firmware's own table tops out far
  /// below this, and a corrupt document must not be able to make the app hold
  /// an unbounded list.
  static const int capacity = 2000;

  /// Set when the sealed store could not be opened, so the table is
  /// session-only.
  static final ValueNotifier<bool> sealedUnreadable = ValueNotifier<bool>(false);

  static Future<List<Contact>> load() async {
    final String? raw = await SealedDocument.read(recordName,
        sealedUnreadable: sealedUnreadable);
    return decode(raw);
  }

  static List<Contact> decode(String? raw) {
    if (raw == null || raw.isEmpty) return <Contact>[];
    try {
      final Object? doc = jsonDecode(raw);
      if (doc is! List) return <Contact>[];
      final List<Contact> rows = <Contact>[
        for (final Object? e in doc)
          if (_contactFromJson(e) case final Contact c) c,
      ];
      return rows.length > capacity ? rows.sublist(0, capacity) : rows;
    } on FormatException {
      return <Contact>[];
    }
  }

  static String encode(Iterable<Contact> contacts) => jsonEncode(
      <Object?>[for (final Contact c in contacts) _contactToJson(c)]);

  static Future<void> save(Iterable<Contact> contacts) async {
    final bool ok = await SealedDocument.write(recordName, encode(contacts));
    sealedUnreadable.value = !ok;
  }

  static Future<void> clear() => SealedDocument.clear(recordName);

  // --- the wire record, field for field ---------------------------------
  //
  // `Contact` has no `toJson` because the app is its only serializer: the
  // radio's own frame already is the wire format, and the model is built from
  // it. Writing the ten fields out here keeps the round trip honest without
  // teaching the protocol package about a file the radio never sees.

  static Map<String, Object?> _contactToJson(Contact c) => <String, Object?>{
        'k': _hex(c.publicKey),
        'ty': c.type,
        'fl': c.flags,
        'pl': c.outPathLen,
        'p': _hex(c.outPath),
        'n': c.name,
        'adv': c.lastAdvertTimestamp,
        'la': c.latitudeMicros,
        'lo': c.longitudeMicros,
        'lm': c.lastMod,
      };

  static Contact? _contactFromJson(Object? raw) {
    if (raw is! Map) return null;
    final Uint8List? key = _bytes(raw['k']);
    if (key == null || key.length != kPubKeySize) return null;
    final Uint8List? path = _bytes(raw['p']);
    if (path == null) return null;
    final Object? type = raw['ty'];
    final Object? flags = raw['fl'];
    final Object? pathLen = raw['pl'];
    final Object? adv = raw['adv'];
    final Object? lat = raw['la'];
    final Object? lon = raw['lo'];
    final Object? lastMod = raw['lm'];
    if (type is! int || flags is! int || pathLen is! int) return null;
    if (adv is! int || lat is! int || lon is! int || lastMod is! int) return null;
    if (pathLen < 0 || pathLen > 0xFF) return null;
    if (lat.abs() > 90000000 || lon.abs() > 180000000) return null;
    final Object? name = raw['n'];
    return Contact(
      publicKey: key,
      type: type,
      flags: flags,
      outPathLen: pathLen,
      outPath: path,
      name: name is String ? name : '',
      lastAdvertTimestamp: adv,
      latitudeMicros: lat,
      longitudeMicros: lon,
      lastMod: lastMod,
    );
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Even-length lowercase hex, or null. A stored row that is not readable as
  /// bytes is dropped rather than guessed at, which is the same rule the radio's
  /// own decoder applies to a frame.
  static Uint8List? _bytes(Object? raw) {
    if (raw is! String || raw.length.isOdd) return null;
    final Uint8List out = Uint8List(raw.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      final int? hi = _nibble(raw.codeUnitAt(i * 2));
      final int? lo = _nibble(raw.codeUnitAt(i * 2 + 1));
      if (hi == null || lo == null) return null;
      out[i] = (hi << 4) | lo;
    }
    return out;
  }

  static int? _nibble(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    return null;
  }
}
