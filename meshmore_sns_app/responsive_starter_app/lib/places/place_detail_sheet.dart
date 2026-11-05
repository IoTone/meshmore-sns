// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import 'place.dart';
import 'place_confirmation.dart';
import 'place_directions.dart';
import 'place_sender.dart';
import 'place_store.dart';
import 'place_ui.dart';

/// What one place says when it is opened (`meshmore-places-spec.md` §12).
///
/// The copy is part of the feature: it says when the pin expires, who reported
/// it and where the point came from, and on a channel-sourced place it says
/// that the identity is a name and not a key. It never says "verified" or
/// "official" — a pin is one person's claim with a date.
class PlaceDetailSheet extends StatelessWidget {
  const PlaceDetailSheet({
    super.key,
    required this.place,
    required this.store,
    this.composer,
    this.probe = const SystemDirectionsProbe(),
  });

  final Place place;
  final PlaceStore store;

  /// Null when there is no radio: the confirm/refute actions are then hidden
  /// rather than shown broken.
  final PlaceComposer? composer;
  final DirectionsProbe probe;

  static Future<void> show(
    BuildContext context, {
    required Place place,
    required PlaceStore store,
    PlaceComposer? composer,
    DirectionsProbe probe = const SystemDirectionsProbe(),
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => PlaceDetailSheet(
          place: place,
          store: store,
          composer: composer,
          probe: probe,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final DateTime now = DateTime.now();
    final PlaceConfirmationSummary counts = store.confirmationsFor(place.id);
    return SafeArea(
      child: Padding(
        padding: skin.space.pad(5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(placeIcon(place.type),
                    color: placeTypeColour(skin, place.type)),
                SizedBox(width: skin.space.step(2)),
                Expanded(
                  child: Text(
                    place.label,
                    style: TextStyle(
                      color: skin.color.fg,
                      fontSize: skin.type.sizeLg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: skin.space.step(2)),
            Text(placeExpiryText(l, place, now),
                key: const ValueKey<String>('place-expiry-line'),
                style: TextStyle(
                    color: place.isLiveAt(now)
                        ? skin.color.accent
                        : skin.color.fgMuted,
                    fontSize: skin.type.sizeBody)),
            Text(
              l.placeReportedBy(
                place.reporterName,
                place.sentAtFromSender
                    ? MaterialLocalizations.of(context).formatShortDate(place.sentAt)
                    : l.placeTimeUnknown,
              ),
              style:
                  TextStyle(color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
            ),
            Text(placeSourceText(l, place.provenance),
                style:
                    TextStyle(color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
            if (place.isUnkeyed)
              Padding(
                padding: EdgeInsets.only(top: skin.space.step(2)),
                child: Text(
                  l.placeUnkeyedIdentity,
                  key: const ValueKey<String>('place-unkeyed-note'),
                  style: TextStyle(
                      color: skin.color.alert, fontSize: skin.type.sizeSm),
                ),
              ),
            if (!PlaceType.isKnownToken(place.typeToken))
              Padding(
                padding: EdgeInsets.only(top: skin.space.step(1)),
                child: Text(l.placeUnknownType(place.typeToken),
                    style: TextStyle(
                        color: skin.color.fgMuted,
                        fontSize: skin.type.sizeSm)),
              ),
            if (counts.totalConfirming > 0 || counts.refuting + counts.claimedRefuting > 0)
              Padding(
                padding: EdgeInsets.only(top: skin.space.step(2)),
                child: Text(
                  <String>[
                    if (counts.totalConfirming > 0)
                      l.placeConfirmations(counts.shown),
                    if (counts.more > 0) l.placeConfirmationsMore(counts.more),
                    if (counts.claimedConfirming > 0)
                      l.placeClaimedConfirmations(counts.claimedConfirming),
                  ].join(' · '),
                  style: TextStyle(
                      color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
                ),
              ),
            if (counts.hidden)
              Padding(
                padding: EdgeInsets.only(top: skin.space.step(1)),
                child: Text(l.placeHiddenByRefutation,
                    style: TextStyle(
                        color: skin.color.alert, fontSize: skin.type.sizeSm)),
              ),
            SizedBox(height: skin.space.step(3)),
            Wrap(
              spacing: skin.space.step(2),
              runSpacing: skin.space.step(2),
              children: <Widget>[
                if (composer != null && place.isLiveAt(now)) ...<Widget>[
                  OutlinedButton(
                    key: const ValueKey<String>('place-confirm'),
                    onPressed: () => _reply(context, PlaceReplyKind.confirm),
                    child: Text(l.placeConfirmAction),
                  ),
                  OutlinedButton(
                    key: const ValueKey<String>('place-refute'),
                    onPressed: () => _reply(context, PlaceReplyKind.refute),
                    child: Text(l.placeRefuteAction),
                  ),
                ],
                TextButton.icon(
                  key: const ValueKey<String>('place-directions'),
                  icon: const Icon(Icons.directions_outlined, size: 18),
                  label: Text(l.placeDirections),
                  onPressed: () => _directions(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reply(BuildContext context, PlaceReplyKind kind) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final PlaceComposer? c = composer;
    if (c == null) return;
    final PlaceReplySendResult result = await c.reply(place, kind: kind);
    if (!context.mounted) return;
    final String text = result.sent
        ? l.placeSent
        : l.placeBudgetRefused(
            6,
            MaterialLocalizations.of(context).formatTimeOfDay(
              TimeOfDay.fromDateTime(result.allowedAt ?? DateTime.now()),
              alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
            ),
          );
    Navigator.of(context).pop();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _directions(BuildContext context) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final DirectionsOutcome outcome = await PlaceDirections.of(place).open(probe);
    if (!context.mounted) return;
    if (outcome.copied) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l.placeDirectionsCopied)));
    }
  }
}
