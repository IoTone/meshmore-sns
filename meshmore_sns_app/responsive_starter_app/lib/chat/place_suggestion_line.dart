// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/chat_message.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/own_location.dart';
import '../places/place.dart';
import '../sns/place_inference.dart';
import '../places/place_create_sheet.dart';
import '../places/place_wiring.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';

/// The line a chat row shows when a message names a place.
///
/// The app used to draw these mentions as markers on the SNS grid. That was
/// guesswork drawn as geography: a message saying "see you in Bellevue" is not
/// a report, and a diamond on a map says it is. The mention is still worth
/// something to a reader, so it is offered here instead — this row named a
/// place, and the person holding the phone is the one who knows whether it is
/// worth reporting and where it is.
///
/// So nothing is placed: no coordinates are derived from the words, and the
/// pin comes only from the user's own position when they choose to report it.
class PlaceSuggestionLine extends StatelessWidget {
  const PlaceSuggestionLine({
    super.key,
    required this.message,
    required this.name,
    this.place,
  });

  final ChatMessage message;

  /// The place name the message mentions, as the gazetteer spells it.
  final String name;

  /// The position the message carries outright, when it carries one.
  ///
  /// A coordinate is not a guess, so the offer uses it rather than the reader's
  /// own position: a direct message from a stranger saying where they are is a
  /// place, and asking the reader to stand on it first would be nonsense.
  final InferredPlace? place;

  Future<void> _report(BuildContext context) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final MeshcoreController mc = context.read<MeshcoreController>();
    final OwnLocation? own = mc.ownLocation;
    if (own == null) {
      // A place is a position. Without one there is nothing to report, and
      // saying so is better than opening a sheet that cannot send.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(l.placeSuggestNeedsLocation)),
      );
      return;
    }
    final Place? place = await PlaceCreateSheet.show(
      context,
      latitude: this.place?.latitude ?? own.latitude,
      longitude: this.place?.longitude ?? own.longitude,
      composer: placeComposerOf(context, channelIdx: message.channelIdx),
      initialLabel: name,
      // The sheet's picker opens on the channel the message arrived on, so the
      // slot it shows is the slot the report will use. Without this the picker
      // fell back to the remembered slot while the composer sent on the
      // message's channel, and the two disagreed on screen.
      initialChannelIdx: message.channelIdx,
    );
    if (!context.mounted) return;
    if (place != null) {
      // Answered: the row has done its job, so the offer goes away.
      await mc.dismissPlaceSuggestion(message);
      return;
    }
  }

  Future<void> _dismiss(BuildContext context) async {
    await context.read<MeshcoreController>().dismissPlaceSuggestion(message);
  }

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
          top: skin.space.step(1), bottom: skin.space.step(1)),
      // A wrap, not a row: the name and two controls do not fit beside each
      // other at 320 dp and 200 % text, and a control that falls off the edge
      // is a control the user cannot press.
      child: Wrap(
        spacing: skin.space.step(2),
        runSpacing: skin.space.step(1),
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.place_outlined,
                  size: skin.type.sizeBody, color: skin.color.fgMuted),
              SizedBox(width: skin.space.step(1)),
              Flexible(
                child: Text(
                  place == null
                      ? l.placeSuggestLooksLike(name)
                      : l.placeSuggestHasPosition(place!.displayName),
                  key: ValueKey<String>('place-suggestion-${message.id}'),
                  softWrap: true,
                  style: TextStyle(
                      color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
                ),
              ),
            ],
          ),
          // Compact: an offer about the row above, not a primary action. The
          // 48 dp target and the boundary stay, so it is still a control; only
          // the type role and the padding step down.
          MmAction(
            key: ValueKey<String>('place-suggestion-report-${message.id}'),
            compact: true,
            icon: Icons.add_location_alt_outlined,
            label: l.placeSuggestReport,
            onPressed: () => _report(context),
          ),
          MmAction(
            key: ValueKey<String>('place-suggestion-dismiss-${message.id}'),
            compact: true,
            label: l.placeSuggestDismiss,
            onPressed: () => _dismiss(context),
          ),
        ],
      ),
    );
  }
}
