// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';
import '../meshcore/chat_message.dart';
import '../theme/mm_skin.dart';
import 'place.dart';
import 'place_codec.dart';
import 'place_confirmation.dart';
import 'place_store.dart';
import 'place_ui.dart';

/// The line a place shows inside the chat thread
/// (`meshmore-places-spec.md` §6, §11).
///
/// The message itself is the wire form; this is the same report rendered as
/// what it means — label, type, time left — with the confirmation count beside
/// it. It is a *display* echo: the row that matters lives in [PlaceStore], so
/// two deliveries of one report still make one pin.
class PlaceEchoLine extends StatelessWidget {
  const PlaceEchoLine({
    super.key,
    required this.place,
    required this.store,
  });

  final Place place;
  final PlaceStore store;

  /// The place a chat message carries, or null when it is ordinary text.
  ///
  /// Parsing is side-effect free so a list build can call it; the store ingests
  /// the same message once, when it arrives.
  ///
  /// The TTL is anchored on the **message's own arrival time**, never on the
  /// moment of the build: a build-time anchor re-starts the countdown on every
  /// rebuild, so a report that expired hours ago would keep reading "expires in
  /// 2 h" and the number under the pin would never move.
  static Place? placeOf(ChatMessage message, {DateTime Function()? clock}) {
    if (message.outgoing) return null;
    final String text = message.text;
    if (!text.contains(placeTag)) return null;
    final int at = text.indexOf(': ');
    final bool prefixed = at > 0 && !text.substring(0, at).contains('[');
    final String sender = prefixed ? text.substring(0, at) : '';
    final String body = prefixed ? text.substring(at + 2) : text;
    return parsePlace(
      body,
      receivedAt: (clock ?? () => message.at)(),
      reporterName: sender,
      provenance: PlaceProvenance.received,
    ).place;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final DateTime now = DateTime.now();
    // The store ingested this same message when it arrived, so its row is the
    // one the rest of the app agrees with (renewals, kept flags, expiry).
    final Place shown = store.byId(place.id) ?? place;
    final PlaceConfirmationSummary counts = store.confirmationsFor(shown.id);
    return Padding(
      padding: EdgeInsets.only(top: skin.space.step(1)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            placeIcon(shown.type),
            size: skin.type.sizeBody,
            color: store.isSeen(shown.id)
                ? skin.color.fgMuted
                : placeTypeColour(skin, shown.type),
          ),
          SizedBox(width: skin.space.step(1)),
          Flexible(
            child: Text(
              l.placeEchoLine(
                shown.label,
                placeTypeLabel(l, shown.type),
                placeExpiryText(l, shown, now),
              ),
              key: ValueKey<String>('place-echo-${shown.id}'),
              maxLines: 2,
              style: TextStyle(
                color: skin.color.fgMuted,
                fontFamily: skin.type.monoFamily,
                fontSize: skin.type.sizeSm,
              ),
            ),
          ),
          if (counts.totalConfirming > 0)
            Padding(
              padding: EdgeInsets.only(left: skin.space.step(1)),
              child: Text(
                l.placeConfirmations(counts.shown),
                style: TextStyle(
                    color: skin.color.ok, fontSize: skin.type.sizeMicro),
              ),
            ),
        ],
      ),
    );
  }
}
