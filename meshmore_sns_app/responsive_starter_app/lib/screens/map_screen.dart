// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../ui/mm_edge_swipe.dart';
import '../ui/mm_page_header.dart';
import '../places/place_history_sheet.dart';
import '../places/place_store.dart';
import '../places/place_wiring.dart';
import 'street_map_view.dart';

/// R61 — the **Map** primary view: the street map as its own swipe page.
///
/// The map used to be one of nine view modes inside the Hyperlocal grid
/// tab, three picks deep. This is the same [StreetMapView] — tiles from
/// the offline cache, peers, own trail, range rings — promoted to a page
/// of the shell's `PageView`, the way the grid itself became one
/// (issue #4).
///
/// It is the map *viewer*, not the pack manager: Settings → Offline maps
/// ([MapsScreen]) is unchanged and is one tap away from the corner
/// button here.
///
/// A pan/zoom map owns every horizontal drag in the middle of the screen, so
/// while this page is the current one the shell does not page (R109, the
/// `HomeShell` rule; the page is built as a neighbour before it is shown, so
/// the lock cannot be a mount-time claim). **Edge swipe** is then the way out
/// by gesture: a 24 dp band on each screen edge ([MmEdgeSwipe]) is hit-tested
/// before the map, and an inward fling there calls [onEdgeSwipe] (`-1`
/// previous, `+1` next). Back and the view strip also leave. The band is
/// hit-tested above the map, so its drag never also pages the body.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key, this.onEdgeSwipe});

  /// Called with -1 (previous view) or +1 (next view) by an edge swipe.
  /// Null (a bare `MapScreen` in a test) means the bands do nothing.
  final ValueChanged<int>? onEdgeSwipe;

  /// The two controls this page contributes to the map's own column.
  static const int _controlExtras = 2;

  /// R70 — the edge band starts below the whole column, built-in controls
  /// plus the two this page adds, so it can never shadow a button.
  static double get rightControlsBottom =>
      StreetMapView.controlsBottomFor(_controlExtras);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      children: <Widget>[
        // The map is the one view whose content is full-bleed, so its header
        // sits above the canvas rather than floating over it: a floating box
        // would cover the thing you are trying to read.
        MmPageHeader(title: l.tabMap),
        Expanded(
          child: MmEdgeSwipe(
            onSwipe: (int d) => onEdgeSwipe?.call(d),
            rightInsets: EdgeInsets.only(top: rightControlsBottom),
            child: StreetMapView(
              browseWithoutFix: true,
              // Both map tools live in the map's own right-hand column, under
              // the built-in controls. They used to sit on the left edge, and
              // with the zoom column on the right the left ones were the
              // buttons a thumb never found.
              controlExtras: <Widget>[
                IconButton(
                  key: const ValueKey<String>('map-offline-maps-button'),
                  tooltip: l.mapsTitle,
                  iconSize: 18,
                  constraints: const BoxConstraints(
                      minWidth: StreetMapView.controlCell,
                      minHeight: StreetMapView.controlCell),
                  icon: const Icon(Icons.download_for_offline_outlined),
                  onPressed: () => context.push('/settings/maps'),
                ),
                IconButton(
                  key: const ValueKey<String>('map-places-button'),
                  tooltip: l.placeHistoryTitle,
                  iconSize: 18,
                  constraints: const BoxConstraints(
                      minWidth: StreetMapView.controlCell,
                      minHeight: StreetMapView.controlCell),
                  icon: const Icon(Icons.push_pin_outlined),
                  onPressed: () => PlaceHistorySheet.show(
                    context,
                    store: context.read<PlaceStore>(),
                    composer: placeComposerOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
