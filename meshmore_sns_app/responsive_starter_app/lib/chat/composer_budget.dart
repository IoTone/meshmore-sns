// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:meshcore/meshcore.dart';

/// How full the composer is, in the bytes the radio actually counts.
enum ComposerState {
  /// Room to spare.
  ok,

  /// At or past the point where the counter should say so once, before the
  /// radio's own limit is reached.
  near,

  /// The message cannot be sent as typed: the radio would cut it.
  over,
}

/// APP-D1/D2 — the composer's byte budget.
///
/// The firmware does not send the channel text it is given: `sendGroupMessage`
/// writes `"<sender_name>: "` into the same `MAX_TEXT_LEN` buffer and then
/// *silently* shortens the caller's text to fit
/// (`src/helpers/BaseChatMesh.cpp:488-496`). So the budget a sender may use is
/// `MAX_TEXT_LEN` (160 bytes, `ChannelTextLimits.maxTextBytes`) minus the bytes
/// of that prefix, which the radio derives from its own node name — not from
/// anything the app passes, and not a fixed 8 unless the name is unknown.
///
/// The text half of the count is delegated to [ChannelTextLimits.bytesOf], so
/// the composer and the encoder cannot disagree about a single message.
class ComposerBudget {
  const ComposerBudget({
    required this.prefixBytes,
    required this.prefixKnown,
  });

  /// The budget for a radio advertising [senderName].
  ///
  /// A radio that has not answered its self-info yet has no name, and the
  /// prefix cannot be guessed. Counting zero prefix bytes would be the worst
  /// guess, because the firmware still writes `"<name>: "`: it would let the
  /// composer accept text the radio then cuts. So an unknown name reserves
  /// [fallbackPrefixBytes], and [prefixKnown] stays false so the counter can
  /// say the number is an estimate.
  factory ComposerBudget.forSender(String? senderName) {
    final String? name = (senderName == null || senderName.isEmpty)
        ? null
        : senderName;
    if (name == null) {
      return const ComposerBudget(
        prefixBytes: fallbackPrefixBytes,
        prefixKnown: false,
      );
    }
    return ComposerBudget(
      prefixBytes: ChannelTextLimits.bytesOf('$name: '),
      prefixKnown: true,
    );
  }

  /// `"sender: "` — eight bytes, the length the app's SOS composer already
  /// reserves for a name it does not know (`lib/sos/sos_message.dart:21`).
  static const int fallbackPrefixBytes = 8;

  /// Bytes the radio will spend on `"<name>: "` before the text.
  final int prefixBytes;

  /// False when [prefixBytes] is the fallback rather than the radio's own name.
  final bool prefixKnown;

  /// The most text bytes a sender may use.
  int get maxTextBytes => ChannelTextLimits.maxTextBytes - prefixBytes;

  /// Budget state for [text] as typed.
  ComposerState stateFor(String text) {
    final int remaining = remainingFor(text);
    if (remaining < 0) return ComposerState.over;
    if (remaining <= nearBytes) return ComposerState.near;
    return ComposerState.ok;
  }

  /// Bytes of [text] that the radio will keep, prefix included.
  int usedFor(String text) =>
      prefixBytes + ChannelTextLimits.bytesOf(text);

  /// Bytes left before the radio would cut the message; negative when over.
  int remainingFor(String text) =>
      ChannelTextLimits.maxTextBytes - usedFor(text);

  /// Whether the composer may send [text] as typed.
  bool canSend(String text) =>
      text.trim().isNotEmpty && stateFor(text) != ComposerState.over;

  /// How far over the limit [text] is, for the refusal copy.
  int overBy(String text) {
    final int remaining = remainingFor(text);
    return remaining < 0 ? -remaining : 0;
  }

  /// The counter warns once inside this many remaining bytes. Chosen so the
  /// warning arrives while there is still room to finish a clause, not when
  /// the next keystroke is refused.
  static const int nearBytes = 20;
}
