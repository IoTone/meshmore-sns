// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import '../maps/basemap.dart';
import '../maps/map_source.dart';
import '../meshcore/coverage_store.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/meshcore_controller.dart';
import '../util/lora_range.dart';
import 'node_detail_sheet.dart';
import '../ui/mm_shape.dart';

/// F8 — Fabric survey view. Paints **mesh coverage** as a quilt of
/// shaded cells over an OSM basemap. Distinct from the equal-grid
/// (where peers are *now*) and from the street-map (peers + trail
/// at one moment): this is **multi-session aggregation** — every
/// cell where we've ever observed mesh activity is shaded, brighter
/// for recent, faded for older. Holes are the gaps where the mesh
/// hasn't reached yet.
///
/// Data lives in the controller's [MeshcoreController.coverageCells]
/// map (persisted via [CoverageStore]). The user can clear it via
/// the overflow menu when they want a clean survey from a fresh
/// location.
class FabricSurveyView extends StatefulWidget {
  const FabricSurveyView({
    super.key,
    this.filteredNodes,
    this.frozen = false,
    this.interactive = true,
  });

  final List<DiscoveredNode>? filteredNodes;
  final bool frozen;

  /// R109 — false in the grid's swipe mode: the survey does not take the drag
  /// that pages the shell. Taps still open a node's detail.
  final bool interactive;

  @override
  State<FabricSurveyView> createState() => _FabricSurveyViewState();
}

class _FabricSurveyViewState extends State<FabricSurveyView> {
  static const double _zoomMin = 8.0;
  static const double _zoomMax = 16.0;
  static const double _zoomStep = 1.0;
  late final MapController _map = MapController();
  double _zoom = 12.0; // metro-area default; quilt reads best here
  bool _centered = false;
  bool _showTiles = true;

  /// "12m ago" for the newest recorded cell, or the empty-state sentence's
  /// age when there is nothing recorded. The map stays: it is still a useful
  /// picture of where you are, and replacing it with a notice would take the
  /// place away rather than explain the survey.
  String _newestAgo(MeshcoreController mc, AppLocalizations l) {
    int newest = 0;
    mc.coverageCells.forEach((String _, int at) {
      if (at > newest) newest = at;
    });
    if (newest == 0) return l.weatherAgoHours(0);
    final int ageSec =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - newest;
    if (ageSec < 60) return l.weatherAgoSeconds(ageSec < 1 ? 0 : ageSec);
    if (ageSec < 3600) return l.weatherAgoMinutes(ageSec ~/ 60);
    if (ageSec < 86400) return l.weatherAgoHours(ageSec ~/ 3600);
    return l.fabricAgoDays(ageSec ~/ 86400);
  }

  Future<void> _confirmReset(MeshcoreController mc) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l.fabricResetTitle),
        content: Text(l.fabricResetBody),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.fabricResetApply)),
        ],
      ),
    );
    if (ok == true) await mc.resetCoverage();
  }

  Future<void> _showDetail(MeshcoreController mc, DiscoveredNode n) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => NodeDetailSheet(
        node: n,
        distanceMeters: n.hasLocation
            ? mc.distanceMetersTo(n.latitude!, n.longitude!)
            : null,
        isFavourite: mc.favorites.contains(n.pubKeyHex),
        isKnown: mc.known.contains(n.pubKeyHex),
        onToggleFavourite: () => mc.toggleFavorite(n.pubKeyHex),
        proximity: mc.proximityFor(n),
        recentDms: mc.dmHistoryFor(n.pubKeyHex),
        tags: mc.tagsFor(n.pubKeyHex),
        tagSuggestions: mc.allTags,
        onAddTag: (String t) => mc.addTagTo(n.pubKeyHex, t),
        onRemoveTag: (String t) => mc.removeTagFrom(n.pubKeyHex, t),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;

    final double? selfLat = mc.ownLocation?.latitude;
    final double? selfLon = mc.ownLocation?.longitude;
    if (selfLat == null || selfLon == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.gridNeedsFix,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    if (!_centered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _map.move(LatLng(selfLat, selfLon), _zoom);
        } catch (_) {/* not laid out */}
        _centered = true;
      });
    }

    // Build the coverage polygon set. One CircleMarker per cell —
    // sized so adjacent cells touch (radius = half the cell
    // diagonal × cos(lat) for square-ish look at this latitude).
    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final List<Polygon> cells = <Polygon>[];
    mc.coverageCells.forEach((String key, int unixSec) {
      final ({int latBucket, int lonBucket})? b = CoverageStore.parseKey(key);
      if (b == null) return;
      final double latOrigin = b.latBucket * CoverageStore.cellDeg;
      final double lonOrigin = b.lonBucket * CoverageStore.cellDeg;
      // Recency ramp: <1 h ago = strong fill; >7 d ago = faint.
      // The coverage quilt is the *primary* signal of this view —
      // each cell shouts "the mesh reached here." Stronger alpha
      // than the reach-circles use; this layer wants to dominate.
      // Theme `secondary` reads cleaner over OSM tiles than the
      // mustard `primary` of the NERV palette.
      final int ageSec = nowSec - unixSec;
      double recency;
      if (ageSec < 3600) {
        recency = 1.0;
      } else if (ageSec < 86400) {
        recency = 0.75;
      } else if (ageSec < 604800) {
        recency = 0.45;
      } else {
        recency = 0.2;
      }
      cells.add(Polygon(
        points: <LatLng>[
          LatLng(latOrigin, lonOrigin),
          LatLng(latOrigin + CoverageStore.cellDeg, lonOrigin),
          LatLng(latOrigin + CoverageStore.cellDeg,
              lonOrigin + CoverageStore.cellDeg),
          LatLng(latOrigin, lonOrigin + CoverageStore.cellDeg),
        ],
        color: cs.secondary.withValues(alpha: 0.30 + 0.55 * recency),
        borderColor: cs.secondary.withValues(alpha: 0.50 + 0.40 * recency),
        borderStrokeWidth: 0.8,
      ));
    });

    final List<DiscoveredNode> source = widget.filteredNodes ?? mc.nodes;
    final List<DiscoveredNode> withLoc = <DiscoveredNode>[
      for (final DiscoveredNode n in source)
        if (n.hasLocation) n
    ];

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: LatLng(selfLat, selfLon),
              initialZoom: _zoom,
              minZoom: _zoomMin,
              maxZoom: _zoomMax,
              interactionOptions: InteractionOptions(
                flags: widget.interactive
                    ? InteractiveFlag.drag |
                        InteractiveFlag.pinchZoom |
                        InteractiveFlag.scrollWheelZoom |
                        InteractiveFlag.doubleTapZoom
                    : InteractiveFlag.none,
              ),
              backgroundColor: cs.surfaceContainerHighest,
            ),
            children: <Widget>[
              if (_showTiles)
                // R61 — cached OSM (view cache; see maps spec).
                basemapLayer(context, kOsmStandard),
              if (_showTiles) MapAttribution(kOsmStandard.attribution),
              // Theme-tinted overlay so cells stay readable on busy
              // street tiles.
              if (cells.isNotEmpty) PolygonLayer(polygons: cells),
              // R48 — per-peer reach circles. Diameter is an
              // estimate of how far the peer would still be hearable
              // by another node like ours, derived from the heard
              // RSSI + known distance (when both ends have GPS) and
              // falling back to RSSI-bin / radio-tuple anchors when
              // not. See `estimatedPeerReachMeters`. Drawn before
              // the markers so the pins stay on top.
              CircleLayer(
                circles: <CircleMarker>[
                  // Self range — uses the existing radio-tuple
                  // anchor (we know our own TX power and modulation).
                  if (mc.selfInfo != null)
                    CircleMarker(
                      point: LatLng(selfLat, selfLon),
                      radius: estimatedLoraRangeMeters(
                        spreadingFactor: mc.selfInfo!.spreadingFactor,
                        bandwidthKhz: mc.selfInfo!.bandwidthKhz,
                        txPowerDbm: mc.selfInfo!.txPowerDbm,
                      ),
                      useRadiusInMeter: true,
                      // Outline-only — even modest fill alpha
                      // accumulates unreadably over the OSM tiles +
                      // coverage polygons when many circles overlap.
                      color: const Color(0x00000000),
                      borderColor: cs.primary.withValues(alpha: .75),
                      borderStrokeWidth: 1.4,
                    ),
                  for (final DiscoveredNode n in withLoc)
                    CircleMarker(
                      point: LatLng(n.latitude!, n.longitude!),
                      radius: estimatedPeerReachMeters(
                        rssiDbm: n.rssi?.toDouble(),
                        distanceMeters:
                            mc.distanceMetersTo(n.latitude!, n.longitude!),
                        peerType: n.type,
                        ourSpreadingFactor: mc.selfInfo?.spreadingFactor ?? 7,
                        ourBandwidthKhz: mc.selfInfo?.bandwidthKhz ?? 125.0,
                        ourTxPowerDbm: mc.selfInfo?.txPowerDbm ?? 14,
                      ),
                      useRadiusInMeter: true,
                      color: const Color(0x00000000),
                      borderColor: cs.tertiary.withValues(alpha: .55),
                      borderStrokeWidth: 1.0,
                    ),
                ],
              ),
              // Tiny pins for peers in the current set so the user
              // can correlate covered cells with the nodes that
              // contributed.
              MarkerLayer(
                markers: <Marker>[
                  for (final DiscoveredNode n in withLoc)
                    Marker(
                      point: LatLng(n.latitude!, n.longitude!),
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      child: Semantics(
                        button: true,
                        label: l.nodeMarkerSemantics(
                            n.name.isEmpty ? n.shortId : n.name),
                        child: GestureDetector(
                          onTap: () => _showDetail(mc, n),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.tertiary,
                              border:
                                  Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Marker(
                    point: LatLng(selfLat, selfLon),
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Top-left stat strip — coverage cell count and how old the newest
        // cell is, as one widget so it can be read without a live map.
        Positioned(
          left: 12,
          top: 12,
          child: IgnorePointer(
            child: FabricSurveyStatStrip(
              cellCount: cells.length,
              newestAgo: cells.isEmpty ? null : _newestAgo(mc, l),
            ),
          ),
        ),
        if (widget.frozen)
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer.withValues(alpha: .85),
                borderRadius: BorderRadius.circular(kRadiusMd),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.pause, size: 12, color: cs.onTertiaryContainer),
                  const SizedBox(width: 4),
                  Text(l.globePaused,
                      style: TextStyle(
                          color: cs.onTertiaryContainer,
                          fontSize: context.skin.type.sizeMicro,
                          letterSpacing: 1)),
                ],
              ),
            ),
          ),
        // Top-right toolbar: zoom + reset.
        Positioned(
          right: 12,
          top: 12,
          child: Material(
            color: cs.surface.withValues(alpha: .9),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: mmRadius(context, 6),
              side: BorderSide(color: cs.outline.withValues(alpha: .4)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: l.gridZoomTighter,
                  iconSize: 18,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.add),
                  onPressed: _zoom < _zoomMax
                      ? () {
                          setState(() => _zoom += _zoomStep);
                          _map.move(_map.camera.center, _zoom);
                        }
                      : null,
                ),
                IconButton(
                  tooltip: l.gridZoomWider,
                  iconSize: 18,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.remove),
                  onPressed: _zoom > _zoomMin
                      ? () {
                          setState(() => _zoom -= _zoomStep);
                          _map.move(_map.camera.center, _zoom);
                        }
                      : null,
                ),
                IconButton(
                  tooltip: l.streetMapRecenter,
                  iconSize: 18,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.my_location),
                  onPressed: () => _map.move(LatLng(selfLat, selfLon), _zoom),
                ),
                IconButton(
                  tooltip: _showTiles ? l.mapHideTiles : l.mapShowTiles,
                  iconSize: 18,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: Icon(_showTiles ? Icons.layers : Icons.layers_clear),
                  onPressed: () => setState(() => _showTiles = !_showTiles),
                ),
                IconButton(
                  tooltip: l.fabricResetTooltip,
                  iconSize: 18,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: cells.isEmpty ? null : () => _confirmReset(mc),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The survey's own two facts, in the corner of the map.
///
/// It states the count and the age of the newest cell, and says which of the
/// two states the record is in: cells recorded, or nothing yet. Extracted so
/// the strip can be read in a widget test without laying out a map.
class FabricSurveyStatStrip extends StatelessWidget {
  const FabricSurveyStatStrip({
    super.key,
    required this.cellCount,
    required this.newestAgo,
  });

  final int cellCount;

  /// "12m ago" for the newest recorded cell, or null when nothing is
  /// recorded.
  final String? newestAgo;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final MmSkin skin = context.skin;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: cs.primary.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            l.fabricCoverageCount(cellCount),
            style: TextStyle(
                color: cs.primary,
                fontSize: skin.type.sizeSm,
                letterSpacing: 1,
                fontFamily: skin.type.monoFamily,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            newestAgo == null
                ? l.fabricNothingYet
                : l.fabricNewestCell(newestAgo!),
            style: TextStyle(
                color: cs.onSurfaceVariant, fontSize: skin.type.sizeMicro),
          ),
        ],
      ),
    );
  }
}
