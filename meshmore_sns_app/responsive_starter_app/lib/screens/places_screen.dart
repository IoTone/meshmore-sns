// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../places/place_history_sheet.dart';
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
class PlacesScreen extends StatelessWidget {
  const PlacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final PlaceStore store = context.watch<PlaceStore>();
    return Scaffold(
      appBar: AppBar(title: Text(l.placeHistoryTitle)),
      body: MmScaffold(
        child: PlaceHistorySheet(
          store: store,
          composer: placeComposerOf(context),
          asScreen: true,
        ),
      ),
    );
  }
}
