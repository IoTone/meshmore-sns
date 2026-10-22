// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../gen/app_localizations.dart';
import '../ui/mm_edge_swipe.dart';
import 'street_map_view.dart';
import '../ui/mm_shape.dart';

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
/// A pan/zoom map owns every horizontal drag in the middle of the
/// screen, and R95 made the shell's `PageView` unscrollable in every skin,
/// so the drag is always the map's. **Edge swipe** is how you
/// leave by gesture: a 24 dp band on each screen edge ([MmEdgeSwipe])
/// is hit-tested before the map, and an inward fling there calls
/// [onEdgeSwipe] (`-1` previous, `+1` next). Back and the view strip
/// also leave.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key, this.onEdgeSwipe});

  /// Called with -1 (previous view) or +1 (next view) by an edge swipe.
  /// Null (a bare `MapScreen` in a test) means the bands do nothing.
  final ValueChanged<int>? onEdgeSwipe;

  /// R70 — derived from [StreetMapView]'s own control geometry (five
  /// 48 dp controls from the top), so the right band always starts below
  /// the column and cannot shadow a button.
  static const double rightControlsBottom = StreetMapView.controlsBottom;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: MmEdgeSwipe(
            onSwipe: (int d) => onEdgeSwipe?.call(d),
            rightInsets: const EdgeInsets.only(top: rightControlsBottom),
            child: const StreetMapView(browseWithoutFix: true),
          ),
        ),
        // Top-left is free in StreetMapView (its controls are top-right
        // and its "paused" chip never shows here: `frozen` is false).
        Positioned(
          left: 12,
          top: 12,
          child: Material(
            color: cs.surface.withValues(alpha: .9),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: mmRadius(context, 6),
              side: BorderSide(color: cs.outline.withValues(alpha: .4)),
            ),
            child: IconButton(
              tooltip: l.mapsTitle,
              icon: const Icon(Icons.download_for_offline_outlined),
              onPressed: () => context.push('/settings/maps'),
            ),
          ),
        ),
      ],
    );
  }
}
