// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import '../meshcore/chat_message.dart';
import '../meshcore/meshcore_controller.dart';
import 'place.dart';
import 'place_codec.dart';
import 'place_confirmation.dart';
import 'place_id.dart';
import 'place_report_budget.dart';
import 'place_store.dart';

/// Who is reporting, and the one call that puts a line on the air.
///
/// A place is ordinary channel text (`meshmore-places-spec.md` §3), so the
/// send path is the channel text path: no new frame, no new payload type, and
/// the radio performs the encryption as it does for any other message. The
/// interface exists so the composer and its tests never need a controller.
abstract interface class PlaceSender {
  /// The name this node reports under. Channel text carries it, so it is the
  /// identity an unkeyed place is derived from.
  String get reporterName;

  /// Our own 32-byte key when the radio has answered with one, so a place this
  /// device reports is keyed even though it travels as channel text.
  Uint8List? get reporterKey;

  /// Puts the line on the air. Returns false when the radio did not take it,
  /// which is not the same as "nobody heard it": a channel send is a broadcast
  /// and the only answer is the radio's own OK.
  Future<bool> sendPlaceText(String text);
}

/// [PlaceSender] over the app's live controller.
final class ChannelPlaceSender implements PlaceSender {
  ChannelPlaceSender(this._controller, {this.channelIdx});

  final MeshcoreController _controller;

  /// The channel the report goes out on; null means the active one.
  final int? channelIdx;

  @override
  String get reporterName => _controller.selfInfo?.name ?? '';

  @override
  Uint8List? get reporterKey => _controller.selfInfo?.publicKey;

  @override
  Future<bool> sendPlaceText(String text) async {
    final int idx = channelIdx ?? _controller.activeChannel;
    final ChatMessage? row = await _controller.sendChannelTextTo(idx, text);
    // A null row means nothing was sent (not ready). A row marked failed means
    // the radio refused it, or the airtime budget did. Either way the place did
    // not go out, and the composer must not say it did.
    return row != null && row.delivery != MessageDelivery.failed;
  }
}

/// Why a report did not go out.
enum PlaceComposeRefusal {
  /// The label is empty, too long, or carries a `[TTL:` token.
  label,

  /// The 6-per-hour / burst-2 budget is spent; [PlaceComposeResult.allowedAt]
  /// says when the next one may go.
  budget,

  /// The coordinates are not a place the codec can write.
  coordinates,

  /// No radio identity yet, so the place would not know who reported it.
  identity,

  /// The radio did not take the line: not connected, a refused capability, or
  /// the airtime budget. The place is not on the air.
  radio,
}

/// What the composer did.
final class PlaceComposeResult {
  const PlaceComposeResult.sent(Place this.place)
      : refusal = null,
        allowedAt = null,
        labelProblem = null;

  const PlaceComposeResult.refused(
    PlaceComposeRefusal this.refusal, {
    this.allowedAt,
    this.labelProblem,
  }) : place = null;

  final Place? place;
  final PlaceComposeRefusal? refusal;

  /// Set when [refusal] is [PlaceComposeRefusal.budget].
  final DateTime? allowedAt;

  /// Set when [refusal] is [PlaceComposeRefusal.label] and the label is the
  /// reason the codec would give.
  final PlaceLabelProblem? labelProblem;

  bool get sent => place != null;
}

/// Builds a report, spends the budget, sends it, and stores it as our own row.
///
/// Order matters: the id is computed from the digits that will actually
/// travel, and snapping happens **before** the id (spec §9) so a receiver
/// computes the same id. The budget is consulted last but charged only when
/// the frame is about to go, and never silently: a refusal carries the moment
/// the next report is allowed.
final class PlaceComposer {
  PlaceComposer({
    required PlaceStore store,
    required PlaceReportBudget budget,
    required PlaceSender sender,
    DateTime Function()? clock,
  })  : _store = store,
        _budget = budget,
        _sender = sender,
        _clock = clock ?? DateTime.now;

  final PlaceStore _store;
  final PlaceReportBudget _budget;
  final PlaceSender _sender;
  final DateTime Function() _clock;

  /// The name this node reports under, so a key-bound reply says who sent it.
  String get reporterNameForReply => _sender.reporterName;

  Future<PlaceComposeResult> compose({
    required double latitude,
    required double longitude,
    required String label,
    required PlaceType type,
    required PlaceTtl ttl,
    PlacePrecision precision = PlacePrecision.exact,
    PlaceProvenance provenance = PlaceProvenance.pinned,
  }) async {
    final String trimmed = label.trim();
    final PlaceLabelProblem? labelProblem = placeLabelProblem(trimmed);
    if (labelProblem != null) {
      return PlaceComposeResult.refused(PlaceComposeRefusal.label,
          labelProblem: labelProblem);
    }
    final String name = _sender.reporterName;
    final Uint8List? key = _sender.reporterKey;
    if (name.isEmpty && key == null) {
      return const PlaceComposeResult.refused(PlaceComposeRefusal.identity);
    }

    // Snap first, so the id and the transmitted digits agree.
    final double lat = precision.snap(latitude);
    final double lon = precision.snap(longitude);
    final int latE6 = _toE6(lat);
    final int lonE6 = _toE6(lon);
    if (latE6 < -90000000 ||
        latE6 > 90000000 ||
        lonE6 < -180000000 ||
        lonE6 > 180000000) {
      return const PlaceComposeResult.refused(PlaceComposeRefusal.coordinates);
    }

    final String id = placeIdFor(
      reporterKey: key,
      reporterName: name,
      latE6: latE6,
      lonE6: lonE6,
      typeToken: type.token,
    );
    final DateTime now = _clock();
    final Place place = Place(
      id: id,
      reporterKey: key,
      reporterName: name,
      type: type,
      typeToken: type.token,
      label: trimmed,
      latE6: latE6,
      lonE6: lonE6,
      decimals: precision.decimals,
      provenance: provenance,
      ttl: ttl,
      sentAt: now,
      sentAtFromSender: false,
      expiresAt: now.add(ttl.life),
      lastSeen: now,
    );

    final String text = encodePlace(place);
    final PlaceReportDecision decision = _budget.take();
    if (!decision.allowed) {
      return PlaceComposeResult.refused(PlaceComposeRefusal.budget,
          allowedAt: decision.allowedAt);
    }
    final bool went = await _sender.sendPlaceText(text);
    if (!went) {
      // The budget was spent on a line that never left, so it is given back:
      // charging the reader for a refusal would make a dead radio cost them
      // their next report too.
      _budget.refund();
      return const PlaceComposeResult.refused(PlaceComposeRefusal.radio);
    }
    _store.upsert(place);
    _store.markSeen(id);
    return PlaceComposeResult.sent(place);
  }

  /// A confirmation or refutation of [place] on the same channel. It shares
  /// the place budget, so confirming cannot be used to bypass reporting
  /// (spec §11).
  Future<PlaceReplySendResult> reply(
    Place place, {
    required PlaceReplyKind kind,
  }) async {
    final String text = encodePlaceReply(PlaceReply(
      kind: kind,
      id8: place.id,
      callsign: _sender.reporterName,
      attribution: PlaceReplyAttribution.claimed,
    ));
    final PlaceReportDecision decision = _budget.take();
    if (!decision.allowed) {
      return PlaceReplySendResult.refused(decision.allowedAt);
    }
    await _sender.sendPlaceText(text);
    return const PlaceReplySendResult.sent();
  }

  /// A confirmation or refutation **addressed to the reporter's own key**.
  ///
  /// A channel reply is attributed by a name, and a name is whatever the sender
  /// typed: the tally records it as `claimed`. A direct message is addressed to
  /// a public key, so the same grammar becomes `keyBound` — the reply cannot be
  /// sent in someone else's name. It shares the place budget with every other
  /// place message, so this is not a way around the rate limit.
  ///
  /// Returns `null` when the place carries no reporter key: there is then nobody
  /// to address, and saying so is better than falling back to a channel reply
  /// the caller did not ask for.
  Future<PlaceReplySendResult?> replyKeyed(
    Place place, {
    required PlaceReplyKind kind,
    required String callsign,
    required Future<bool> Function(Uint8List key, String text) sendDirect,
  }) async {
    final Uint8List? key = place.reporterKey;
    if (key == null) return null;
    final PlaceReportDecision decision = _budget.take();
    if (!decision.allowed) {
      return PlaceReplySendResult.refused(decision.allowedAt);
    }
    final String text = encodePlaceReply(PlaceReply(
      kind: kind,
      id8: place.id,
      callsign: callsign,
      attribution: PlaceReplyAttribution.keyBound,
    ));
    final bool ok = await sendDirect(key, text);
    if (!ok) return null;
    return const PlaceReplySendResult.sent();
  }

  static int _toE6(double degrees) => (degrees * 1e6).truncate();
}

/// The outcome of sending a confirmation or a refutation.
final class PlaceReplySendResult {
  const PlaceReplySendResult.sent()
      : allowedAt = null,
        sent = true;

  const PlaceReplySendResult.refused(this.allowedAt) : sent = false;

  final bool sent;

  /// The moment the budget allows the next place-family message.
  final DateTime? allowedAt;
}
