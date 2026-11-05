// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
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
  const PlaceHistorySheet({super.key, required this.store, this.composer});

  final PlaceStore store;
  final PlaceComposer? composer;

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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final AppLocalizations l = AppLocalizations.of(context);
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final File file = File('${dir.path}/places-ledger.csv');
      await file.writeAsString(widget.store.exportLedgerCsv());
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l.placeExportDone(file.path))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l.placeExportFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final List<Place> rows = widget.store.filtered(
      liveOnly: _liveOnly,
      types: _types,
      query: _search.text,
      keyedOnly: _keyedOnly,
    );
    return SafeArea(
      child: Padding(
        padding: skin.space.pad(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l.placeHistoryTitle,
                    style: TextStyle(
                      color: skin.color.fg,
                      fontSize: skin.type.sizeLg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('place-export'),
                  tooltip: l.placeExportLedger,
                  onPressed: _export,
                  icon: const Icon(Icons.ios_share),
                ),
              ],
            ),
            TextField(
              key: const ValueKey<String>('place-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: l.placeSearchHint),
              style:
                  TextStyle(color: skin.color.fg, fontSize: skin.type.sizeBody),
            ),
            SizedBox(height: skin.space.step(2)),
            Wrap(
              spacing: skin.space.step(2),
              runSpacing: skin.space.step(2),
              children: <Widget>[
                FilterChip(
                  key: const ValueKey<String>('place-filter-live'),
                  label: Text(l.placeStateLive),
                  selected: _liveOnly,
                  onSelected: (bool v) => setState(() => _liveOnly = v),
                ),
                FilterChip(
                  key: const ValueKey<String>('place-filter-keyed'),
                  label: Text(l.placeKeyedOnly),
                  selected: _keyedOnly,
                  onSelected: (bool v) => setState(() => _keyedOnly = v),
                ),
                for (final PlaceType t in PlaceType.values)
                  FilterChip(
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
            Flexible(
              child: rows.isEmpty
                  ? Text(l.placeHistoryEmpty,
                      style: TextStyle(
                          color: skin.color.fgMuted,
                          fontSize: skin.type.sizeBody))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      itemBuilder: (BuildContext c, int i) =>
                          _row(context, l, skin, rows[i]),
                    ),
            ),
          ],
        ),
      ),
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
          place: place, store: widget.store, composer: widget.composer),
    );
  }
}
