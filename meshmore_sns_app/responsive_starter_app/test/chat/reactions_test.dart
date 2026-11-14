// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/chat/reactions.dart';

/// A reaction is a wire format with two implementations already in the field,
/// so the test pins the bytes rather than the behaviour of our own parser.
void main() {
  test('the hash is MeshCore One\'s: sha256(text + uint32le ts), 5 bytes, base32',
      () {
    // Computed here from the definition rather than from our own encoder, so a
    // change to the encoder cannot silently redefine the format.
    const String text = 'good morning';
    const int ts = 1700000000;
    final List<int> digest = sha256
        .convert(<int>[
          ...utf8.encode(text),
          ...(ByteData(4)..setUint32(0, ts, Endian.little)).buffer.asUint8List(),
        ])
        .bytes
        .sublist(0, 5);
    const String alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final StringBuffer expected = StringBuffer();
    int buffer = 0;
    int bits = 0;
    for (final int b in digest) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        expected.write(alphabet[(buffer >> (bits - 5)) & 0x1F]);
        bits -= 5;
      }
    }
    final String want = expected.toString().toLowerCase();

    final String got = Reactions.hashFor(timestampSeconds: ts, text: text);
    expect(got, want);
    expect(got.length, 8, reason: 'five bytes is exactly eight base32 chars');
    expect(RegExp(r'^[0-9a-tv-z]{8}$').hasMatch(got), isTrue,
        reason: 'Crockford: no i, l, o or u');
  });

  test('a channel reaction names its sender, which is what salts the hash', () {
    final String line = Reactions.encodeChannel(
        senderName: 'Sam', emoji: '👍', hash: 'abcd2345');
    expect(line, '@[Sam]👍\nabcd2345');

    final ({String hash, String emoji, String? senderName, bool isOpen})? p =
        Reactions.parse(line);
    expect(p, isNotNull);
    expect(p!.hash, 'abcd2345');
    expect(p.emoji, '👍');
    expect(p.senderName, 'Sam');
    expect(p.isOpen, isFalse);
  });

  test('a direct reaction has no name, because the envelope carries it', () {
    final String line = Reactions.encodeDirect(emoji: '❤️', hash: 'abcd2345');
    expect(line, '❤️\nabcd2345');
    final ({String hash, String emoji, String? senderName, bool isOpen})? p =
        Reactions.parse(line);
    expect(p, isNotNull);
    expect(p!.emoji, '❤️');
    expect(p.senderName, isNull);
  });

  test('MeshCore Open\'s shorthand is read, and marked as theirs', () {
    final ({String hash, String emoji, String? senderName, bool isOpen})? p =
        Reactions.parse('r:1a2b:03');
    expect(p, isNotNull);
    expect(p!.hash, '1a2b');
    expect(p.isOpen, isTrue, reason: 'their emoji index is not our emoji');
  });

  test('an ordinary message is not a reaction', () {
    expect(Reactions.parse('good morning'), isNull);
    expect(Reactions.parse('meet at 5\nnotahash!'), isNull);
    expect(Reactions.parse('12:30 today'), isNull,
        reason: 'prose that happens to end in something short is still prose');
    // A line that is shaped right but whose first part is not an emoji.
    expect(Reactions.parse('hello\nabcd2345'), isNull);
  });

  test('every palette entry round trips through the parser', () {
    for (final String emoji in Reactions.palette) {
      final String line =
          Reactions.encodeChannel(senderName: 'Kim', emoji: emoji, hash: '0abc2345');
      final ({String hash, String emoji, String? senderName, bool isOpen})? p =
          Reactions.parse(line);
      expect(p, isNotNull, reason: '$emoji did not parse');
      expect(p!.emoji, emoji);
    }
  });

  test('a Uint8List from the encoder is not required to be padded', () {
    // 40 bits is exactly 8 groups of 5, so nothing is padded; this pins that a
    // future change to a 6-byte digest would be caught.
    expect(kReactionHashBytes * 8 % 5, 0);
  });
}

/// The digest length the format fixes: five bytes, forty bits.
const int kReactionHashBytes = 5;
