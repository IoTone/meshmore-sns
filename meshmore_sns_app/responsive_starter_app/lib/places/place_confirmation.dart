// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';

/// Confirmations and refutations of a place report
/// (`meshmore-places-spec.md` §11, decision D8.25).
///
/// Two reply tags, the same shape as the other reply tags in the app:
///
/// ```
/// [CONFIRM:<id8>] <callsign>
/// [REFUTE:<id8>]  <callsign>
/// ```
///
/// The callsign is repeated so a listener who missed the original still reads
/// something. Neither tag is a new payload type: both are ordinary channel
/// text, which is why they work through any number of hops on any client.
///
/// A confirmation is **weight, not renewal**: it never moves a place's expiry.
/// Only the reporter's own deliberate renewal does that, because a stranger
/// who could extend a pin could keep a wrong one alive.

enum PlaceReplyKind {
  confirm('CONFIRM'),
  refute('REFUTE');

  const PlaceReplyKind(this.tag);

  final String tag;
}

/// What the app actually knows about who replied (spec §11).
///
/// A direct message is authenticated by the packet's key; channel text carries
/// a display name and nothing more, so it is counted separately and shown as
/// "claimed".
enum PlaceReplyAttribution { keyBound, claimed }

enum PlaceReplyFailure {
  /// No `[CONFIRM:` / `[REFUTE:` tag at the start.
  notAReply,

  /// The id is not eight hex characters.
  badId,

  /// Neither the text nor the surrounding message names a sender.
  emptyCallsign,
}

/// One parsed reply.
@immutable
final class PlaceReply {
  const PlaceReply({
    required this.kind,
    required this.id8,
    required this.callsign,
    required this.attribution,
    this.reporterKeyHex,
  });

  final PlaceReplyKind kind;

  /// Lowercase eight hex characters, the place's id.
  final String id8;

  final String callsign;
  final PlaceReplyAttribution attribution;

  /// The replying peer's key. Present exactly when [attribution] is
  /// [PlaceReplyAttribution.keyBound].
  final String? reporterKeyHex;

  @override
  bool operator ==(Object other) =>
      other is PlaceReply &&
      other.kind == kind &&
      other.id8 == id8 &&
      other.callsign == callsign &&
      other.attribution == attribution &&
      other.reporterKeyHex == reporterKeyHex;

  @override
  int get hashCode =>
      Object.hash(kind, id8, callsign, attribution, reporterKeyHex);
}

@immutable
final class PlaceReplyOutcome {
  const PlaceReplyOutcome.reply(PlaceReply this.reply) : failure = null;

  const PlaceReplyOutcome.rejected(PlaceReplyFailure this.failure)
      : reply = null;

  final PlaceReply? reply;
  final PlaceReplyFailure? failure;

  bool get isReply => reply != null;
}

/// Reads a reply tag out of one message.
///
/// [senderName] is the name the surrounding message carries; it is used when
/// the text itself has no callsign after the tag. [reporterKeyHex] decides the
/// attribution: pass it for a direct message and leave it null for a channel.
PlaceReplyOutcome parsePlaceReply(
  String text, {
  String senderName = '',
  String? reporterKeyHex,
}) {
  final String trimmed = text.trim();
  PlaceReplyKind? kind;
  for (final PlaceReplyKind k in PlaceReplyKind.values) {
    if (trimmed.startsWith('[${k.tag}:')) {
      kind = k;
      break;
    }
  }
  if (kind == null) {
    return const PlaceReplyOutcome.rejected(PlaceReplyFailure.notAReply);
  }
  final int close = trimmed.indexOf(']');
  if (close < 0) {
    return const PlaceReplyOutcome.rejected(PlaceReplyFailure.badId);
  }
  final String id = trimmed.substring(kind.tag.length + 2, close).trim();
  if (!_isId8(id)) {
    return const PlaceReplyOutcome.rejected(PlaceReplyFailure.badId);
  }
  final String tail = trimmed.substring(close + 1).trim();
  final String callsign = tail.isEmpty ? senderName.trim() : tail;
  if (callsign.isEmpty) {
    return const PlaceReplyOutcome.rejected(PlaceReplyFailure.emptyCallsign);
  }
  return PlaceReplyOutcome.reply(PlaceReply(
    kind: kind,
    id8: id.toLowerCase(),
    callsign: callsign,
    attribution: reporterKeyHex == null
        ? PlaceReplyAttribution.claimed
        : PlaceReplyAttribution.keyBound,
    reporterKeyHex: reporterKeyHex,
  ));
}

/// The wire spelling of [reply].
String encodePlaceReply(PlaceReply reply) =>
    '[${reply.kind.tag}:${reply.id8}] ${reply.callsign}';

bool _isId8(String id) {
  if (id.length != 8) return false;
  for (int i = 0; i < 8; i++) {
    final int c = id.codeUnitAt(i);
    final bool hex = (c >= 0x30 && c <= 0x39) ||
        (c >= 0x61 && c <= 0x66) ||
        (c >= 0x41 && c <= 0x46);
    if (!hex) return false;
  }
  return true;
}

/// What a pin shows about its replies (spec §11 rules 1–5).
@immutable
final class PlaceConfirmationSummary {
  const PlaceConfirmationSummary({
    required this.confirming,
    required this.claimedConfirming,
    required this.refuting,
    required this.claimedRefuting,
    required this.hidden,
  });

  final int confirming;
  final int claimedConfirming;
  final int refuting;
  final int claimedRefuting;

  /// A key-bound refutation hides the pin on this device. A claimed one only
  /// adds weight, and neither can delete another reporter's row.
  final bool hidden;

  int get totalConfirming => confirming + claimedConfirming;

  /// Five at most: "5 confirmations + 12 more" persuades as much as twelve and
  /// stays readable.
  int get shown => totalConfirming > 5 ? 5 : totalConfirming;

  int get more => totalConfirming - shown;
}

/// The replies this device has seen, one vote per identity per place.
///
/// Identity is the peer's key when the reply was key-bound and the normalised
/// callsign otherwise; a repeat from the same identity updates its timestamp
/// and does not add a count. A blocked key's reply neither counts nor appears.
final class PlaceConfirmationTally {
  final Map<String, Map<String, _Vote>> _byPlace = <String, Map<String, _Vote>>{};

  /// Records [reply]. Returns false when it changed nothing (a repeat from the
  /// same identity with the same kind).
  bool record(
    PlaceReply reply, {
    required DateTime at,
    bool Function(String reporterKeyHex)? isBlocked,
  }) {
    final String? key = reply.reporterKeyHex;
    if (key != null && isBlocked != null && isBlocked(key)) return false;

    final Map<String, _Vote> votes =
        _byPlace.putIfAbsent(reply.id8, () => <String, _Vote>{});
    final String identity = key != null
        ? 'key:${key.toLowerCase()}'
        : 'name:${reply.callsign.trim().toLowerCase()}';
    final _Vote? previous = votes[identity];
    if (previous != null && previous.kind == reply.kind) {
      previous.at = at;
      return false;
    }
    votes[identity] = _Vote(reply.kind, at);
    return true;
  }

  PlaceConfirmationSummary summaryFor(String id8) {
    final Map<String, _Vote> votes = _byPlace[id8] ?? const <String, _Vote>{};
    int confirming = 0;
    int claimedConfirming = 0;
    int refuting = 0;
    int claimedRefuting = 0;
    bool hidden = false;
    votes.forEach((String identity, _Vote vote) {
      final bool keyBound = identity.startsWith('key:');
      if (vote.kind == PlaceReplyKind.confirm) {
        if (keyBound) {
          confirming++;
        } else {
          claimedConfirming++;
        }
      } else if (keyBound) {
        refuting++;
        hidden = true;
      } else {
        claimedRefuting++;
      }
    });
    return PlaceConfirmationSummary(
      confirming: confirming,
      claimedConfirming: claimedConfirming,
      refuting: refuting,
      claimedRefuting: claimedRefuting,
      hidden: hidden,
    );
  }

  /// Forgets one place (its expiry, or the block of every reporter).
  void forget(String id8) => _byPlace.remove(id8);

  void clear() => _byPlace.clear();
}

final class _Vote {
  _Vote(this.kind, this.at);

  final PlaceReplyKind kind;

  /// When this identity last said it. A repeat moves the time, not the count.
  DateTime at;
}
