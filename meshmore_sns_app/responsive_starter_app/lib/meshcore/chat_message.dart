// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import '../chat/reactions.dart';
import '../media/mp1.dart';
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
/// - [failed]    — the BLE send threw, the radio refused it with an
///                 explicit `ERR`, or a direct message saw no ACK after the
///                 device's estimate and the 30 s grace that follows it.
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
    this.mp1,
    this.hidden = false,
    Map<String, List<String?>>? reactions,
    Set<String>? ownReactions,
  })  : id = id ?? _genId(),
        reactions = reactions ?? <String, List<String?>>{},
        ownReactions = ownReactions ?? <String>{},
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
  String text;

  /// True for a row that is bookkeeping rather than a message.
  ///
  /// A reaction goes out as a text line in MeshCore One's grammar, so sending
  /// one wrote an ordinary row containing `@[name]🙂\n<hash>`: the reactor's own
  /// thread showed the wire format as chat text. The row still exists, because
  /// it is how the ledger attributes the radio's acknowledgement to what was
  /// sent, and because the reaction itself is folded into the message it names.
  /// It is simply not a line a reader should see.
  final bool hidden;

  /// The MP1 preview this row carries, as the channel datagram it arrived in.
  ///
  /// A preview is not chat text: it arrives as one channel datagram
  /// (`0xFF50`), so without this the picture would exist only in the strip above
  /// the composer, away from the moment it arrived. The packed bytes are kept
  /// rather than the decoded pixels: 163 bytes at most, and the palette grid is
  /// a pure function of them, so a restart costs a decode rather than a cache.
  final Uint8List? mp1;

  /// The preview, decoded once per row.
  Mp1Image? get mp1Image {
    if (_mp1Image != null || _mp1Tried) return _mp1Image;
    _mp1Tried = true;
    final Uint8List? bytes = mp1;
    if (bytes == null) return null;
    return _mp1Image = decodeMp1Preview(bytes).image;
  }

  Mp1Image? _mp1Image;
  bool _mp1Tried = false;

  /// Reactions on this message: emoji to the senders who chose it.
  ///
  /// A reaction is a text line naming another message by hash, so it is folded
  /// into the message it names rather than appended to the thread. The sender
  /// is null for a channel reaction that named nobody and for MeshCore Open's
  /// shorthand, which does not carry one.
  final Map<String, List<String?>> reactions;

  /// The emoji this app has sent on this message.
  ///
  /// [reactions] cannot answer that question: a channel reaction carries no key,
  /// so the folded list holds a name or nothing, and a DM reaction carries no
  /// sender at all. Reacting is a gesture rather than a message, so a second tap
  /// on the same emoji must not put a second line on the air — and that has to
  /// survive a restart, which a name match against [reactions] cannot promise
  /// when our own name is absent from it.
  final Set<String> ownReactions;

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
        // `x`, not `c`. This was `'c': failCause!.name` in the same map literal
        // that already writes `'c': channelIdx`, so a row with a typed failure
        // persisted its cause *over* its channel and no channel at all. On the
        // next launch `fromJson` read a String where it wanted a number, threw,
        // and `ChatStore`'s catch turned that into an empty history — one failed
        // send plus one restart discarded every message the app had kept.
        //
        // `fromJson` still reads a legacy `c` that is a String, because a build
        // in the field has written rows in that shape and they are recoverable:
        // the channel is 0 in that case, which is where a failed send on the
        // public channel belongs.
        if (failCause != null) 'x': failCause!.name,
        // `m` for the MP1 preview. Base64 rather than a byte list: the row is
        // written on every message, and 163 numbers is five times the payload.
        if (mp1 != null) 'm': base64Encode(mp1!),
        if (hidden) 'h': true,
        if (reactions.isNotEmpty)
          'e': <String, List<String?>>{
            for (final MapEntry<String, List<String?>> e in reactions.entries)
              e.key: e.value,
          },
        // `or`: what this app reacted with, kept apart from `e` because the
        // folded map cannot say who is who.
        if (ownReactions.isNotEmpty) 'or': ownReactions.toList(),
      };

  static Uint8List? _tryBase64(String value) {
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

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
      // A row written by the legacy `'c': failCause` shape has no numeric
      // channel; public (0) is where a send that failed on the public channel
      // belongs, and it is the only channel that shape could have truncated to.
      // Tolerant on purpose: a legacy row put the failure cause (a String) in
      // this key, and a cast here threw away the whole history on restore.
      channelIdx: switch (j['c']) {
        final num n => n.toInt(),
        _ => 0,
      },
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
      // A preview saved by a build that wrote it, read by one that can draw it.
      // A body that will not decode is dropped rather than throwing: one bad row
      // must not cost the history it lives in.
      mp1: switch (j['m']) {
        final String b64 => _tryBase64(b64),
        _ => null,
      },
      // A row written before this build marked reactions was stored as ordinary
      // chat, so its text is the wire line. The parser is the same one the
      // inbound path uses, so an old row is recognised on the way in rather than
      // left in the thread as `@[name]🙂\n<hash>`.
      hidden: j['h'] == true ||
          Reactions.parse((j['t'] as String? ?? '').trim()) != null,
      ownReactions: switch (j['or']) {
        final List<Object?> l => <String>{
            for (final Object? e in l)
              if (e is String) e,
          },
        _ => null,
      },
      reactions: switch (j['e']) {
        final Map<Object?, Object?> m => <String, List<String?>>{
            for (final MapEntry<Object?, Object?> e in m.entries)
              if (e.key is String && e.value is List)
                e.key! as String: <String?>[
                  for (final Object? who in e.value! as List)
                    who is String ? who : null,
                ],
          },
        _ => null,
      },
      // `x` is the current key; a legacy row has the cause in `c` and no channel
      // index, which is why the channel above falls back to 0.
      failCause: switch (j['x'] ?? j['c']) {
        final String name => _causeByName(name),
        _ => null,
      },
    );
  }
}
