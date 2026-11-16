// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../geofence/geofence_controller.dart';
import '../geofence/geofence_create_sheet.dart';
import '../meshcore/meshcore_controller.dart';
import '../ui/mm_components.dart';
import '../theme/mm_skin.dart';
import 'place.dart';
import 'place_confirmation.dart';
import '../util/share.dart';
import 'place_directions.dart';
import 'place_sender.dart';
import 'place_store.dart';
import '../media/media_receive_view.dart';
import '../media/media_transfer.dart';
import 'place_photo.dart';
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
    this.photos,
    this.onFetchPhoto,
    this.sendDirect,
  });

  final Place place;
  final PlaceStore store;

  /// The fetched pictures, when the app has a store. Null keeps the section
  /// out of the sheet rather than showing a button that cannot work.
  final PlacePhotos? photos;

  /// Starts a fetch for this place's picture, or null when there is no radio.
  /// The sheet watches the returned fetch's progress while it runs.
  final Future<PlacePhotoFetch?> Function()? onFetchPhoto;

  /// Null when there is no radio: the confirm/refute actions are then hidden
  /// rather than shown broken.
  final PlaceComposer? composer;
  final DirectionsProbe probe;

  /// Sends a direct message to one key, or null when there is no radio. The
  /// key-bound confirm/refute pair is hidden without it: a reply that cannot be
  /// addressed is not offered.
  final Future<bool> Function(Uint8List key, String text)? sendDirect;

  static Future<void> show(
    BuildContext context, {
    required Place place,
    required PlaceStore store,
    PlaceComposer? composer,
    DirectionsProbe probe = const SystemDirectionsProbe(),
    PlacePhotos? photos,
    Future<PlacePhotoFetch?> Function()? onFetchPhoto,
    Future<bool> Function(Uint8List key, String text)? sendDirect,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => PlaceDetailSheet(
          place: place,
          store: store,
          composer: composer,
          probe: probe,
          photos: photos,
          onFetchPhoto: onFetchPhoto,
          sendDirect: sendDirect,
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
        padding: skin.space.pad(6),
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
            // Where it went, or where it came from. A place is channel text, so
            // the slot is its whole audience, and the sheet used to leave the
            // reader to guess which one.
            if (placeChannelText(
                    l, place, context.read<MeshcoreController?>()?.channels ??
                        const <MapEntry<int, String>>[])
                case final String channelLine)
              Text(channelLine,
                  key: const ValueKey<String>('place-channel-line'),
                  style: TextStyle(
                      color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
            if (photos != null)
              Padding(
                padding: EdgeInsets.only(top: skin.space.step(3)),
                child: _PhotoSection(
                  place: place,
                  photos: photos!,
                  onFetch: onFetchPhoto,
                  skin: skin,
                  l: l,
                ),
              ),
            if (place.isUnkeyed)
              Padding(
                padding: EdgeInsets.only(top: skin.space.step(2)),
                child: Text(
                  l.placeUnkeyedIdentity,
                  key: const ValueKey<String>('place-unkeyed-note'),
                  style: TextStyle(
                      color: skin.color.alertInk, fontSize: skin.type.sizeSm),
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
                        color: skin.color.alertInk, fontSize: skin.type.sizeSm)),
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
                // A key-bound reply, when there is a key to address: the same
                // grammar over a direct message, so the tally records it as
                // binding rather than as a name somebody typed.
                if (composer != null &&
                    sendDirect != null &&
                    place.reporterKey != null &&
                    place.isLiveAt(now)) ...<Widget>[
                  OutlinedButton(
                    key: const ValueKey<String>('place-confirm-sender'),
                    onPressed: () =>
                        _replyKeyed(context, PlaceReplyKind.confirm),
                    child: Text(l.placeConfirmToSender),
                  ),
                  OutlinedButton(
                    key: const ValueKey<String>('place-refute-sender'),
                    onPressed: () => _replyKeyed(context, PlaceReplyKind.refute),
                    child: Text(l.placeRefuteToSender),
                  ),
                ],
                // A place is already a centre and a name; a fence is that plus
                // a radius. Making one from the other is one tap and no typing,
                // which is the whole reason both exist.
                MmAction(
                  key: const ValueKey<String>('place-to-geofence'),
                  icon: Icons.shield_outlined,
                  label: l.placeFenceThis,
                  onPressed: () => _fence(context),
                ),
                MmAction(
                  key: const ValueKey<String>('place-directions'),
                  icon: Icons.directions_outlined,
                  label: l.placeDirections,
                  onPressed: () => _directions(context),
                ),
                // The share belongs on the pin, and what it shares is the
                // address: a label, a coordinate pair and a link that opens
                // them somewhere else. The list used to offer a CSV of the
                // whole ledger instead, which answered a different question.
                MmAction(
                  key: const ValueKey<String>('place-share'),
                  icon: Icons.ios_share,
                  label: l.placeShareAddress,
                  onPressed: () => _share(context),
                ),
                // A place is a claim about the world, and a claim the reader
                // does not want on their map is theirs to drop, whoever
                // reported it. Blocking the reporter is a different decision
                // and stays where it is.
                MmAction(
                  key: const ValueKey<String>('place-remove'),
                  icon: Icons.delete_outline,
                  label: l.placeRemove,
                  onPressed: () => _remove(context),
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
        : result.failed
            ? l.placeSendFailed
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

  /// The key-bound pair: the same grammar, addressed to the reporter's key.
  ///
  /// A channel reply carries a *name*, which the tally can only record as
  /// claimed. A direct message is addressed to a key, so the reply binds to
  /// this node and cannot be sent in someone else's name. It shares the place
  /// budget, so it is not a way around the rate limit.
  Future<void> _replyKeyed(BuildContext context, PlaceReplyKind kind) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final PlaceComposer? c = composer;
    final Future<bool> Function(Uint8List, String)? send = sendDirect;
    if (c == null || send == null) return;
    final PlaceReplySendResult? result = await c.replyKeyed(place,
        kind: kind, callsign: c.reporterNameForReply, sendDirect: send);
    if (!context.mounted) return;
    final String text = result == null
        ? l.placeNoSenderKey
        : result.sent
            ? l.placeSentDirect
            : result.failed
                ? l.placeSendFailed
                : l.placeBudgetRefused(
                6,
                MaterialLocalizations.of(context).formatTimeOfDay(
                  TimeOfDay.fromDateTime(result.allowedAt ?? DateTime.now()),
                  alwaysUse24HourFormat:
                      MediaQuery.alwaysUse24HourFormatOf(context),
                ),
              );
    Navigator.of(context).pop();
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  /// Open the fence sheet centred on this place, and save what comes back.
  Future<void> _fence(BuildContext context) async {
    final GeofenceController? fences =
        Provider.of<GeofenceController?>(context, listen: false);
    if (fences == null) return;
    final ({String label, double radiusMeters})? made =
        await showModalBottomSheet<({String label, double radiusMeters})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => GeofenceCreateSheet(
        latitude: place.latitude,
        longitude: place.longitude,
      ),
    );
    if (made == null || !context.mounted) return;
    final AppLocalizations l = AppLocalizations.of(context);
    await fences.addFence(
      // A fence named after the place it was made from, so the two line up in
      // both lists without anyone retyping the name.
      label: made.label.isEmpty ? place.label : made.label,
      latitude: place.latitude,
      longitude: place.longitude,
      radiusMeters: made.radiusMeters,
    );
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(l.placeFenceMade(fences.fences.length))));
    }
  }

  /// Take this place off the map, after asking.
  Future<void> _remove(BuildContext context) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l.placeRemoveTitle),
        content: Text(l.placeRemoveBody(place.label)),
        actions: <Widget>[
          MmAction(
              label: l.actionCancel, onPressed: () => Navigator.pop(ctx, false)),
          MmAction(
              label: l.placeRemove,
              onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    store.remove(place.id);
    if (context.mounted) Navigator.of(context).maybePop();
  }

  Future<void> _share(BuildContext context) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool shared = await Share.text(placeShareText(place),
        subject: l.placeShareSubject);
    if (!context.mounted || shared) return;
    // Nothing on the device claimed a plain-text share. Saying so is better
    // than a tap with no answer.
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(l.placeShareFailed)));
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

/// The picture line: bytes when they are here, "not fetched" when they are not.
///
/// The copy before a fetch is the spec's own warning (§12): the photo may never
/// arrive, and the text already did. Saying that only after a timeout would be
/// late and would read as a failure rather than as the nature of a broadcast.
class _PhotoSection extends StatefulWidget {
  const _PhotoSection({
    required this.place,
    required this.photos,
    required this.onFetch,
    required this.skin,
    required this.l,
  });

  final Place place;
  final PlacePhotos photos;
  final Future<PlacePhotoFetch?> Function()? onFetch;
  final MmSkin skin;
  final AppLocalizations l;

  @override
  State<_PhotoSection> createState() => _PhotoSectionState();
}

class _PhotoSectionState extends State<_PhotoSection> {
  PlacePhotoFetch? _fetch;
  int? _requested;

  @override
  void dispose() {
    _fetch?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final PlacePhotoFetch? fetch = await widget.onFetch!();
    if (!mounted) {
      fetch?.dispose();
      return;
    }
    setState(() => _fetch = fetch);
  }

  @override
  Widget build(BuildContext context) {
    final PlacePhoto? photo = widget.photos.photoFor(widget.place);
    if (photo != null) {
      return MediaPhotoView(
        photo: photo.photo,
        height: 160,
        key: const ValueKey<String>('place-photo'),
      );
    }
    final PlacePhotoFetch? fetch = _fetch;
    if (fetch == null) {
      return Row(
        children: <Widget>[
          Icon(Icons.image_outlined,
              size: widget.skin.type.sizeLg, color: widget.skin.color.fgMuted),
          SizedBox(width: widget.skin.space.step(2)),
          Expanded(
            child: Text(
              widget.onFetch == null
                  ? widget.l.placePhotoNotFetched
                  : widget.l.placePhotoMayNotArrive,
              key: const ValueKey<String>('place-photo-not-fetched'),
              style: TextStyle(
                  color: widget.skin.color.fgMuted,
                  fontSize: widget.skin.type.sizeSm),
            ),
          ),
          if (widget.onFetch != null)
            MmAction(
              key: const ValueKey<String>('place-photo-fetch'),
              label: widget.l.placePhotoFetch,
              dense: true,
              onPressed: _start,
            ),
        ],
      );
    }
    return ValueListenableBuilder<MediaDownloadProgress?>(
      valueListenable: fetch.progress,
      builder: (BuildContext c, MediaDownloadProgress? progress, Widget? _) {
        if (progress == null) {
          return Text(widget.l.placePhotoFetching,
              style: TextStyle(
                  color: widget.skin.color.fgMuted,
                  fontSize: widget.skin.type.sizeSm));
        }
        return MediaReceiveView(
          progress: progress,
          requested: _requested,
          dropped: fetch.download.reassembler.evictions,
          onAskForMissing: fetch.sendRequest == null
              ? null
              : () async {
                  final int asked = await fetch.askForMissing();
                  if (mounted) setState(() => _requested = asked);
                },
        );
      },
    );
  }
}
