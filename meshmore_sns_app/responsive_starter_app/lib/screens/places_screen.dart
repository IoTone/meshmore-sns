// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../places/place.dart';
import '../places/place_create_sheet.dart';
import '../places/place_history_sheet.dart';
import '../places/place_import.dart';
import '../places/place_import_sheet.dart';
import '../places/place_store.dart';
import '../places/place_wiring.dart';
import '../ui/mm_scaffold.dart';

/// Every place this session has kept, as a page.
///
/// The list existed only as a modal opened from a pin control on the map, which
/// is a fine way to peek and a bad way to arrive: no route meant nothing could
/// link to it, the router could not restore it, and a reader who did not think
/// to look under a pin icon had no door at all. The settings hub has one now, and
/// so does any future link.
///
/// It is also where a place that arrived as text is read back in: sharing a
/// place writes a label, a coordinate pair and a map link, and until now
/// nothing in the app could read that back, so a place somebody sent had to be
/// retyped by hand.
class PlacesScreen extends StatelessWidget {
  const PlacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final PlaceStore store = context.watch<PlaceStore>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l.placeHistoryTitle),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('place-import-action'),
            tooltip: l.placeImportAction,
            icon: const Icon(Icons.content_paste_go_outlined),
            onPressed: () => _import(context),
          ),
        ],
      ),
      body: MmScaffold(
        child: PlaceHistorySheet(
          store: store,
          composer: placeComposerOf(context),
          asScreen: true,
        ),
      ),
    );
  }

  /// Reads a shared place, then opens the ordinary create sheet on it.
  ///
  /// The import is a starting point, not a report: the reader still picks the
  /// type and the life, and the sheet is the one place a report is written.
  Future<void> _import(BuildContext context) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final ImportedPlace? read = await PlaceImportSheet.show(context);
    if (read == null || !context.mounted) return;
    if (read.labelTruncated) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(l.placeImportLabelCut)),
      );
    }
    final Place? place = await PlaceCreateSheet.show(
      context,
      latitude: read.latitude,
      longitude: read.longitude,
      composer: placeComposerOf(context),
      initialLabel: read.label.isEmpty ? null : read.label,
    );
    if (place == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(l.placeSent)),
    );
  }
}
