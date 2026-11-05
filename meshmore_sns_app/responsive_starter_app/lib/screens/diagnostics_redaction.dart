// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

/// L1/L2 — what a diagnostics capture may leave the screen.
///
/// The capture exists so a frame can be replayed against the codec, so the
/// encrypted frames are kept verbatim: they are the evidence. What must not
/// be written out or copied is the material that would let someone else read
/// the mesh:
///
///  * a **channel PSK** decrypts every message on that channel, and the
///    interop fixture carries one in `psk_hex`, so it is masked to its first
///    four bytes and its width;
///  * a **node key** identifies a peer and is the input to a DM's key
///    agreement, so a field whose name says key, token, secret or pin is
///    masked the same way;
///  * a **position** is the most sensitive thing the app holds that is not a
///    key, so a coordinate field is coarsened to about a kilometre. The
///    screen a person is looking at still shows the fix they already have;
///    only the copy and export paths coarsen.
///
/// Masking is by field name, not by guessing at hex length: a 32-byte
/// ciphertext and a 32-byte key look identical, and guessing wrong would
/// either leak a key or destroy the evidence.
class DiagnosticsRedaction {
  const DiagnosticsRedaction({this.revealPosition = false});

  /// Coordinates a person has asked to see in full. Off by default; the
  /// screen never sets it, so a shared capture cannot carry a fix.
  final bool revealPosition;

  static const String _mask = '…';

  static final RegExp _secretField =
      RegExp(r'(psk|key|token|secret|pin|password)', caseSensitive: false);
  static final RegExp _positionField = RegExp(
      r'^(lat|lon|lng|latitude|longitude|coord|coords|coordinate|coordinates)$',
      caseSensitive: false);

  /// A JSON document with its secrets masked. Anything that is not JSON is
  /// returned with `maskSecrets` applied instead of throwing, because a
  /// diagnostics path that fails closed is better than one that crashes.
  String json(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return maskSecrets(raw);
    }
    return const JsonEncoder.withIndent('  ').convert(_walk(decoded));
  }

  Object? _walk(Object? node, [String? field]) {
    if (node is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in node.entries)
          '${e.key}': _walk(e.value, '${e.key}'),
      };
    }
    if (node is List) {
      return <Object?>[for (final Object? v in node) _walk(v, field)];
    }
    if (node is String && field != null) {
      if (_secretField.hasMatch(field)) return _masked(node);
      if (!revealPosition && _positionField.hasMatch(field)) {
        return _coarsened(node);
      }
    }
    return node;
  }

  /// Free text (a soak report, a captured log line): only whole hex runs that
  /// sit next to a secret word are touched, so a frame stays readable.
  String maskSecrets(String text) {
    return text.replaceAllMapped(
      RegExp(r'((?:psk|key|token|secret|pin|password)[^\n:]*[:=]\s*)([0-9a-fA-F]{16,})',
          caseSensitive: false),
      (Match m) => '${m.group(1)}${_masked(m.group(2)!)}',
    );
  }

  /// First four bytes, then the width: enough to tell two channels apart in a
  /// bug report, not enough to derive the key.
  String _masked(String value) {
    if (value.length <= 8) return _mask;
    return '${value.substring(0, 8)}$_mask${value.length}';
  }

  String _coarsened(String value) {
    final double? v = double.tryParse(value);
    if (v == null) return _mask;
    return v.toStringAsFixed(2);
  }
}
