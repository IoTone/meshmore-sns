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
///    only the copy and export paths coarsen. A coordinate reaches a capture
///    under several names (`latE6`, `position`, a `lat=` inside a soak line),
///    so the field set is the union of the spellings the app actually writes
///    rather than the two obvious ones.
///
/// Masking is by field name, not by guessing at hex length: a 32-byte
/// ciphertext and a 32-byte key look identical, and guessing wrong would
/// either leak a key or destroy the evidence.
///
/// The raw frame log needs one extra rule, because a frame has no field
/// names: `CHANNEL_INFO` (0x12) carries the channel secret verbatim after a
/// 32-byte name, so that tail is replaced with its width. Every other frame
/// is left byte-for-byte, which is what makes the log replayable.
class DiagnosticsRedaction {
  const DiagnosticsRedaction({this.revealPosition = false});

  /// Coordinates a person has asked to see in full. Off by default; the
  /// screen never sets it, so a shared capture cannot carry a fix.
  final bool revealPosition;

  static const String _mask = '…';

  static final RegExp _secretField =
      RegExp(r'(psk|key|token|secret|pin|password)', caseSensitive: false);

  /// Every spelling a position reaches a capture under. `position`, `location`
  /// and `fix` are the words the soak and place paths use; `alt` and `elev`
  /// are an altitude, which is a position fact even though it is one number.
  static final RegExp _positionField = RegExp(
      r'^(lat|lon|lng|latitude|longitude|coord|coords|coordinate|coordinates|'
      r'late6|lone6|alt|altitude|elev|elevation|position|location|fix)$',
      caseSensitive: false);

  /// Fields whose value is a coordinate scaled by 10^6 rather than degrees.
  static final RegExp _scaledCoordinateField =
      RegExp(r'^(late6|lone6)$', caseSensitive: false);

  /// Fields that hold a distance above the ground rather than a latitude or a
  /// longitude: coarsened to whole metres, never to two decimal places.
  static final RegExp _altitudeField =
      RegExp(r'^(alt|altitude|elev|elevation)$', caseSensitive: false);

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
        return _coarsened(node, field);
      }
    }
    // A coordinate is usually a number, and a PIN is an int on the wire: both
    // have to be caught here or the JSON form leaks what the string form
    // masks. Found while wiring the issue link, which pastes a capture into a
    // public tracker.
    if (node is num && field != null) {
      if (_secretField.hasMatch(field)) return _mask;
      if (!revealPosition && _positionField.hasMatch(field)) {
        final double v = _scaledCoordinateField.hasMatch(field)
            ? node.toDouble() / 1e6
            : node.toDouble();
        if (_altitudeField.hasMatch(field)) return v.round();
        return double.parse(v.toStringAsFixed(2));
      }
    }
    return node;
  }

  /// Free text (a soak report, a captured log line): whole hex runs that sit
  /// next to a secret word are masked, and a coordinate written as `lat=…`
  /// (the shape a soak line uses) is coarsened in place, so a frame stays
  /// readable and a fix does not travel.
  String maskSecrets(String text) {
    String out = text.replaceAllMapped(
      RegExp(r'((?:psk|key|token|secret|pin|password)[^\n:]*[:=]\s*)([0-9a-fA-F]{16,})',
          caseSensitive: false),
      (Match m) => '${m.group(1)}${_masked(m.group(2)!)}',
    );
    if (revealPosition) return out;
    return out.replaceAllMapped(
      RegExp(r'\b(latE6|lonE6|lat|lon)\b(\s*[:=]\s*)(-?\d+(?:\.\d+)?)',
          caseSensitive: false),
      (Match m) => '${m.group(1)}${m.group(2)}'
          '${_coarsened(m.group(3)!, m.group(1))}',
    );
  }

  /// One captured frame, hex, with the channel secret of a `CHANNEL_INFO`
  /// replaced.
  ///
  /// A frame has no field names, so the rule is positional: opcode `0x12`,
  /// then the channel index and a fixed 32-byte name, then the secret whose
  /// width is whatever is left (16 on mainline, 32 where the firmware answers
  /// the full width). The secret is replaced with its width so the capture
  /// still shows that a channel info frame arrived and for which slot.
  String frame(String hex) {
    final String normalised = hex.toLowerCase();
    if (!normalised.startsWith('12')) return hex;
    const int headerBytes = 1 + 1 + 32; // opcode, index, fixed name
    if (normalised.length <= headerBytes * 2) return hex;
    final int secretHalfBytes = normalised.length ~/ 2 - headerBytes;
    return '${normalised.substring(0, headerBytes * 2)}'
        '$_mask${secretHalfBytes}_bytes';
  }

  /// The copy path: every captured frame, with any channel secret masked.
  List<String> frames(Iterable<String> captured) =>
      <String>[for (final String h in captured) frame(h)];

  /// First four bytes, then the width: enough to tell two channels apart in a
  /// bug report, not enough to derive the key.
  String _masked(String value) {
    if (value.length <= 8) return _mask;
    return '${value.substring(0, 8)}$_mask${value.length}';
  }

  String _coarsened(String value, [String? field]) {
    double? v = double.tryParse(value);
    if (v == null) return _mask;
    if (field != null && _scaledCoordinateField.hasMatch(field)) v /= 1e6;
    if (field != null && _altitudeField.hasMatch(field)) return '${v.round()}';
    return v.toStringAsFixed(2);
  }
}
