// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';

/// Why a typed record was not accepted, before anything reached the radio.
///
/// The four are separate because the fix differs: nothing typed, something
/// that is not hex, something too small for `CMD_SEND_RAW_DATA`'s handler, or
/// something the contact's path leaves no room for. `MeshCarryLimits` is the
/// authority for the last two, so the message can name the real number.
enum RawRecordRefusal { empty, notHex, tooShort, tooLong }

/// A record decoded from typed hex, or the reason it was refused.
///
/// The tool that sends a raw record is a developer surface, and the one thing
/// it must not do is send a guess: a half-typed pair, a stray `0x`, or an
/// accidental 200 bytes would all reach the firmware as something the app did
/// not intend. So parsing is a value with a named refusal rather than a throw,
/// and [length] is reported even when the input is refused, because the byte
/// counter beside the field has to say what was typed.
final class RawRecordInput {
  const RawRecordInput._(this.length, {this.bytes, this.refusal});

  /// The bytes to send, or null when [refusal] is set.
  final Uint8List? bytes;

  /// Decoded byte count. Meaningful for a refusal too: "over budget" needs a
  /// number to be actionable.
  final int length;

  final RawRecordRefusal? refusal;

  bool get ok => bytes != null;

  @override
  String toString() => ok
      ? 'RawRecordInput($length bytes)'
      : 'RawRecordInput(refused: ${refusal!.name}, $length bytes)';
}

/// Decodes typed hex into a record, or names why it will not.
///
/// Accepts the two shapes a person actually types: space-separated pairs
/// (`01 02 ab`) and one continuous run (`0102ab`). Whitespace anywhere is
/// ignored, so a pasted capture with newlines works. Everything else is
/// [RawRecordRefusal.notHex] and nothing is sent, because "it looked close
/// enough" is how a malformed command reaches a radio.
RawRecordInput parseRawRecord(
  String text, {
  int maxBytes = MeshCarryLimits.maxFrameSize,
  int minBytes = MeshCarryLimits.rawDataMinPayload,
}) {
  final String compact = text.replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty) return const RawRecordInput._(0, refusal: RawRecordRefusal.empty);
  if (compact.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(compact)) {
    // An odd run cannot be pairs, and a non-hex character is not a byte with a
    // typo in it. Both are refused with the same sentence: fix the text.
    return RawRecordInput._(compact.length ~/ 2, refusal: RawRecordRefusal.notHex);
  }
  final int count = compact.length ~/ 2;
  final Uint8List bytes = Uint8List(count);
  for (int i = 0; i < count; i++) {
    bytes[i] = int.parse(compact.substring(i * 2, i * 2 + 2), radix: 16);
  }
  if (count < minBytes) {
    return RawRecordInput._(count, refusal: RawRecordRefusal.tooShort);
  }
  if (count > maxBytes) {
    return RawRecordInput._(count, refusal: RawRecordRefusal.tooLong);
  }
  return RawRecordInput._(count, bytes: bytes);
}
