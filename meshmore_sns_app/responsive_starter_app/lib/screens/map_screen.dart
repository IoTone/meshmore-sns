// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
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
/// A pan/zoom map owns every horizontal drag on this page, so while it shows
/// the shell does not page (R109, the `HomeShell` rule; the page is built as a
/// neighbour before it is shown, so the lock cannot be a mount-time claim).
/// **The view strip and Back are how you leave.** The edge-swipe bands that
/// used to be the gesture exit are gone by the owner's ruling: a drag that
/// started near an edge is a pan, and a page change is a tap at the top.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});


  /// The one control this page contributes to the map's own column.
  ///
  /// It used to be two. The offline-maps button was a navigation shortcut to a
  /// row that already exists in Settings, sitting in a column of map controls:
  /// every other button there changes what the map *shows*, and this one left
  /// the screen. The places button stays, because places are a map layer rather
  /// than a settings page.
  static const int _controlExtras = 1;

  /// R70 — anything placed on the right edge starts below the whole column,
  /// built-in controls plus the one this page adds, so it can never shadow a
  /// button.
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
        Expanded(
          // No edge-swipe bands: on this screen a horizontal drag is the map's,
          // and a page change is the strip at the top. The owner's ruling, after
          // the bands kept fighting a pan that started near an edge.
          child: StreetMapView(
              // The map's own tool lives in the map's right-hand column, under
              // the built-in controls: it used to sit on the left edge, where a
              // right thumb never found it.
              controlExtras: <Widget>[
                // A place is a thing the app keeps, and this column was the only
                // way to see the list — an icon with no count reads as a verb, so
                // a reader with twelve saved places had no way to know they
                // existed. The badge is the count.
                Builder(builder: (BuildContext ctx) {
                  final int count = ctx.watch<PlaceStore?>()?.all.length ?? 0;
                  final Widget button = IconButton(
                    key: const ValueKey<String>('map-places-button'),
                    tooltip: l.placeHistoryTitle,
                    iconSize: 18,
                    constraints: const BoxConstraints(
                        minWidth: StreetMapView.controlCell,
                        minHeight: StreetMapView.controlCell),
                    icon: const Icon(Icons.push_pin_outlined),
                    onPressed: () => PlaceHistorySheet.show(
                      ctx,
                      store: ctx.read<PlaceStore>(),
                      composer: placeComposerOf(ctx),
                    ),
                  );
                  if (count == 0) return button;
                  return Badge(
                    label: Text('$count'),
                    child: button,
                  );
                }),
              ],
            ),
        ),
      ],
    );
  }
}
