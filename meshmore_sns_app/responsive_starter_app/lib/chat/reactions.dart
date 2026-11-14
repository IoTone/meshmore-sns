// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Reactions, in the format the other clients already speak.
///
/// There is no reaction opcode in the companion protocol, so a reaction is a
/// text message whose whole body is a reference to another message. Two formats
/// exist in the wild:
///
/// - **MeshCore One's**, documented at `MeshCoreOne/docs/Reactions.md` and
///   parsed by MeshCore Open as `parseReactionMC1`. The body is the emoji, a
///   newline, and an eight-character Crockford-base32 hash of the target. In a
///   channel it also names the sender, because a channel message carries no key
///   and the hash is salted with the sender's name.
/// - **MeshCore Open's own** `r:<hash4>:<emojiIndex>`, which nothing else reads.
///
/// This app writes MeshCore One's format and reads both, because one of them is
/// a documented convention two clients implement and the other is one client's
/// private shorthand. A reader who is not running a client that understands
/// reactions sees a short line with an emoji and a code, which is what a stock
/// MeshCore user sees today anyway.
///
/// The hash is `SHA-256(utf8(text) + uint32le(timestampSeconds))`, first five
/// bytes, encoded as Crockford base32 and lowercased. Eight characters carry
/// exactly forty bits, so nothing is padded.
abstract final class Reactions {
  /// Crockford base32: no I, L, O or U, so a reader cannot confuse 1, 0 or a
  /// vowel for a digit.
  static const String _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// The reaction palette. A fixed set, not a picker: a reaction is a gesture,
  /// and eight choices is what fits a long-press menu on a 320 dp phone.
  static const List<String> palette = <String>[
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏',
    '🔥',
    '✅',
  ];

  /// The hash that names one message: `SHA-256(text + uint32le(ts))`, first
  /// five bytes, base32.
  ///
  /// The sender is *not* in the digest. MeshCore One carries the sender's name
  /// beside the hash in a channel (`@[name]emoji\nhash`) and compares the pair,
  /// so the same text sent at the same second by two people has one hash and
  /// two reactions that do not collide. That is why [parse] returns the name.
  static String hashFor({
    required int timestampSeconds,
    required String text,
  }) {
    final BytesBuilder b = BytesBuilder(copy: false)
      ..add(utf8.encode(text))
      ..add((ByteData(4)..setUint32(0, timestampSeconds, Endian.little))
          .buffer
          .asUint8List());
    final List<int> digest = sha256.convert(b.takeBytes()).bytes.sublist(0, 5);
    return _base32(digest);
  }

  /// A channel reaction: `@[name]emoji\nhash`.
  static String encodeChannel({
    required String senderName,
    required String emoji,
    required String hash,
  }) =>
      '@[$senderName]$emoji\n$hash';

  /// A direct-message reaction: `emoji\nhash`, with the sender implicit.
  static String encodeDirect({required String emoji, required String hash}) =>
      '$emoji\n$hash';

  /// A parsed reaction: which message it names, what it says, and who said it
  /// when the line named them.
  static ({String hash, String emoji, String? senderName, bool isOpen})? parse(
      String text) {
    // MeshCore One, channel form.
    final RegExpMatch? channel = RegExp(r'^@\[(.+?)](.+?)\n([0-9a-tv-zA-TV-Z]{8})$')
        .firstMatch(text.trim());
    if (channel != null && _isEmoji(channel.group(2)!)) {
      return (
        hash: channel.group(3)!.toLowerCase(),
        emoji: channel.group(2)!,
        senderName: channel.group(1),
        isOpen: false,
      );
    }
    // MeshCore One, direct form (and its legacy ordering).
    final RegExpMatch? direct =
        RegExp(r'^(.+?)\n([0-9a-tv-zA-TV-Z]{8})$').firstMatch(text.trim());
    if (direct != null && _isEmoji(direct.group(1)!)) {
      return (
        hash: direct.group(2)!.toLowerCase(),
        emoji: direct.group(1)!,
        senderName: null,
        isOpen: false,
      );
    }
    // MeshCore Open's own shorthand, read so their users' reactions land here
    // too. The emoji is an index into their palette, which this build does not
    // carry, so it is recorded as a neutral marker rather than a wrong face.
    final RegExpMatch? open =
        RegExp(r'^r:([0-9a-f]{4}):([0-9a-f]{2})$').firstMatch(text.trim());
    if (open != null) {
      return (hash: open.group(1)!, emoji: '•', senderName: null, isOpen: true);
    }
    return null;
  }

  /// Whether [emoji] is one grapheme that looks like an emoji rather than prose.
  ///
  /// The test is the one MeshCore Open uses: nearly every emoji starts at
  /// U+2000 or above, and the exceptions (keycaps, © and ®) carry a variation
  /// selector or a combining keycap. Ordinary text fails both, which is what
  /// keeps an ordinary one-line message from being read as a reaction.
  static bool _isEmoji(String emoji) {
    if (emoji.isEmpty) return false;
    final int first = emoji.runes.first;
    final bool high = first >= 0x2000;
    final bool carrying = emoji.runes.any((int r) => r == 0xFE0F || r == 0x20E3);
    return high || carrying;
  }

  static String _base32(List<int> bytes) {
    final StringBuffer out = StringBuffer();
    int buffer = 0;
    int bits = 0;
    for (final int b in bytes) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        out.write(_crockford[(buffer >> (bits - 5)) & 0x1F]);
        bits -= 5;
      }
    }
    if (bits > 0) {
      out.write(_crockford[(buffer << (5 - bits)) & 0x1F]);
    }
    return out.toString().toLowerCase();
  }
}
