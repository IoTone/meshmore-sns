// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import '../meshcore/chat_message.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/own_location.dart';
import '../theme/theme_controller.dart';
import '../shell/horizontal_drag_claim.dart';
import '../shell/shell_view_request.dart';
import '../ui/mm_components.dart';
import '../ui/mm_page_header.dart';
import '../ui/mm_scaffold.dart';
import '../util/geo.dart' as geo;
import 'elevation_profile_view.dart';
import 'fabric_survey_view.dart';
import 'globe_view.dart';
import 'mesh_tree_view.dart';
import 'node_detail_sheet.dart';
import 'sns_cells_view.dart';
import 'grid_prefs_store.dart';
import 'meshbook_view.dart';
import 'weather_view.dart';
import '../ui/mm_shape.dart';
import 'package:meshcore/meshcore.dart';

/// R117 — the mesh survey: one tab for the views that answer "what does the
/// mesh look like from here, and where has it been heard?". `radial` (R18) is
/// the default and the tab's identity; `fabric` (persisted coverage) and
/// `weather` (environment telemetry) complete the primary set. The rest are
/// behind "More views…" because they answer narrower questions: `globe` (a
/// projection, not a zoom level), `tree` (topology, works with no GPS),
/// `snsCells` (chatter heat) and `elevation` (altitude against landmarks).
/// The view picker is the only way between them: a left/right swipe belongs
/// to the shell's tabs (R109).
enum _GridViewMode {
  radial,
  fabric,
  weather,
  globe,
  tree,
  snsCells,
  elevation,
  meshbook,
}

/// The rows the view picker shows first: the views that answer a question a
/// small mesh actually raises. Everything else is one level down, because ten
/// options in one sheet buried the three that matter.
const List<_GridViewMode> _primaryViews = <_GridViewMode>[
  _GridViewMode.radial,
  _GridViewMode.fabric,
  _GridViewMode.weather,
];

/// The views behind "More views…": still available, deliberately not in the
/// way. Globe and equal grid are two ways to look at the same positions, the
/// tree is topology rather than geography, and the last two are reports.
const List<_GridViewMode> _moreViews = <_GridViewMode>[
  _GridViewMode.globe,
  _GridViewMode.tree,
  _GridViewMode.snsCells,
  _GridViewMode.elevation,
];

extension on _GridViewMode {
  /// Views whose body pans or zooms with a drag. These offer the Swipe ⇄ Pan
  /// toggle: in swipe mode the view is a still picture and a horizontal drag
  /// changes tab; in pan mode it takes every drag and the shell stops paging
  /// (R109).
  ///
  /// The equal grid is not one of them even though it looks like a map: its
  /// tiles are pinned to us (`InteractiveFlag.none`) and its zoom is the cell
  /// stepper, so a toggle there would lock the shell's swipe and hand the drag
  /// to nothing. The views that draw to fit never need the toggle either.
  bool get pansHorizontally => switch (this) {
        _GridViewMode.globe ||
        _GridViewMode.fabric ||
        _GridViewMode.tree ||
        _GridViewMode.snsCells =>
          true,
        _GridViewMode.radial ||
        _GridViewMode.elevation ||
        _GridViewMode.weather ||
        _GridViewMode.meshbook =>
          false,
      };
}

/// What a radar marker can honestly be drawn from.
///
/// A node with a reported position is placed by bearing and distance. A node
/// without one is placed on the ring its signal strength implies, at an angle
/// that is a stable placeholder — the app does not know which way it lies. The
/// marker says so: the glyph is hollow, and the legend states that the angle is
/// not a direction. Drawing both as the same solid dot was the lie.
enum GridMarkerSource { position, signal }

GridMarkerSource gridMarkerSourceFor({
  required bool nodeHasLocation,
  required bool selfHasLocation,
}) =>
    nodeHasLocation && selfHasLocation
        ? GridMarkerSource.position
        : GridMarkerSource.signal;

/// R18 / U9 — the hyperlocal grid: a radial range-ring view of the
/// mesh **fabric** relative to us. Brightness = recency (100 % at
/// register, 0 % at >24 h → removed). Animation semantics: a *known*
/// node (we've had a direct/attributable exchange) **pulses**; a
/// *favourited* contact **blinks rapidly**; plain fabric nodes are
/// static (just brightness). Colour is theme-driven (R14 / R13). On
/// reduce-motion (R13) animations are replaced with a static ring
/// overlay so the same information is carried without flashing.
///
/// Positioning is **hybrid**: GPS bearing+distance when both we and
/// the node advertise a location; else RSSI/SNR → distance ring with
/// a stable per-pubkey hash bearing; else an abstract outer slot.
///
/// Audio/haptic parity (R12) is left for the R12 CueService (U6);
/// the grid currently carries the visual+positional cue only.
///
/// Lives in the HomeShell as the tab after Nodes (issue #4). The shell
/// supplies the title; this widget brings its own toolbar.
class GridScreen extends StatefulWidget {
  const GridScreen({super.key});

  /// The selected view, held for the life of the process: it survives
  /// leaving and re-entering the tab (the PageView disposes the state),
  /// but every app launch starts back on the radar (issue #4). Kept
  /// out of [GridPrefsStore] deliberately for that reason.
  static _GridViewMode _sessionMode = _GridViewMode.radial;

  /// R109 — the name this tab takes in [shellDragClaim] while its Swipe ⇄ Pan
  /// toggle is in pan mode, so the shell knows to stop paging.
  static const String dragHolder = 'grid';

  /// Test seam: back to the launch state (radar).
  @visibleForTesting
  static void resetSession() {
    _sessionMode = _GridViewMode.radial;
  }

  /// Default outer-range scale (km) when the user hasn't moved the
  /// **Range** slider yet. Beyond this distance a GPS-positioned
  /// node clamps to the outer ring.
  static const double defaultRangeKm = 5.0;

  /// Discrete stops for the **Range** slider. Index 0 = literally
  /// "the same room", through wide-area at 5 km (the practical LoRa
  /// SF7-12 outdoor envelope), then City (~metro) and Region. The
  /// **Region** stop is special: its scale is computed at runtime to
  /// frame the farthest known node (see `_effectiveScaleKm`); the km
  /// here is only a fallback when no located nodes are visible.
  static const List<({String label, double km})> rangeStops =
      <({String label, double km})>[
    (label: 'Room', km: 0.025),
    (label: 'Home', km: 0.10),
    (label: 'Block', km: 0.5),
    (label: 'Neighborhood', km: 1.0),
    (label: 'Area', km: 2.0),
    (label: 'Wide', km: 5.0),
    (label: 'City', km: 25.0),
    (label: 'Region', km: 300.0),
  ];

  /// Selectable cadences for the **Play** refresh timer. Pause is
  /// the default; Play with the smallest interval is effectively
  /// live but bounded against thrash on noisy meshes.
  static const List<Duration> playIntervals = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  /// Cutoff for visibility on the grid (R18: > 24 h → removed).
  static const Duration recencyWindow = Duration(hours: 24);

  @override
  State<GridScreen> createState() => _GridScreenState();
}

class _GridScreenState extends State<GridScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tick;
  StreamSubscription<ChatMessage>? _msgSub;

  /// R18's anonymous-channel ripple: anchors a transient centre-out
  /// wave on every incoming channel message. The painter reads this
  /// each frame and decays it over `_rippleDuration`.
  DateTime? _rippleAt;
  static const Duration _rippleDuration = Duration(milliseconds: 900);

  /// Whether the inline legend overlay is shown (info button in app bar).
  bool _legendVisible = false;

  /// R27 — which of the available map views is showing. Seeded from,
  /// and written back to, [GridScreen._sessionMode].
  _GridViewMode _viewMode = GridScreen._sessionMode;

  /// R109 — pan mode, from the toggle that only pannable views show. Off
  /// means swipe mode: the view is held still and a horizontal drag changes
  /// tab. Starts off on every visit, so arriving by a swipe can never leave
  /// the shell locked under the finger mid-drag.
  bool _panMode = false;

  /// The map takes horizontal drags only when it both pans and is in pan
  /// mode; anything else hands the drag to the shell.
  bool get _mapOwnsDrags => _panMode && _viewMode.pansHorizontally;

  /// Maximum hit-test radius (logical px) for tap-to-select on the grid.
  static const double _tapRadius = 28.0;

  /// Pause / play state. Starts **live**: the view follows `mc.nodes`
  /// and the transport button says so, which is what the screen was
  /// already doing (`_userInteracted` was false) while the old status
  /// line printed "paused". Tapping pause freezes the snapshot; play
  /// restarts the periodic refresh at `_interval`.
  bool _live = true;
  bool _userInteracted = false;
  Duration _interval = const Duration(seconds: 15);
  List<DiscoveredNode>? _snapshot;
  Timer? _refreshTimer;

  /// Index into [GridScreen.rangeStops] for the outer-ring scale.
  /// Default stays at **Wide** (5 km) even though City/Region sit
  /// beyond it on the slider.
  int _scaleIndex =
      GridScreen.rangeStops.indexWhere((s) => s.label == 'Wide');

  @override
  void initState() {
    super.initState();
    _tick = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4), // arbitrary; we read .value
    )..repeat();
    final MeshcoreController mc = context.read<MeshcoreController>();
    _snapshot = List<DiscoveredNode>.of(mc.nodes); // initial paused frame
    _msgSub =
        mc.incomingChannelMessages.listen((_) {
      if (mounted) _rippleAt = DateTime.now();
    });
    // R109 — pan mode is per visit, not per session: the view mode is
    // remembered, the gesture lock is not.
    _panMode = false;
    _publishDragClaim();
    // Restore last-used grid preferences (scale / orientation / refresh)
    // so they don't reset when re-opening the grid. The view itself is
    // session state — see [GridScreen._sessionMode].
    GridPrefsStore.load().then((GridPrefs? p) {
      if (p == null || !mounted) return;
      setState(() {
        if (p.scaleIndex >= 0 &&
            p.scaleIndex < GridScreen.rangeStops.length) {
          _scaleIndex = p.scaleIndex;
        }
        _interval = Duration(seconds: p.intervalSec.clamp(1, 600));
        // Don't auto-restore `live` — the screen intentionally opens paused
        // (a fresh snapshot), and live restore is handled by the existing
        // follow-mc-until-interacted behaviour.
      });
    });
  }

  void _savePrefs() {
    GridPrefsStore.save(GridPrefs(
      scaleIndex: _scaleIndex,
      live: _live,
      intervalSec: _interval.inSeconds,
    ));
  }

  void _selectMode(_GridViewMode m) {
    setState(() => _viewMode = m);
    GridScreen._sessionMode = m;
    _publishDragClaim();
  }

  /// The second level of the picker: the views that are worth keeping but
  /// do not earn a primary slot.
  void _showMoreViews(BuildContext context, AppLocalizations l) {
    showMmPicker<_GridViewMode>(
      context: context,
      title: l.gridMoreViews,
      current: _viewMode,
      items: <MmPickerItem<_GridViewMode>>[
        for (final _GridViewMode v in _moreViews)
          MmPickerItem<_GridViewMode>.option(
              v, _longLabel(v, l), icon: _iconForMode(v)),
        MmPickerItem<_GridViewMode>.option(_GridViewMode.meshbook,
            _longLabel(_GridViewMode.meshbook, l),
            icon: _iconForMode(_GridViewMode.meshbook)),
      ],
    ).then((_GridViewMode? m) {
      if (m != null && mounted) _selectMode(m);
    });
  }

  void _togglePanMode() {
    setState(() => _panMode = !_panMode);
    _publishDragClaim();
  }

  /// Tells the shell whether this tab owns horizontal drags right now.
  void _publishDragClaim() {
    if (_mapOwnsDrags) {
      shellDragClaim.hold(GridScreen.dragHolder);
    } else {
      shellDragClaim.release(GridScreen.dragHolder);
    }
  }

  @override
  void dispose() {
    // The shell must page again as soon as this tab is gone, even if it was
    // left in pan mode.
    shellDragClaim.release(GridScreen.dragHolder);
    _refreshTimer?.cancel();
    _msgSub?.cancel();
    _tick.dispose();
    super.dispose();
  }

  void _refreshSnapshot() {
    if (!mounted) return;
    setState(() => _snapshot = List<DiscoveredNode>.of(
        context.read<MeshcoreController>().nodes));
  }

  /// Icon for the AppBar picker entry / button. Each mode has a
  /// distinctive Material symbol so the dropdown reads as glanceable
  /// regardless of language.
  /// Views that read a time-ordered snapshot, so the transport bar means
  /// something. The three report views (altitude, weather, activity) are
  /// always current and have no transport.
  /// The bar carries a refresh cadence on the radar (the one view that shows a
  /// snapshot in time) and the range scale on the two views that use it.
  /// "Play" over a map meant "freeze the picture", which is not transport.
  bool get _hasTransport => _viewMode == _GridViewMode.radial;

  /// Whether the view plots nodes, and therefore whether a node count means
  /// anything above it. A weather report over "3 in mesh · 2 known" was three
  /// counts about something the view does not show.
  bool get _plotsNodes => switch (_viewMode) {
        _GridViewMode.radial ||
        _GridViewMode.fabric ||
        _GridViewMode.globe ||
        _GridViewMode.tree ||
        _GridViewMode.snsCells =>
          true,
        _GridViewMode.weather ||
        _GridViewMode.elevation ||
        _GridViewMode.meshbook =>
          false,
      };

  /// Views that render a legend, so the info button exists only there.
  bool get _hasLegend => switch (_viewMode) {
        _GridViewMode.radial ||
        _GridViewMode.fabric ||
        _GridViewMode.elevation ||
        _GridViewMode.tree ||
        _GridViewMode.snsCells =>
          true,
        _ => false,
      };

  /// The range scale is the radar's ring scale, and only the radar draws
  /// rings. It used to be editable only inside the radar branch, so the cell
  /// grid inherited a value it could not change; that view is gone.
  bool get _hasRange => _viewMode == _GridViewMode.radial;


  /// Bottom bar: transport (play/pause + interval) and, in the two views
  /// that consume it, the range scale. Kept off the header so switching
  /// views is one control, and so play/pause is not a per-view toggle
  /// sitting next to the view's own name.
  Widget _transportBar(
      AppLocalizations l, ColorScheme cs, String scaleLabel, String scaleValue) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outline.withValues(alpha: .2))),
      ),
      // Wrap, not Row: on a 320 dp phone the transport and the range chip
      // together overflowed the bar by 26 px. Wrap lays them out at their
      // own width and drops the range chip to a second line when it must.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            if (_viewMode == _GridViewMode.radial)
              IconButton(
                tooltip: _live ? l.gridPauseTooltip : l.gridPlayTooltip,
                icon: Icon(_live ? Icons.pause : Icons.play_arrow),
                onPressed: _togglePlay,
              ),
            if (_viewMode != _GridViewMode.radial) const SizedBox.shrink(),
            if (_viewMode == _GridViewMode.radial)
            Tooltip(
              message: l.gridIntervalTooltip,
              child: InkWell(
                onTap: () async {
                  final Duration? d = await showMmPicker<Duration>(
                    context: context,
                    title: l.gridIntervalTooltip,
                    current: _interval,
                    items: <MmPickerItem<Duration>>[
                      for (final Duration d in GridScreen.playIntervals)
                        MmPickerItem<Duration>.option(d, _intervalLabel(d)),
                    ],
                  );
                  if (d != null) _changeInterval(d);
                },
                child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(_intervalLabel(_interval),
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
                ),
              ),
            ),
            if (_hasRange)
              Tooltip(
                message: l.gridRange,
                child: InkWell(
                onTap: () async {
                  final int? i = await showMmPicker<int>(
                    context: context,
                    title: l.gridRange,
                    current: _scaleIndex,
                    items: <MmPickerItem<int>>[
                      for (int k = 0; k < GridScreen.rangeStops.length; k++)
                        MmPickerItem<int>.option(k, _rangeLabel(l, k)),
                    ],
                  );
                  if (i != null) {
                    setState(() {
                      _userInteracted = true;
                      _scaleIndex = i;
                    });
                    _savePrefs();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Icon + value, not "Range · value": at 2.0x text the
                      // prefix alone was 65 px wider than the bar. The
                      // tooltip carries the word.
                      Icon(Icons.straighten,
                          size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(scaleLabel,
                          style: TextStyle(color: cs.onSurfaceVariant)),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static IconData _iconForMode(_GridViewMode m) => switch (m) {
        _GridViewMode.radial => Icons.radar,
        _GridViewMode.globe => Icons.public,
        _GridViewMode.fabric => Icons.view_quilt,
        _GridViewMode.elevation => Icons.terrain,
        _GridViewMode.tree => Icons.account_tree,
        _GridViewMode.snsCells => Icons.local_fire_department,
        _GridViewMode.weather => Icons.thermostat,
        _GridViewMode.meshbook => Icons.menu_book_outlined,
      };


  static String _longLabel(_GridViewMode m, AppLocalizations l) =>
      switch (m) {
        _GridViewMode.radial => l.gridViewRadial,
        _GridViewMode.globe => l.gridViewGlobe,
        _GridViewMode.fabric => l.gridViewFabric,
        _GridViewMode.elevation => l.gridViewElevation,
        _GridViewMode.tree => l.gridViewTree,
        _GridViewMode.snsCells => l.gridViewSnsCells,
        _GridViewMode.weather => l.gridViewWeather,
        _GridViewMode.meshbook => l.gridViewMeshbook,
      };


  void _togglePlay() {
    setState(() {
      _userInteracted = true;
      _live = !_live;
    });
    _refreshTimer?.cancel();
    if (_live) {
      _refreshSnapshot(); // immediate snap on Play
      _refreshTimer =
          Timer.periodic(_interval, (_) => _refreshSnapshot());
    } else {
      // Pause taps: re-capture current state so the frozen view
      // matches what the user sees at the moment of pause.
      _refreshSnapshot();
    }
  }

  void _changeInterval(Duration d) {
    setState(() {
      _userInteracted = true;
      _interval = d;
    });
    _savePrefs();
    if (_live) {
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(d, (_) => _refreshSnapshot());
    }
  }

  String _intervalLabel(Duration d) {
    if (d.inMinutes >= 1) return '${d.inMinutes} min';
    return '${d.inSeconds}s';
  }

  /// Localised label for the current Range slider stop. The
  /// stop list itself stays as English keys (matching the asset /
  /// codepath identity); the user-facing label is translated.
  String _rangeLabel(AppLocalizations l, int idx) {
    return switch (idx) {
      0 => l.gridRangeRoom,
      1 => l.gridRangeHome,
      2 => l.gridRangeBlock,
      3 => l.gridRangeNeighborhood,
      4 => l.gridRangeArea,
      5 => l.gridRangeWide,
      6 => l.gridRangeCity,
      _ => l.gridRangeRegion,
    };
  }

  /// The outer-ring scale in km for the current stop. Most stops use
  /// their fixed km; the **Region** stop (the last) instead frames the
  /// farthest located node so it shows the whole known mesh extent,
  /// falling back to the stop's km when no node has a location.
  double _effectiveScaleKm(
      double? selfLat, double? selfLon, List<DiscoveredNode> visible) {
    final double base = GridScreen.rangeStops[_scaleIndex].km;
    final bool isRegion = _scaleIndex == GridScreen.rangeStops.length - 1;
    if (!isRegion || selfLat == null || selfLon == null) return base;
    double maxKm = 0;
    for (final DiscoveredNode n in visible) {
      if (!n.hasLocation) continue;
      final double km = geo.haversineMeters(
              selfLat, selfLon, n.latitude!, n.longitude!) /
          1000.0;
      if (km > maxKm) maxKm = km;
    }
    if (maxKm <= 0) return base;
    // Pad 10% so the farthest node sits just inside the rim; clamp to
    // a sane window.
    return (maxKm * 1.1).clamp(50.0, 2000.0);
  }

  /// Pretty distance label for a scale stop (e.g. "25 m" / "5 km").
  String _rangeValue(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(0)} km';
  }

  /// Cheap "did the live node list change" check for the
  /// auto-track-until-interaction path. We compare by length first
  /// (the cheap case) then identity per index — both nodes lists
  /// are managed by the controller which doesn't mutate in place.
  bool _listEquals(
      List<DiscoveredNode>? a, List<DiscoveredNode> b) {
    if (a == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// Hit-test the visible node fleet against a tap. Picks the
  /// closest node within `_tapRadius`. Returns null if none match.
  DiscoveredNode? _hitTest({
    required Offset tap,
    required Size area,
    required List<DiscoveredNode> visible,
    required double? selfLat,
    required double? selfLon,
  }) {
    final Offset center = Offset(area.width / 2, area.height / 2);
    final double maxR = math.min(area.width, area.height) / 2 - 24;
    if (maxR <= 0) return null;
    final double scaleKm = _effectiveScaleKm(selfLat, selfLon, visible);
    DiscoveredNode? best;
    double bestDist = double.infinity;
    for (final DiscoveredNode n in visible) {
      final Offset p = _GridPainter.positionFor(
        node: n,
        center: center,
        maxR: maxR,
        selfLat: selfLat,
        selfLon: selfLon,
        scaleKm: scaleKm,
      );
      final double d = (p - tap).distance;
      if (d <= _tapRadius && d < bestDist) {
        best = n;
        bestDist = d;
      }
    }
    return best;
  }

  Future<void> _showDetail(
      BuildContext ctx, MeshcoreController mc, DiscoveredNode n) async {
    await showModalBottomSheet<void>(
      context: ctx,
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
        recentDms: mc.dmHistoryFor(n.pubKeyHex),
        proximity: mc.proximityFor(n),
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
    final ThemeController tc = context.watch<ThemeController>();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool ready = mc.state == MeshcoreConnectionState.ready;

    // Until the user touches any control, the snapshot follows the
    // live `mc.nodes` automatically — that way a freshly-connected
    // user actually sees adverts populate the view. As soon as they
    // tap pause/play/scale (sets `_userInteracted = true`), the
    // snapshot freezes per the pause semantics.
    if (!_userInteracted && !_listEquals(_snapshot, mc.nodes)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_userInteracted) {
          setState(() => _snapshot =
              List<DiscoveredNode>.of(mc.nodes));
        }
      });
    }
    final List<DiscoveredNode> source = _snapshot ?? mc.nodes;

    // Filter visible nodes — within the 24 h recency window AND not
    // ourselves (we shouldn't appear in our own fabric; the centre
    // marker is us). `ownPubKeyHex` is null until SelfInfo arrives,
    // in which case nothing is filtered.
    final int nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final int windowSec = GridScreen.recencyWindow.inSeconds;
    final String? selfPk = mc.ownPubKeyHex;
    // Not connected → no nodes at all (issue #4): whatever the cache
    // holds is not what the mesh around us is doing right now.
    final List<DiscoveredNode> visible = <DiscoveredNode>[
      if (ready)
        for (final DiscoveredNode n in source)
          if (nowUnix - n.lastHeardUnix < windowSec &&
              n.pubKeyHex != selfPk)
            n
    ];

    // R22 — own location must be a single source of truth. Reading
    // `selfInfo` directly skipped the device-first / phone-fallback rule in
    // `MeshcoreController.ownLocation`, so whenever the radio reported
    // (0,0) — GPS off, no lock, or a hidden position — every node fell
    // through to the arbitrary RSSI-ring / hash-bearing placement even
    // though a good phone fix was cached.
    final OwnLocation? self = mc.ownLocation;
    final double scaleKm =
        _effectiveScaleKm(self?.latitude, self?.longitude, visible);
    final AppLocalizations l = AppLocalizations.of(context);
    final String scaleLabel = _rangeLabel(l, _scaleIndex);
    final String scaleValue = _rangeValue(scaleKm);

    return MmScaffold(
      child: Column(
        children: <Widget>[
      MmPageHeader(title: l.gridTitle),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
        child: Row(
        children: <Widget>[
          // R88 — one control on the left: the current view's own icon,
          // short name and a chevron. The separate caption that used to
          // sit above it said the same thing in the same toolbar. The
          // menu groups the ten views by what they show (peers, surveys,
          // reports) instead of listing them as ten peers.
          // R104 — a labelled sheet, not a menu: ten views in three groups
          // with a check state is a list, and a menu cannot scroll, cannot
          // say "Peers" as a group, and opens away from its own button.
          Tooltip(
            message: l.gridViewPicker,
            child: InkWell(
              onTap: () async {
                final _GridViewMode? m = await showMmPicker<_GridViewMode>(
                  context: context,
                  title: l.gridViewPicker,
                  current: _viewMode,
                  items: <MmPickerItem<_GridViewMode>>[
                    for (final _GridViewMode v in _primaryViews)
                      MmPickerItem<_GridViewMode>.option(
                          v, _longLabel(v, l), icon: _iconForMode(v)),
                    // The map is a tab, not a grid view: this row leaves for
                    // it instead of showing a second copy of the same widget
                    // inside the grid (the street map used to do exactly that).
                    MmPickerItem<_GridViewMode>.action(
                      l.gridOpenMap,
                      icon: Icons.map_outlined,
                      onAction: () {
                        if (!mounted) return;
                        context.read<ShellViewRequest?>()?.openMap();
                      },
                    ),
                    MmPickerItem<_GridViewMode>.action(
                      l.gridMoreViews,
                      icon: Icons.more_horiz,
                      onAction: () {
                        if (mounted) _showMoreViews(context, l);
                      },
                    ),
                  ],
                );
                if (m != null) _selectMode(m);
              },
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(_iconForMode(_viewMode), size: 20),
                  const SizedBox(width: 8),
                  // The long name, not the four-letter code: "Weather
                  // (environment)" tells you where you are, "WX" does not.
                  Flexible(
                    child: Text(_longLabel(_viewMode, l),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: context.skin.type.sizeBodyLg, fontWeight: FontWeight.w600)),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
            ),
          ),
          // R109 — Swipe ⇄ Pan, only where the view has a drag of its own.
          // In swipe mode the view is held still so the drag is the shell's;
          // in pan mode the view takes it and the shell stops paging.
          if (_viewMode.pansHorizontally)
            IconButton(
              key: const ValueKey<String>('grid-pan-toggle'),
              tooltip:
                  _panMode ? l.gridPanModeTooltip : l.gridSwipeModeTooltip,
              isSelected: _panMode,
              icon: const Icon(Icons.swipe),
              selectedIcon: const Icon(Icons.pan_tool),
              onPressed: _togglePanMode,
            ),
          const Spacer(),
          // Only the five views that draw a legend get the button, so it
          // can no longer be a silent no-op in the other five.
          if (_hasLegend)
            IconButton(
              tooltip: _legendVisible ? l.gridHideLegend : l.gridShowLegend,
              icon: Icon(_legendVisible ? Icons.info : Icons.info_outline),
              onPressed: () =>
                  setState(() => _legendVisible = !_legendVisible),
            ),
        ],
      ),
      ),
      // Counts for every view. They used to be printed inside the radar
      // branch only, and the play state rode along in the same sentence
      // even though the transport now says it.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            ready && _plotsNodes
                ? l.gridStatusCounts(visible.length, mc.known.length,
                    mc.favorites.length)
                : ready
                    ? ''
                    : l.gridStatusOffline,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeBody),
          ),
        ),
      ),
      // The radar says it in its own centre; every other view gets
      // the strip.
      if (!ready && _viewMode != _GridViewMode.radial)
        _NotConnectedStrip(cs: cs, label: l.gridNotConnected),
      // The picker drives mode; the body renders the chosen mode's widget
      // under its Swipe ⇄ Pan state (R109).
      Expanded(
        child: switch (_viewMode) {
        _GridViewMode.globe => GlobeView(
            filteredNodes: visible,
            frozen: !_live && _userInteracted,
            interactive: _panMode,
          ),
        _GridViewMode.fabric => Stack(
            children: <Widget>[
              FabricSurveyView(
                filteredNodes: visible,
                frozen: !_live && _userInteracted,
                interactive: _panMode,
              ),
              if (_legendVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _FabricLegend(cs: cs, l: l),
                ),
            ],
          ),
        _GridViewMode.elevation => Stack(
            children: <Widget>[
              ElevationProfileView(filteredNodes: visible),
              if (_legendVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _FujiLegend(cs: cs, l: l),
                ),
            ],
          ),
        // Tree mode overlays the legend strip on top of the canvas
        // so the info button does something here (the radial branch
        // is the only other place that hosts a legend). Stack lets
        // the legend dismiss without restructuring the layout.
        _GridViewMode.tree => Stack(
            children: <Widget>[
              MeshTreeView(
                filteredNodes: visible,
                frozen: !_live && _userInteracted,
              ),
              if (_legendVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _TreeLegend(cs: cs, l: l),
                ),
            ],
          ),
        _GridViewMode.snsCells => Stack(
            children: <Widget>[
              SnsCellsView(
                filteredNodes: visible,
                frozen: !_live && _userInteracted,
                interactive: _panMode,
              ),
              if (_legendVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _SnsCellsLegend(cs: cs, l: l),
                ),
            ],
          ),
        _GridViewMode.weather => WeatherView(filteredNodes: visible),
        _GridViewMode.meshbook => const MeshbookView(),
        _GridViewMode.radial => Column(
          // R109 — the radar never pans, so it is always the shell's drag;
          // no toggle, no hold-still wrapper.
        children: <Widget>[
          // The range control lives in the bottom bar now, where the
          // cells view can reach it too.
          if (_legendVisible)
            _GridLegend(cs: cs, scaleKm: scaleKm, l: l),
          const Divider(height: 1),
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  // Offline still paints the rings — an empty radar with
                  // the message over it, not a blank page (issue #4).
                  child: visible.isEmpty && ready
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        l.gridEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (BuildContext _, BoxConstraints c) {
                      final Size area =
                          Size(c.maxWidth, c.maxHeight);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (TapDownDetails d) {
                          final DiscoveredNode? hit = _hitTest(
                            tap: d.localPosition,
                            area: area,
                            visible: visible,
                            selfLat: self?.latitude,
                            selfLon: self?.longitude,
                          );
                          if (hit != null) {
                            _showDetail(context, mc, hit);
                          }
                        },
                        child: AnimatedBuilder(
                          animation: _tick,
                          builder: (BuildContext _, Widget? __) =>
                              CustomPaint(
                            size: area,
                            painter: _GridPainter(
                              nodes: visible,
                              favorites: mc.favorites,
                              known: mc.known,
                              selfLat: self?.latitude,
                              selfLon: self?.longitude,
                              nowUnix: nowUnix,
                              windowSec: windowSec,
                              tick: _tick.value,
                              reduceMotion: tc.reduceMotion,
                              accent: cs.primary,
                              subtle: cs.onSurface.withValues(alpha: .12),
                              ringStroke:
                                  cs.outline.withValues(alpha: .35),
                              base: cs.onSurfaceVariant,
                              type: context.skin.type,
                              rippleAt: _rippleAt,
                              rippleDuration: _rippleDuration,
                              scaleKm: scaleKm,
                              ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (!ready)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: _NotConnectedStrip(
                            cs: cs, label: l.gridNotConnected),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      }),
      if (_hasTransport) _transportBar(l, cs, scaleLabel, scaleValue),
        ],
      ),
    );
  }
}

/// Toggleable legend overlay strip. Explains what the rings, the
/// node glyphs, the animations, and the ripple mean — every cue is
/// in here so a new user can decode the grid at a glance.
/// The rest of a legend, behind one tap. A legend explains glyphs; the
/// sentences that explain the animations belong in a dialog, not on the canvas.
class _LegendMore extends StatelessWidget {
  const _LegendMore({required this.title, required this.lines});
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Builder(
        builder: (BuildContext context) => MmAction(
          dense: true,
          label: title,
          onPressed: () => showDialog<void>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final String line in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(line,
                          style: TextStyle(
                              color: cs.onSurface,
                              fontSize: context.skin.type.sizeBody)),
                    ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(MaterialLocalizations.of(c).closeButtonLabel),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _GridLegend extends StatelessWidget {
  const _GridLegend(
      {required this.cs, required this.scaleKm, required this.l});
  final ColorScheme cs;
  final double scaleKm;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 14, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontSize: context.skin.type.sizeBody,
                        height: 1.35)),
              ),
            ],
          ),
        );
    final String scaleValueDisplay = scaleKm < 1
        ? '${(scaleKm * 1000).round()} m'
        : '${scaleKm.toStringAsFixed(0)} km';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: mmRadius(context, 8),
        border: Border.all(color: cs.outline.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.gridLegend,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: context.skin.type.sizeSm,
                  letterSpacing: 3)),
          const SizedBox(height: 6),
          row(Icons.adjust, l.gridLegendRingsShort),
          row(Icons.my_location, l.gridLegendSelfShort),
          row(Icons.circle, l.gridLegendDotShort),
          row(Icons.blur_circular, l.gridLegendSignalOnly),
          row(Icons.radio_button_checked, l.gridLegendKnownShort),
          row(Icons.star, l.gridLegendFavShort),
          row(Icons.waves, l.gridLegendRippleShort),
          row(Icons.touch_app, l.gridLegendTapShort),
          _LegendMore(title: l.gridLegendMore, lines: <String>[
            l.gridLegendRings(scaleValueDisplay),
            l.gridLegendSelf,
            l.gridLegendDot,
            l.gridLegendKnown,
            l.gridLegendFavourite,
            l.gridLegendRipple,
            l.gridLegendTap,
          ]),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// "Not Connected to Mesh" — centred on the empty radar, a strip atop
/// every other view. Text + icon, never colour alone (R13).
class _NotConnectedStrip extends StatelessWidget {
  const _NotConnectedStrip({required this.cs, required this.label});

  final ColorScheme cs;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: .85),
        borderRadius: mmRadius(context, 8),
        border: Border.all(color: cs.error.withValues(alpha: .6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.link_off, size: 18, color: cs.error),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: context.skin.type.sizeBodyLg,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.nodes,
    required this.favorites,
    required this.known,
    required this.selfLat,
    required this.selfLon,
    required this.nowUnix,
    required this.windowSec,
    required this.tick,
    required this.reduceMotion,
    required this.accent,
    required this.subtle,
    required this.ringStroke,
    required this.base,
    required this.type,
    required this.rippleAt,
    required this.rippleDuration,
    required this.scaleKm,
  });

  final List<DiscoveredNode> nodes;
  final Set<String> favorites;
  final Set<String> known;
  final double? selfLat;
  final double? selfLon;
  final int nowUnix;
  final int windowSec;
  final double tick; // 0..1, repeating
  final bool reduceMotion;
  final Color accent;
  final Color subtle;
  final Color ringStroke;
  final Color base;

  /// The active skin's type system: the ring labels are painted, not built,
  /// so the ladder reaches them through this.
  final MmType type;
  final DateTime? rippleAt;
  final Duration rippleDuration;
  final double scaleKm;

  static bool _selfHasGpsStatic(double? lat, double? lon) =>
      lat != null && lon != null && !(lat == 0 && lon == 0);

  /// Whether this node is placed by a reported position or only by signal.
  static GridMarkerSource _sourceFor(
          DiscoveredNode node, double? selfLat, double? selfLon) =>
      gridMarkerSourceFor(
          nodeHasLocation: node.hasLocation,
          selfHasLocation: _selfHasGpsStatic(selfLat, selfLon));

  /// Stable arbitrary angle from pubkey (so a node doesn't jump).
  static double _hashAngle(String pubKeyHex) {
    final String head =
        pubKeyHex.length >= 4 ? pubKeyHex.substring(0, 4) : pubKeyHex;
    final int v = int.tryParse(head, radix: 16) ?? 0;
    return (v / 0xFFFF) * 2 * math.pi;
  }

  /// RSSI → ring index 0 (near) / 1 (mid) / 2 (far).
  static int _ringFromRssi(int? rssi) {
    if (rssi == null) return 2;
    if (rssi >= -60) return 0;
    if (rssi >= -90) return 1;
    return 2;
  }

  /// Pure position math — same logic the painter uses, exposed so
  /// `GridScreen` can hit-test taps against the rendered fleet
  /// without re-deriving it (no animation phase is involved, so this
  /// is stable per node per snapshot). [scaleKm] is the outer-ring
  /// scale (km) selected via the Range slider.
  static Offset positionFor({
    required DiscoveredNode node,
    required Offset center,
    required double maxR,
    required double? selfLat,
    required double? selfLon,
    required double scaleKm,
  }) {
    final bool selfGps = _selfHasGpsStatic(selfLat, selfLon);
    final double angle;
    final double radius;
    if (selfGps && node.hasLocation) {
      final double dKm = geo.haversineMeters(
              selfLat!, selfLon!, node.latitude!, node.longitude!) /
          1000.0;
      radius = (dKm / scaleKm).clamp(0.05, 1.0) * maxR;
      angle = geo.bearingRadians(
          selfLat, selfLon, node.latitude!, node.longitude!);
    } else if (node.rssi != null) {
      final int ringIdx = _ringFromRssi(node.rssi);
      radius = maxR * <double>[1 / 3, 2 / 3, 1.0][ringIdx];
      angle = _hashAngle(node.pubKeyHex);
    } else {
      radius = maxR;
      angle = _hashAngle(node.pubKeyHex);
    }
    return center +
        Offset(radius * math.sin(angle), -radius * math.cos(angle));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double maxR = math.min(size.width, size.height) / 2 - 24;
    if (maxR <= 0) return;

    // Concentric range rings — slightly thicker stroke than 1 so
    // they survive low-contrast themes; per-ring distance label on
    // the +X axis so the user can read the scale at a glance.
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ringStroke;
    const List<double> ringFracs = <double>[1 / 3, 2 / 3, 1.0];
    for (final double f in ringFracs) {
      canvas.drawCircle(center, maxR * f, ring);
    }
    // Ring labels. Position each label just inside the ring on the
    // right (+X) axis so they don't collide with node markers in
    // typical fleets.
    for (final double f in ringFracs) {
      final double meters = scaleKm * f * 1000;
      final String label = meters < 1000
          ? '${meters.round()} m'
          : '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
              color: base,
              fontSize: type.sizeMicro,
              fontFamily: type.monoFamily),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(center.dx + maxR * f - tp.width - 4,
            center.dy - tp.height - 2),
      );
    }
    // Cross-hair guides (faint).
    final Paint cross = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = subtle;
    canvas.drawLine(Offset(center.dx - maxR, center.dy),
        Offset(center.dx + maxR, center.dy), cross);
    canvas.drawLine(Offset(center.dx, center.dy - maxR),
        Offset(center.dx, center.dy + maxR), cross);

    // Self marker.
    canvas.drawCircle(center, 5, Paint()..color = accent);
    canvas.drawCircle(center, 9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = accent.withValues(alpha: .6));

    // R18 anonymous-channel ripple: an incoming channel message is
    // not attributable to a node, so draw a transient centre-out
    // wave instead of a node marker. Honours reduce-motion: skipped.
    if (!reduceMotion && rippleAt != null) {
      final int ageMs =
          DateTime.now().difference(rippleAt!).inMilliseconds;
      final double t = ageMs / rippleDuration.inMilliseconds;
      if (t >= 0 && t < 1) {
        canvas.drawCircle(
          center,
          maxR * t,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = accent.withValues(alpha: (1 - t) * 0.7),
        );
      }
    }

    for (final DiscoveredNode n in nodes) {
      // Recency → brightness (linear 24h decay).
      final double age = (nowUnix - n.lastHeardUnix) / windowSec;
      final double bright = (1.0 - age).clamp(0.0, 1.0);
      if (bright <= 0) continue;

      final Offset p = positionFor(
        node: n,
        center: center,
        maxR: maxR,
        selfLat: selfLat,
        selfLon: selfLon,
        scaleKm: scaleKm,
      );

      final bool isFav = favorites.contains(n.pubKeyHex);
      final bool isKnown = known.contains(n.pubKeyHex);

      // Animation phases.
      double scale = 1.0;
      double opacityMul = 1.0;
      if (!reduceMotion) {
        if (isFav) {
          // Rapid blink ~5 Hz: on for half the cycle.
          final double phase = (tick * 5 * 2) % 1;
          opacityMul = phase < 0.5 ? 1.0 : 0.35;
        } else if (isKnown) {
          // Pulse ~0.7 Hz: gentle sine.
          final double s =
              0.5 + 0.5 * math.sin(tick * 2 * math.pi * 2.8);
          scale = 0.9 + 0.4 * s;
        }
      }

      final double r0 = (isFav || isKnown ? 6.0 : 4.0) * scale;
      final Color c = accent.withValues(alpha: bright * opacityMul);
      final GridMarkerSource source = _sourceFor(n, selfLat, selfLon);
      if (source == GridMarkerSource.position) {
        canvas.drawCircle(p, r0, Paint()..color = c);
      } else {
        // Hollow: a position we do not have is not a position. The ring sits
        // on the band its signal implies; the angle is a placeholder.
        canvas.drawCircle(p, r0 + 1, Paint()..color = c.withValues(alpha: .18));
        canvas.drawCircle(
          p,
          r0 + 1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = c,
        );
      }

      // Reduce-motion accessibility ring: known = thin ring; fav =
      // thicker ring (info preserved without animation).
      if (reduceMotion && (isKnown || isFav)) {
        canvas.drawCircle(
          p,
          r0 + (isFav ? 5 : 3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = isFav ? 2 : 1.2
            ..color = accent.withValues(alpha: bright * .8),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.nodes != nodes ||
      old.favorites != favorites ||
      old.known != known ||
      old.tick != tick ||
      old.reduceMotion != reduceMotion ||
      old.rippleAt != rippleAt ||
      old.scaleKm != scaleKm ||
      old.type != type;
}

/// R50 — info-button legend specifically for the Mesh Tree view.
/// Different from the radial legend ([_GridLegend]) because the tree
/// has no rings, no scale, and the node glyphs mean something
/// different (role × halo state instead of recency).
class _TreeLegend extends StatelessWidget {
  const _TreeLegend({required this.cs, required this.l});
  final ColorScheme cs;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String text, {Color? colour}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 14, color: colour ?? cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontSize: context.skin.type.sizeBody,
                        height: 1.35)),
              ),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: mmRadius(context, 8),
        border: Border.all(color: cs.outline.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.meshTreeLegendTitle,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: context.skin.type.sizeSm,
                  letterSpacing: 3)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(l.meshTreeLegendDesc,
                style: TextStyle(
                    color: cs.onSurface,
                    fontSize: context.skin.type.sizeBody,
                    height: 1.35)),
          ),
          row(Icons.my_location, l.treeSelfShort, colour: cs.primary),
          row(Icons.crop_square, l.treeRepeaterShort, colour: cs.tertiary),
          row(Icons.diamond, l.treeRoomShort, colour: cs.tertiary),
          row(Icons.circle, l.treeChatShort, colour: cs.primary),
          row(Icons.sensors, l.treeSensorShort,
              colour: cs.primary.withValues(alpha: .55)),
          row(Icons.more_horiz, l.treeFloodShort,
              colour: cs.onSurfaceVariant),
          row(Icons.arrow_forward, l.treeArrowShort),
          _LegendMore(title: l.gridLegendMore, lines: <String>[
            l.meshTreeLegendDesc,
            l.meshTreeLegendSelf,
            l.meshTreeLegendRepeater,
            l.meshTreeLegendRoom,
            l.meshTreeLegendChat,
            l.meshTreeLegendSensor,
            l.meshTreeLegendFlood,
            l.meshTreeLegendFloat,
            l.meshTreeLegendArrow,
            l.meshTreeLegendInteract,
          ]),
        ],
      ),
    );
  }
}

/// R50 — info-button legend specifically for the Fabric Survey view.
/// Different from the radial legend ([_GridLegend]) and the tree
/// legend ([_TreeLegend]) — explains the coverage quilt cells,
/// recency tiers, and the peer markers.
class _FabricLegend extends StatelessWidget {
  const _FabricLegend({required this.cs, required this.l});
  final ColorScheme cs;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String text, {Color? colour}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 14, color: colour ?? cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontSize: context.skin.type.sizeBody,
                        height: 1.35)),
              ),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: mmRadius(context, 8),
        border: Border.all(color: cs.outline.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.fabricLegendTitle,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: context.skin.type.sizeSm,
                  letterSpacing: 3)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(l.fabricLegendDesc,
                style: TextStyle(
                    color: cs.onSurface,
                    fontSize: context.skin.type.sizeBody,
                    height: 1.35)),
          ),
          row(Icons.grid_view, l.fabricCellShort, colour: cs.secondary),
          row(Icons.gradient, l.fabricRecencyShort, colour: cs.secondary),
          row(Icons.place, l.fabricMarkerShort, colour: cs.tertiary),
          row(Icons.my_location, l.gridLegendSelfShort, colour: cs.primary),
          _LegendMore(title: l.gridLegendMore, lines: <String>[
            l.fabricLegendDesc,
            l.fabricLegendCell,
            l.fabricLegendRecency,
            l.fabricLegendMarker,
            l.fabricLegendSelf,
            l.fabricLegendReset,
          ]),
        ],
      ),
    );
  }
}

/// Info-button legend for the Fujiさん elevation view.
class _FujiLegend extends StatelessWidget {
  const _FujiLegend({required this.cs, required this.l});
  final ColorScheme cs;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String text, {Color? colour}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 14, color: colour ?? cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontSize: context.skin.type.sizeBody,
                        height: 1.35)),
              ),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: mmRadius(context, 8),
        border: Border.all(color: cs.outline.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.fujiLegendTitle,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: context.skin.type.sizeSm,
                  letterSpacing: 3)),
          const SizedBox(height: 6),
          row(Icons.my_location, l.fujiMeShort, colour: cs.tertiary),
          row(Icons.terrain, l.fujiRefsShort, colour: cs.primary),
          row(Icons.circle, l.fujiPeersShort,
              colour: cs.primary.withValues(alpha: .7)),
          row(Icons.help_outline, l.fujiUnknownShort,
              colour: cs.onSurfaceVariant),
          _LegendMore(title: l.gridLegendMore, lines: <String>[
            l.fujiLegendDesc,
            l.fujiLegendMe,
            l.fujiLegendRefs,
            l.fujiLegendPeers,
            l.fujiLegendUnknown,
            l.fujiLegendAutoQuery,
          ]),
        ],
      ),
    );
  }
}

/// R51 — info-button legend for the sns-cells social heat map.
class _SnsCellsLegend extends StatelessWidget {
  const _SnsCellsLegend({required this.cs, required this.l});
  final ColorScheme cs;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String text, {Color? colour}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 14, color: colour ?? cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontSize: context.skin.type.sizeBody,
                        height: 1.35)),
              ),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: mmRadius(context, 8),
        border: Border.all(color: cs.outline.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.snsCellsLegendTitle,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: context.skin.type.sizeSm,
                  letterSpacing: 3)),
          const SizedBox(height: 6),
          row(Icons.local_fire_department, l.snsHotShort, colour: cs.error),
          row(Icons.ac_unit, l.snsCoolShort),
          row(Icons.chat_bubble_outline, l.snsToastShort,
              colour: cs.tertiary),
          row(Icons.timelapse, l.snsDecayShort),
          _LegendMore(title: l.gridLegendMore, lines: <String>[
            l.snsCellsLegendDesc,
            l.snsCellsLegendHot,
            l.snsCellsLegendCool,
            l.snsCellsLegendToast,
            l.snsCellsLegendChannel,
            l.snsCellsLegendDecay,
          ]),
        ],
      ),
    );
  }
}
