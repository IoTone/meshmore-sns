// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'constants.dart';

/// Why a text message was refused before it reached the radio.
///
/// The firmware truncates an over-long text to `MAX_TEXT_LEN` bytes without
/// saying so (`BaseChatMesh.cpp` writes `text_len = min(len, MAX_TEXT_LEN)` in
/// the receive path), so a caller that sends one gets a message the peer shows
/// cut in half and no error at all. Refusing here keeps the reason and names
/// the length that was over.
enum ChannelTextRefusal {
  /// The UTF-8 text is longer than [ChannelTextLimits.maxTextBytes].
  textTooLong,
}

/// The byte budget for `CMD_SEND_CHANNEL_TXT_MSG` (`0x03`) and the frame cap
/// every send shares.
///
/// `MAX_TEXT_LEN` is `10 * CIPHER_BLOCK_SIZE` = 160 bytes
/// (`src/helpers/BaseChatMesh.h:8`). The firmware's own comment on it says the
/// text must be *less than* `MAX_PACKET_PAYLOAD - 4 - CIPHER_MAC_SIZE - 1` =
/// 177, the room one queued packet leaves once its header, cipher MAC and type
/// byte are paid for. So 160 is the budget a caller may use and 177 is the
/// hard slot it must stay under — the slot is a bound, not a target.
///
/// The budget is in **bytes**, not characters: the firmware compares the
/// encoded length, and the sender prefix the app adds (`name: `) is part of the
/// 160. A Japanese message therefore has fewer characters than 160.
abstract final class ChannelTextLimits {
  /// `MAX_TEXT_LEN`, `src/helpers/BaseChatMesh.h:8`.
  static const int maxTextBytes = 160;

  /// `MAX_PACKET_PAYLOAD - 4 - CIPHER_MAC_SIZE - 1` (`src/MeshCore.h:20`,
  /// `BaseChatMesh.h:8`): the room one queued packet leaves for text. Text
  /// must stay below this, and [maxTextBytes] does.
  static const int queueSlotBytes = 177;

  /// Bytes the whole send frame may occupy: `MAX_FRAME_SIZE`,
  /// `src/MeshCore.h:20` / `src/helpers/BaseSerialInterface.h:5`.
  static const int maxFrameBytes = MeshcoreBle.maxFrameSize;

  /// UTF-8 length of [text], which is what the firmware measures.
  static int bytesOf(String text) => _utf8Length(text);

  static int _utf8Length(String s) {
    int n = 0;
    for (final int rune in s.runes) {
      n += rune < 0x80
          ? 1
          : rune < 0x800
              ? 2
              : rune < 0x10000
                  ? 3
                  : 4;
    }
    return n;
  }
}

/// A text send refused before the radio saw it.
class ChannelTextException implements Exception {
  const ChannelTextException(
    this.refusal, {
    required this.actual,
    required this.maximum,
  });

  final ChannelTextRefusal refusal;
  final int actual;
  final int maximum;

  @override
  String toString() =>
      'ChannelTextException(${refusal.name}: $actual bytes, maximum $maximum)';
}

/// A frame refused because it cannot cross the link as one unit.
class FrameLengthException implements Exception {
  const FrameLengthException({required this.actual, required this.maximum});

  final int actual;
  final int maximum;

  @override
  String toString() => 'FrameLengthException($actual bytes, maximum $maximum)';
}
