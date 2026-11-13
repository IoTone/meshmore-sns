// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/meshcore_controller.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import 'place.dart';
import 'place_detail_sheet.dart';
import 'place_sender.dart';
import 'place_store.dart';
import 'place_ui.dart';

/// Every place this device saw, live and expired, with its final state
/// (`meshmore-places-spec.md` §10).
///
/// The list is the after-action record: a pin leaves the map at its expiry and
/// arrives here, which is why nothing is ever deleted on expiry. Search covers
/// the label and the reporter; a blocked reporter is absent from every list,
/// the map and search at once because the filter lives in the store.
class PlaceHistorySheet extends StatefulWidget {
  const PlaceHistorySheet({
    super.key,
    required this.store,
    this.composer,
    this.asScreen = false,
  });

  final PlaceStore store;
  final PlaceComposer? composer;

  /// Drawn as a page rather than a sheet.
  ///
  /// The list was only ever a modal, which meant it had no route: it could not be
  /// linked, could not be restored by the router, and could not be reached except
  /// through the map's pin control. The filters and the rows are the same widget
  /// in both cases so the two cannot drift, and the difference is only what owns
  /// the height — a sheet sizes to its content, a page fills the screen.
  final bool asScreen;

  static Future<void> show(
    BuildContext context, {
    required PlaceStore store,
    PlaceComposer? composer,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => PlaceHistorySheet(store: store, composer: composer),
      );

  @override
  State<PlaceHistorySheet> createState() => _PlaceHistorySheetState();
}

class _PlaceHistorySheetState extends State<PlaceHistorySheet> {
  final TextEditingController _search = TextEditingController();
  final Set<PlaceType> _types = <PlaceType>{};
  bool _liveOnly = true;
  bool _keyedOnly = false;

  /// The spec's "expires within" filter (§10). Null is no window.
  Duration? _within;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final List<Place> rows = widget.store.filtered(
      liveOnly: _liveOnly,
      types: _types,
      expiresWithin: _within,
      query: _search.text,
      keyedOnly: _keyedOnly,
    );
    // One list of header widgets, used two ways: inside a Column when this is a
    // sheet (the sheet sizes to its content), and inside a ListView when it is a
    // page. A page that kept the filters outside the scrollable overflowed by 314
    // pixels on a 320 dp phone at 200 % text, because the chips alone were taller
    // than what the list had left.
    final List<Widget> header = <Widget>[
            // One title and nothing beside it. The share control that used
            // to sit here exported the whole ledger as a CSV, which is a
            // different question from the one a place answers: a pin is an
            // address, so sharing belongs on the pin, and it shares the
            // address (see the place detail sheet).
            if (!widget.asScreen)
              Text(
                l.placeHistoryTitle,
                style: TextStyle(
                  color: skin.color.fg,
                  fontSize: skin.type.sizeLg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            TextField(
              key: const ValueKey<String>('place-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: l.placeSearchHint),
              style:
                  TextStyle(color: skin.color.fg, fontSize: skin.type.sizeBody),
            ),
            SizedBox(height: skin.space.rowGap),
            Wrap(
              spacing: skin.space.step(2),
              runSpacing: skin.space.step(2),
              children: <Widget>[
                MmFilterChip(
                  key: const ValueKey<String>('place-filter-live'),
                  label: Text(l.placeStateLive),
                  selected: _liveOnly,
                  onSelected: (bool v) => setState(() => _liveOnly = v),
                ),
                // "Expires within": one choice at a time, because two windows
                // describe one span and the narrower is the one asked for.
                _withinChip(null, l.placeWithinAny),
                _withinChip(const Duration(hours: 1), l.placeWithinHour),
                _withinChip(const Duration(hours: 24), l.placeWithinDay),
                MmFilterChip(
                  key: const ValueKey<String>('place-filter-keyed'),
                  label: Text(l.placeKeyedOnly),
                  selected: _keyedOnly,
                  onSelected: (bool v) => setState(() => _keyedOnly = v),
                ),
                for (final PlaceType t in PlaceType.values)
                  MmFilterChip(
                    key: ValueKey<String>('place-filter-type-${t.token}'),
                    label: Text(placeTypeLabel(l, t)),
                    selected: _types.contains(t),
                    onSelected: (bool v) => setState(() {
                      if (v) {
                        _types.add(t);
                      } else {
                        _types.remove(t);
                      }
                    }),
                  ),
              ],
            ),
            SizedBox(height: skin.space.step(2)),
    ];

    if (widget.asScreen) {
      return SafeArea(
        child: ListView(
          padding: skin.space.pad(6),
          children: <Widget>[
            ...header,
            if (rows.isEmpty)
              Text(l.placeHistoryEmpty,
                  style: TextStyle(
                      color: skin.color.fgMuted,
                      fontSize: skin.type.sizeBody))
            else
              for (final Place p in rows) _row(context, l, skin, p),
          ],
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: skin.space.pad(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ...header,
            Flexible(child: _list(context, l, skin, rows)),
          ],
        ),
      ),
    );
  }

  /// The rows, or the sentence that says there are none.
  Widget _list(
      BuildContext context, AppLocalizations l, MmSkin skin, List<Place> rows) {
    return rows.isEmpty
              ? Text(l.placeHistoryEmpty,
                  style: TextStyle(
                      color: skin.color.fgMuted,
                      fontSize: skin.type.sizeBody))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  itemBuilder: (BuildContext c, int i) =>
                      _row(context, l, skin, rows[i]),
                );
  }

  Widget _withinChip(Duration? window, String label) {
    return MmFilterChip(
      key: ValueKey<String>('place-filter-within-'
          '${window == null ? 'any' : '${window.inHours}h'}'),
      label: Text(label),
      selected: _within == window,
      onSelected: (bool _) => setState(() => _within = window),
    );
  }

  Widget _row(
      BuildContext context, AppLocalizations l, MmSkin skin, Place place) {
    final DateTime now = DateTime.now();
    final bool live = place.isLiveAt(now);
    return ListTile(
      key: ValueKey<String>('place-row-${place.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        placeIcon(place.type),
        color: live ? placeTypeColour(skin, place.type) : skin.color.fgMuted,
      ),
      title: Text(place.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: skin.color.fg, fontSize: skin.type.sizeBody)),
      subtitle: Text(
        <String>[
          live ? placeExpiryText(l, place, now) : l.placeStateExpired,
          place.reporterName,
          if (place.isUnkeyed) l.placeUnkeyedIdentity,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
      ),
      trailing: live
          ? null
          : Icon(Icons.history, size: 16, color: skin.color.fgMuted),
      onTap: () => PlaceDetailSheet.show(context,
          place: place,
          store: widget.store,
          composer: widget.composer,
          sendDirect: (Uint8List key, String text) async {
            final String hex =
                key.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
            return await context
                    .read<MeshcoreController>()
                    .sendDirectText(hex, text) !=
                null;
          }),
    );
  }
}
