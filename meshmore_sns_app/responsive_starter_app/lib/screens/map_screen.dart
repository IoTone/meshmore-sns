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
import '../theme/mm_skin.dart';
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

  /// R70 — derived from [StreetMapView]'s own control geometry (five
  /// 48 dp controls from the top), so the right band always starts below
  /// the column and cannot shadow a button.
  static const double rightControlsBottom = StreetMapView.controlsBottom;

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
          child: Stack(
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
          child: _MapTool(
            label: l.mapsTitle,
            icon: Icons.download_for_offline_outlined,
            onTap: () => context.push('/settings/maps'),
          ),
        ),
        // Places history (meshmore-places-spec.md §10): every report this
        // device saw, live and expired, with the ledger export. Below the
        // offline-maps button so the two read as one column of map tools.
        Positioned(
          left: 12,
          top: 12 + 40 + 8,
          child: _MapTool(
            key: const ValueKey<String>('map-places-button'),
            label: l.placeHistoryTitle,
            icon: Icons.push_pin_outlined,
            onTap: () => PlaceHistorySheet.show(
              context,
              store: context.read<PlaceStore>(),
              composer: placeComposerOf(context),
            ),
          ),
        ),
      ],
          ),
        ),
      ],
    );
  }
}

/// One labelled map tool. The map's chrome used to be icon-only, so the only
/// way to learn what a button did was to press it (UX audit C8). A short label
/// under the glyph is cheaper than a tooltip that does not exist on touch.
class _MapTool extends StatelessWidget {
  const _MapTool({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final MmSkin skin = context.skin;
    return Semantics(
      button: true,
      label: label,
      // The label is visible, and the tooltip stays so the control keeps the
      // same discoverable name on long-press and in tests.
      child: Tooltip(
        message: label,
        child: Material(
        color: cs.surface.withValues(alpha: .9),
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: mmRadius(context, 6),
          side: BorderSide(color: cs.outline.withValues(alpha: .4)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: mmRadius(context, 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                minWidth: 64, maxWidth: 88, minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: skin.type.sizeLg, color: cs.onSurface),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: skin.type.sizeMicro,
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}
