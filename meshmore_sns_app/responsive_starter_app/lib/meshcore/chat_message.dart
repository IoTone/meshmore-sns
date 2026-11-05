// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

import 'failure.dart';

/// Delivery lifecycle of an **outgoing** message. Null on incoming
/// lines (not applicable). Drives the per-bubble status glyph.
///
/// - [sending]   — handed to the radio over BLE; awaiting the device's
///                 send confirmation (`RESP_CODE_SENT`).
/// - [sent]      — device accepted it and transmitted into the mesh.
///                 Terminal success for channel/broadcast messages
///                 (flood-routed → no recipient receipt exists).
/// - [delivered] — a direct message's recipient ACK arrived
///                 (`PUSH_CODE_ACK` matched our expectedAck tag).
/// - [failed]    — the BLE send threw, or a direct message saw no ACK
///                 within the device's estimated timeout (no path /
///                 recipient unreachable).
/// - [unknown]   — the app went away while the send was in flight. The
///                 in-flight tracking (the pending queue and the ack
///                 timers) does not survive a restart, so whether the
///                 radio transmitted it is not knowable: this row was
///                 `sending` when the process died. It is deliberately
///                 not [failed] — claiming a send failed when the app
///                 cannot know is worse than saying it does not know.
enum MessageDelivery { sending, sent, delivered, failed, unknown }

/// One line in the channel chat (R6). Incoming lines are decoded from
/// `ChannelMessageFrame`; outgoing lines are appended optimistically
/// when we send (the radio performs the OTA encryption).
class ChatMessage {
  ChatMessage({
    String? id,
    required this.channelIdx,
    required this.text,
    required this.outgoing,
    DateTime? at,
    this.snrDb,
    this.isFlood = false,
    this.peerPubKeyHex,
    this.delivery,
    this.expectedAck,
    this.failReason,
    this.failCause,
  })  : id = id ?? _genId(),
        at = at ?? DateTime.now();

  /// Monotonic-ish per-process id so per-message actions (R20:
  /// Reply / Copy / Delete) can target a specific row even across
  /// JSON round-trips. Persisted in `toJson`; restored in `fromJson`.
  final String id;

  static int _seq = 0;
  static String _genId() {
    final int t = DateTime.now().microsecondsSinceEpoch;
    _seq = (_seq + 1) & 0xFFFFFF;
    return '${t.toRadixString(36)}.${_seq.toRadixString(36)}';
  }

  final int channelIdx;
  final String text;

  /// For **DMs (1:1 P2P)**: the peer's pubkey hex (64 chars) when we
  /// can resolve it from the fabric, or the 12-hex pubkey prefix
  /// when only the prefix arrived (legacy `CONTACT_MSG_RECV` carries
  /// 6 bytes). Null for channel messages (use [channelIdx] then).
  final String? peerPubKeyHex;

  /// True = we sent it; false = received over the mesh.
  final bool outgoing;

  /// Local send/receive time (the OTA timestamp is sender-clock and
  /// not trustworthy for ordering).
  final DateTime at;

  /// Signal-to-noise of the inbound message, when the radio reported
  /// it (V3 channel frame only).
  final double? snrDb;

  /// True when the inbound message arrived via flood (path_len 0xFF).
  final bool isFlood;

  /// Delivery state of an outgoing message; null for incoming. Mutable
  /// because the state evolves *after* the row is created, as the
  /// device's send confirmation and the recipient ACK arrive.
  MessageDelivery? delivery;

  /// The `MsgSent.expectedAck` tag the device returned for this
  /// outgoing message, used to match a later `PUSH_CODE_ACK`. Null
  /// until the device confirms the send (or for incoming messages).
  int? expectedAck;

  /// Why an outgoing message ended `failed` or `unknown` (the device's ERR
  /// reason, or that no confirmation arrived). Null otherwise, and absent
  /// from rows persisted before this field existed.
  String? failReason;

  /// Why the row failed, as a cause rather than a sentence (APP-N2). A row
  /// written before the catalogue existed has only [failReason]; the retry
  /// sheet prefers this when both are present.
  FailureCause? failCause;

  /// Compact JSON for local persistence (history survives restarts —
  /// the companion protocol has no history-fetch; the device queue is
  /// drained destructively).
  Map<String, Object?> toJson() => <String, Object?>{
        'i': id,
        'c': channelIdx,
        't': text,
        'o': outgoing,
        'a': at.millisecondsSinceEpoch,
        if (snrDb != null) 's': snrDb,
        if (isFlood) 'f': true,
        if (peerPubKeyHex != null) 'p': peerPubKeyHex,
        if (delivery != null) 'd': delivery!.index,
        if (expectedAck != null) 'k': expectedAck,
        if (failReason != null) 'r': failReason,
        if (failCause != null) 'c': failCause!.name,
      };

  /// Reads a persisted cause name. An unknown name (a row written by a newer
  /// build) becomes null, so the row keeps its older sentence rather than
  /// showing a cause this build cannot translate.
  static FailureCause? _causeByName(String name) {
    for (final FailureCause c in FailureCause.values) {
      if (c.name == name) return c;
    }
    return null;
  }

  static ChatMessage fromJson(Map<String, Object?> j) {
    final int? dIdx = (j['d'] as num?)?.toInt();
    MessageDelivery? delivery =
        dIdx != null && dIdx >= 0 && dIdx < MessageDelivery.values.length
            ? MessageDelivery.values[dIdx]
            : null;
    // In-flight tracking (pending FIFO + ack timers) does not survive a
    // restart, so a persisted `sending` row would otherwise show a
    // permanent clock. It resolves to [MessageDelivery.unknown]: the
    // process died mid-send and nothing on the phone can say whether the
    // radio transmitted it. Calling that `failed` asserted an outcome the
    // app had no evidence for.
    String? reason = j['r'] as String?;
    if (delivery == MessageDelivery.sending) {
      delivery = MessageDelivery.unknown;
      reason ??= 'sent while the app closed; the radio’s answer is unknown';
    }
    return ChatMessage(
      id: j['i'] as String?,
      channelIdx: (j['c'] as num?)?.toInt() ?? 0,
      text: j['t'] as String? ?? '',
      outgoing: j['o'] as bool? ?? false,
      at: DateTime.fromMillisecondsSinceEpoch(
          (j['a'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
      snrDb: (j['s'] as num?)?.toDouble(),
      isFlood: j['f'] as bool? ?? false,
      peerPubKeyHex: j['p'] as String?,
      delivery: delivery,
      expectedAck: (j['k'] as num?)?.toInt(),
      failReason: reason,
      failCause: j['c'] is String ? _causeByName(j['c'] as String) : null,
    );
  }
}
