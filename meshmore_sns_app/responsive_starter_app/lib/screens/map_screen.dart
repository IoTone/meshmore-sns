// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../gen/app_localizations.dart';
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
/// A pan/zoom map owns every horizontal drag, so the shell locks its
/// swipe while this tab is current (see `HomeShell`); leave via Back,
/// the dots or quick-nav. There is no flag to publish, unlike
/// `GridScreen.capturesHorizontalDrag`: the lock is unconditional.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Stack(
      children: <Widget>[
        const Positioned.fill(child: StreetMapView()),
        // Top-left is free in StreetMapView (its controls are top-right
        // and its "paused" chip never shows here: `frozen` is false).
        Positioned(
          left: 12,
          top: 12,
          child: Material(
            color: cs.surface.withValues(alpha: .9),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
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
