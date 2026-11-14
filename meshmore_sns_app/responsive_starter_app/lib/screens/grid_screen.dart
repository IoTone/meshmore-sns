// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import '../meshcore/chat_message.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/own_location.dart';
import '../theme/theme_controller.dart';
import '../shell/horizontal_drag_claim.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';
import '../util/geo.dart' as geo;
import 'elevation_profile_view.dart';
import 'mesh_tree_view.dart';
import 'node_detail_sheet.dart';
import 'sns_cells_view.dart';
import 'grid_notice.dart';
import 'grid_prefs_store.dart';
import '../maps/compass.dart';
import '../maps/radar_scale.dart';
import '../theme/viz_palette.dart';
import '../util/mm_format.dart';
import 'weather_view.dart';
import '../ui/mm_shape.dart';
import 'package:meshcore/meshcore.dart';

/// R117 — the mesh survey: one tab for the views that answer "what does the
/// mesh look like from here, and where has it been heard?". `radial` (R18) is
/// the default and the tab's identity; `fabric` (persisted coverage) and
/// `weather` (environment telemetry) complete the primary set. The rest are
/// all in one list in the view picker: `tree` (topology, works with no GPS),
/// `elevation` (altitude against landmarks) and `snsCells` (chatter heat)
/// answer narrower questions than the first three, but a view nobody can find
/// is a view the app does not have.
/// The view picker is the only way between them: a left/right swipe belongs
/// to the shell's tabs (R109).
enum _GridViewMode {
  radial,
  weather,
  tree,
  snsCells,
  elevation,
}

/// Every view this tab ships, in the order they answer a question: what is
/// around me (radial), what we have heard where (coverage), what the air is
/// doing (weather), then topology (tree) and the two reports (altitude,
/// chatter heat).
///
/// One list, no second level. A "More views…" row hid four working views
/// behind a menu nobody opens; a view the user cannot see the name of is a
/// view they do not have.
const List<_GridViewMode> _allViews = <_GridViewMode>[
  _GridViewMode.radial,
  _GridViewMode.weather,
  _GridViewMode.tree,
  _GridViewMode.elevation,
  _GridViewMode.snsCells,
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
        _GridViewMode.tree || _GridViewMode.snsCells => true,
        _GridViewMode.radial ||
        _GridViewMode.elevation ||
        _GridViewMode.weather =>
          false,
      };

  /// Whether this view keeps a horizontal drag for itself, even if it does not
  /// pan.
  ///
  /// The altitude profile is a diagram: a drag across it does nothing, and
  /// paging the app sideways while the reader is tracing a summit is the worst
  /// of both. Claiming the drag makes the gesture inert instead of changing the
  /// view under their finger.
  bool get holdsDrags => this == _GridViewMode.elevation;
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
  const GridScreen({super.key, this.isCurrent});

  /// Whether this tab is the one on screen.
  ///
  /// The shell builds the neighbouring pages, so a listener here runs whether or
  /// not the reader is looking at it. A haptic click from a tab you are not on is
  /// a buzz with no explanation — the same reason `ChatScreen` takes this flag
  /// for its read marks.
  final bool? isCurrent;

  /// The selected view, held for the life of the process so it survives
  /// leaving and re-entering the tab (the PageView disposes the state), and
  /// written to [GridPrefsStore] so it also survives a restart.
  ///
  /// It used to be session-only, on the reasoning that every launch should open
  /// on the radar. The owner asked for the opposite on 2026-11-14: a reader who
  /// works in the mesh tree or the heat map should come back to it. A fresh
  /// install still opens on the radar, because that is what an absent
  /// preference means.
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
    // Auto frames whatever is actually in hand instead of a fixed window:
    // the bulk of the located nodes sit just inside the rim and the outliers
    // clamp to it. Appended rather than inserted, because `scaleIndex` is
    // persisted and an index that changes meaning would silently re-scale
    // every stored preference.
    (label: 'Auto', km: 0),
  ];

  /// The index of the [rangeStops] entry that frames the mesh automatically.
  static int get autoScaleIndex => rangeStops.length - 1;

  /// What share of the located nodes Auto keeps inside the rim.
  ///
  /// Nine in ten, so the furthest tenth clamps to the edge — which is what an
  /// edge is for — while the rest are spread across the body rather than
  /// huddled at the centre. A percentile rather than the maximum, because one
  /// node at 40 km would otherwise squash forty nodes into a dot.
  static const double autoPercentile = 0.9;

  /// Where the percentile lands inside the radius. Reads as "just inside the
  /// rim" with the ring labels still legible.
  static const double autoAnchor = 0.86;

  /// The outer radius, in km, that frames [distancesKm].
  ///
  /// Pure and static so the arithmetic is testable without a canvas or a
  /// controller: everything else about the radar is drawing.
  @visibleForTesting
  static double? autoRangeKm(List<double> distancesKm) {
    if (distancesKm.isEmpty) return null;
    final List<double> sorted = List<double>.of(distancesKm)..sort();
    // Below five nodes a percentile is just noise, so frame the furthest one.
    final int at = sorted.length >= 5
        ? ((sorted.length - 1) * autoPercentile).round()
        : sorted.length - 1;
    final double anchor = sorted[at];
    if (anchor <= 0) return null; // every node is on top of us
    // An exact radius rather than a rounded one. Rounding to a "nice" number
    // was tried and is worse than it sounds: the ladder's own steps are up to
    // a third wide, so a frame aimed at 86 % lands anywhere from 65 % to 100 %
    // — sometimes with nothing near the rim at all. The ring labels carry one
    // decimal instead, which is cheaper than a radius nobody asked for.
    return (anchor / autoAnchor).clamp(0.01, 2000.0);
  }

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

  /// Which way the phone is pointing. Started with the screen and disposed with
  /// it; null until the first sample, and every consumer falls back to north-up
  /// while it is null.
  late final CompassHeading _compass;
  late final bool _ownsCompass;

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

  /// A view that pans always owns its horizontal drags.
  ///
  /// There used to be a Swipe ⇄ Pan toggle (R109): in "swipe" the graph was
  /// held still so a drag changed tab. The owner's ruling removed it — a drag
  /// on a graph or a map is a drag, and a page change is a tap on the strip at
  /// the top. So the claim follows the view, not a mode.
  bool get _mapOwnsDrags => _viewMode.pansHorizontally;

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
  ///
  /// The default is **Auto**, which frames whatever nodes are in hand; the
  /// fixed stops stay for a user who wants a ring that means the same distance
  /// twice in a row.
  int _scaleIndex = GridScreen.autoScaleIndex;

  /// Run the ticker only while something it drives is actually drawn.
  ///
  /// The sweep and the pulse are the ticker's whole job, and reduce-motion
  /// removes both. The ticker used to repeat forever regardless, rebuilding a
  /// full-screen dial sixty times a second to paint a frame the user could not
  /// see — the one accessibility setting in this app that cost more battery than
  /// the animation it replaces.
  void _syncTickToMotion(bool still) {
    // Two reasons to stand still: reduce-motion removes the animation, and a
    // paused dial is not polling. Both used to leave the sweep running.
    final bool standStill = still || !_live;
    if (standStill && _tick.isAnimating) {
      _tick.stop();
    } else if (!standStill && !_tick.isAnimating) {
      _tick.repeat();
    }
  }

  @override
  void initState() {
    super.initState();
    // One revolution per refresh interval: at 15 s the line takes 15 s to come
    // round, so the sweep *is* the polling cadence rather than a decoration that
    // happens to move. The controller is retimed whenever the interval changes.
    _tick = AnimationController(vsync: this, duration: _interval)..repeat();
    final CompassHeading? shared = context.sharedCompass;
    _ownsCompass = shared == null;
    _compass = shared ?? CompassHeading();
    _compass.addListener(_onHeading);
    _compass.start();
    final MeshcoreController mc = context.read<MeshcoreController>();
    _snapshot = List<DiscoveredNode>.of(mc.nodes); // initial paused frame
    _msgSub = mc.incomingChannelMessages.listen((_) {
      if (mounted) _rippleAt = DateTime.now();
    });
    // The screen opens in its "live" state and the sweep says "I am polling this
    // often", but nothing started the timer: the only two places that created it
    // were the pause button and the interval picker. A live-looking screen with a
    // frozen picture is worse than a paused one, so the timer starts here.
    if (_live) _startRefresh();
    // The view mode is remembered for the session, the drag claim is not: it
    // is published from the mode that is showing.
    _publishDragClaim();
    // The sensors are not free: a report view that draws no bearing does not
    // need the magnetometer running behind it.
    _syncCompassToView();
    // Restore last-used grid preferences (scale / orientation / refresh)
    // so they don't reset when re-opening the grid. The view itself is
    // session state — see [GridScreen._sessionMode].
    GridPrefsStore.load().then((GridPrefs? p) {
      if (p == null || !mounted) return;
      setState(() {
        if (p.scaleIndex >= 0 && p.scaleIndex < GridScreen.rangeStops.length) {
          _scaleIndex = p.scaleIndex;
        }
        _interval = Duration(seconds: p.intervalSec.clamp(1, 600));
        // The view and the legend come back with the scale and the cadence.
        // An unknown name (a view that was removed) falls back to the radar
        // rather than to a blank screen.
        final _GridViewMode? saved = _GridViewMode.values
            .where((_GridViewMode m) => m.name == p.mode)
            .firstOrNull;
        if (saved != null) {
          _viewMode = saved;
          GridScreen._sessionMode = saved;
        }
        _legendVisible = p.legendVisible;
        // The dial's revolution follows the interval that was just restored,
        // and the poll timer is retimed with it so the two cannot disagree.
        _tick
          ..stop()
          ..duration = _interval;
        if (_live) {
          _tick.repeat();
          _startRefresh();
        }
        // Don't auto-restore `live` — the screen intentionally opens paused
        // (a fresh snapshot), and live restore is handled by the existing
        // follow-mc-until-interacted behaviour.
      });
    });
  }

  void _savePrefs() {
    GridPrefsStore.save(GridPrefs(
      scaleIndex: _scaleIndex,
      intervalSec: _interval.inSeconds,
      mode: _viewMode.name,
      legendVisible: _legendVisible,
    ));
  }

  void _selectMode(_GridViewMode m) {
    setState(() => _viewMode = m);
    GridScreen._sessionMode = m;
    _publishDragClaim();
    _syncCompassToView();
    _savePrefs();
  }

  /// Run the magnetometer (and the quarter-turn click) only while a view that
  /// draws a bearing is showing. The compass is app-scoped and shared, so this
  /// only ever stops an instance this screen owns.
  void _syncCompassToView() {
    if (!_ownsCompass) return;
    if (_usesHeading) {
      _compass.start();
    } else {
      _compass.stop();
    }
  }

  /// Tells the shell whether this tab owns horizontal drags right now.
  void _publishDragClaim() {
    if (_mapOwnsDrags || _viewMode.holdsDrags) {
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
    _compass.removeListener(_onHeading);
    if (_ownsCompass) _compass.dispose();
    super.dispose();
  }

  /// The compass listener exists for the redraw; the quarter-turn click lives in
  /// `CompassHeading`, which is the one instance every dial shares, so a phone
  /// turned on the dashboard or the map clicks there too.
  void _onHeading() {}

  void _refreshSnapshot() {
    if (!mounted) return;
    setState(() => _snapshot =
        List<DiscoveredNode>.of(context.read<MeshcoreController>().nodes));
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

  /// Views that draw a bearing, and therefore the only ones a compass line
  /// belongs on. The radar and the mesh tree both place peers by heading; the
  /// reports (altitude, weather) and the cell grid do not.
  bool get _usesHeading =>
      _viewMode == _GridViewMode.radial || _viewMode == _GridViewMode.tree;

  /// What the compass has to say about itself, or null when it has nothing to
  /// add to the view's own purpose line.
  ///
  /// A dial that cannot point says why, because a phone near a magnet otherwise
  /// simply does nothing when it is turned. A dial that points but has never
  /// been turned is right about which way it moved and not yet about which way
  /// is north, and the model has always known that (`calibratedCircle` plus the
  /// platform's own accuracy verdict) while nothing said it.
  String? _compassLine(AppLocalizations l) {
    if (!_usesHeading) return null;
    if (_compass.disturbed && !_compass.hasHeading) return l.gridCompassDisturbed;
    if (_compass.hasHeading && !_compass.calibratedCircle) {
      return l.gridCompassCalibrating;
    }
    if (_compass.hasHeading && _compass.needsCalibration) {
      return l.gridCompassLowAccuracy;
    }
    return null;
  }

  /// Whether the view plots nodes, and therefore whether a node count means
  /// anything above it. A weather report over "3 in mesh · 2 known" was three
  /// counts about something the view does not show.
  bool get _plotsNodes => switch (_viewMode) {
        _GridViewMode.radial ||
        _GridViewMode.tree ||
        _GridViewMode.snsCells =>
          true,
        _GridViewMode.weather || _GridViewMode.elevation => false,
      };

  /// Views that render a legend, so the info button exists only there.
  bool get _hasLegend => switch (_viewMode) {
        _GridViewMode.radial ||
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
  Widget _transportBar(AppLocalizations l, ColorScheme cs, String scaleLabel,
      String scaleValue) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border:
            Border(top: BorderSide(color: cs.outline.withValues(alpha: .2))),
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
                          // The stop's own name, and the distance the dial
                          // actually draws for it. A picker entry reading "1 km"
                          // beside a chip reading "1.5 km" was two scales on one
                          // screen; the rounded rim is the one that is true.
                          MmPickerItem<int>.option(
                              k, _rangePickerLabel(l, k)),
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
        _GridViewMode.elevation => Icons.terrain,
        _GridViewMode.tree => Icons.account_tree,
        _GridViewMode.snsCells => Icons.local_fire_department,
        _GridViewMode.weather => Icons.thermostat,
      };

  static String _longLabel(_GridViewMode m, AppLocalizations l) => switch (m) {
        _GridViewMode.radial => l.gridViewRadial,
        _GridViewMode.elevation => l.gridViewElevation,
        _GridViewMode.tree => l.gridViewTree,
        _GridViewMode.snsCells => l.gridViewSnsCells,
        _GridViewMode.weather => l.gridViewWeather,
      };

  /// One line under the header saying what this view answers, so a view is
  /// not a name the user has to decode. Kept to one line on purpose: a view
  /// that needs a paragraph to explain itself is the wrong view.
  static String _purposeFor(_GridViewMode m, AppLocalizations l) => switch (m) {
        _GridViewMode.radial => l.gridPurposeRadial,
        _GridViewMode.weather => l.gridPurposeWeather,
        _GridViewMode.tree => l.gridPurposeTree,
        _GridViewMode.snsCells => l.gridPurposeSnsCells,
        _GridViewMode.elevation => l.gridPurposeElevation,
      };

  /// Start the periodic refresh the "live" state promises. Idempotent, because
  /// three callers start it (init, the pause button, the interval picker).
  void _startRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_interval, (_) => _refreshSnapshot());
  }

  void _togglePlay() {
    setState(() {
      _userInteracted = true;
      _live = !_live;
    });
    _refreshTimer?.cancel();
    if (_live) {
      _refreshSnapshot(); // immediate snap on Play
      _startRefresh();
      // The sweep is the poll made visible: one revolution per interval. Play
      // puts it back on the clock, unless reduce-motion removed it entirely.
      if (!context.read<ThemeController>().reduceMotion && !_tick.isAnimating) {
        _tick
          ..duration = _interval
          ..repeat();
      }
    } else {
      // Pause stops the timer AND the sweep. It used to stop only the timer, so
      // the line kept coming round every interval with a frozen picture behind
      // it, which reads as a refresh spinner that ignores the pause button.
      _tick.stop();
      // Pause taps: re-capture current state so the frozen view
      // matches what the user sees at the moment of pause.
      _refreshSnapshot();
    }
  }

  void _changeInterval(Duration d) {
    setState(() {
      _userInteracted = true;
      _interval = d;
      // The dial keeps time with the radio: one revolution per poll.
      _tick
        ..stop()
        ..duration = d
        ..repeat();
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
      7 => l.gridRangeRegion,
      _ => l.gridRangeAuto,
    };
  }

  /// A stop's name with the rim the dial draws for it, so the picker and the
  /// chip cannot state two different scales.
  String _rangePickerLabel(AppLocalizations l, int idx) {
    final String name = _rangeLabel(l, idx);
    if (idx == GridScreen.autoScaleIndex ||
        idx == GridScreen.rangeStops.length - 2) {
      return name;
    }
    return '$name · ${_rangeValue(_roundRimKm(GridScreen.rangeStops[idx].km))}';
  }

  /// The outer-ring scale in km for the current stop.
  ///
  /// **Auto** (the default) frames the mesh in hand: the ninth decile of the
  /// located distances lands at 86 % of the radius, so the bulk of the nodes
  /// spread across the body and the furthest tenth clamps to the rim.
  /// **Region** frames the single furthest node. Every other stop is a fixed
  /// window, so the ring means the same distance twice in a row.
  double _effectiveScaleKm(
      double? selfLat, double? selfLon, List<DiscoveredNode> visible) {
    final bool isAuto = _scaleIndex == GridScreen.autoScaleIndex;
    final double base = isAuto
        ? GridScreen.defaultRangeKm
        : GridScreen.rangeStops[_scaleIndex].km;
    if (isAuto) {
      if (selfLat == null || selfLon == null) return base;
      final double? framed =
          GridScreen.autoRangeKm(<double>[for (final DiscoveredNode n in visible)
            if (n.hasLocation)
              geo.haversineMeters(selfLat, selfLon, n.latitude!, n.longitude!) /
                  1000.0]);
      // Nothing located to frame: the rings fall back to a stated fixed
      // window rather than inventing a scale from signal-strength guesses.
      return _roundRimKm(framed ?? base);
    }
    // A fixed stop's rim is rounded up to whole ring steps, so its labels are
    // round numbers. The *picker* prints the rounded rim rather than the raw
    // stop, because a dial whose chip reads 1.5 km while its picker says 1 km is
    // two scales on one screen — the owner's report.
    final bool isRegion = _scaleIndex == GridScreen.rangeStops.length - 2;
    if (!isRegion || selfLat == null || selfLon == null) {
      return _roundRimKm(base);
    }
    double maxKm = 0;
    for (final DiscoveredNode n in visible) {
      if (!n.hasLocation) continue;
      final double km =
          geo.haversineMeters(selfLat, selfLon, n.latitude!, n.longitude!) /
              1000.0;
      if (km > maxKm) maxKm = km;
    }
    if (maxKm <= 0) return _roundRimKm(base);
    // Pad 10% so the farthest node sits just inside the rim; clamp to
    // a sane window, then round the rim so the labels are round too.
    return _roundRimKm((maxKm * 1.1).clamp(50.0, 2000.0));
  }

  /// A rim distance rounded up to three whole steps, so the dial's labels are
  /// round numbers: 25 / 50 / 75 km rather than 66 / 132 / 198.
  static double _roundRimKm(double km) {
    if (!km.isFinite || km <= 0) return km;
    return radarRingStepMeters(km * 1000) * 3 / 1000;
  }

  /// Pretty distance label for a scale stop (e.g. "25 m" / "5 km"), in the
  /// reader's units.
  String _rangeValue(double km) =>
      MmFormat.step(km * 1000, prefs: context.formatPrefs);

  /// Cheap "did the live node list change" check for the
  /// auto-track-until-interaction path. We compare by length first
  /// (the cheap case) then identity per index — both nodes lists
  /// are managed by the controller which doesn't mutate in place.
  bool _listEquals(List<DiscoveredNode>? a, List<DiscoveredNode> b) {
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
        headingDegrees: _compass.heading,
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
    // The ticker is the sweep's and the pulse's engine, and reduce-motion removes
    // both. It used to repeat forever regardless, rebuilding this whole dial
    // sixty times a second for a frame nothing draws.
    _syncTickToMotion(tc.reduceMotion);
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
          setState(() => _snapshot = List<DiscoveredNode>.of(mc.nodes));
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
          if (nowUnix - n.lastHeardUnix < windowSec && n.pubKeyHex != selfPk) n
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
          // The app bar says which view this is; here the view says what it
          // shows, one muted line: a name is not an explanation and a paragraph
          // is not a header.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Text(
              _purposeFor(_viewMode, l),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: context.skin.type.sizeSm),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
            // The picker takes the width it needs and gives back what it does not,
            // so the view name ellipsises instead of pushing the toggles off the
            // edge at 200 % text on a 320 dp phone (found by the floor test).
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                // R88 — one control on the left: the current view's own icon,
                // short name and a chevron. The separate caption that used to
                // sit above it said the same thing in the same toolbar. The
                // menu groups the ten views by what they show (peers, surveys,
                // reports) instead of listing them as ten peers.
                // R104 — a labelled sheet, not a menu: ten views in three groups
                // with a check state is a list, and a menu cannot scroll, cannot
                // say "Peers" as a group, and opens away from its own button.
                Flexible(
                  child: Tooltip(
                    message: l.gridViewPicker,
                    child: InkWell(
                      onTap: () async {
                        final _GridViewMode? m =
                            await showMmPicker<_GridViewMode>(
                          context: context,
                          title: l.gridViewPicker,
                          current: _viewMode,
                          items: <MmPickerItem<_GridViewMode>>[
                            for (final _GridViewMode v in _allViews)
                              MmPickerItem<_GridViewMode>.option(
                                  v, _longLabel(v, l),
                                  icon: _iconForMode(v)),
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
                                      fontSize: context.skin.type.sizeBodyLg,
                                      fontWeight: FontWeight.w600)),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Only the five views that draw a legend get the button, so it
                // can no longer be a silent no-op in the other five.
                if (_hasLegend)
                  IconButton(
                    tooltip:
                        _legendVisible ? l.gridHideLegend : l.gridShowLegend,
                    // A legend glyph, not an info one. `info` is this app's
                    // "about this screen" mark everywhere else (About, SOS's
                    // notes, the mesh tree's explainer), so a legend toggle
                    // wearing it read as a link to documentation.
                    icon: Icon(_legendVisible
                        ? Icons.legend_toggle
                        : Icons.legend_toggle_outlined),
                    onPressed: () {
                      setState(() => _legendVisible = !_legendVisible);
                      _savePrefs();
                    },
                  ),
              ],
            ),
          ),
          // The compass line belongs to the views that draw a bearing, and it
          // belongs under the header rather than above it: the header says which
          // view this is, and this says what the view's own instrument is doing.
          // It used to sit above the picker and to appear on every view, so a
          // weather report could open with "Turn the phone right round once to
          // calibrate" about a dial that view does not draw.
          if (_usesHeading && _compassLine(l) != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _compassLine(l)!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: context.skin.type.sizeSm),
                ),
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
                // Offline is the strip's sentence below, with its action on it.
                // Printing it twice on one screen — once muted here and once in
                // the strip — was two ways of saying the same thing in the same
                // column.
                !ready
                    ? ''
                    : _plotsNodes
                        ? l.gridStatusCounts(
                            visible.length, mc.known.length, mc.favorites.length)
                        : '',
                style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: context.skin.type.sizeBody),
              ),
            ),
          ),
          // The radar says it in its own centre; every other view gets
          // the strip.
          if (!ready && _viewMode != _GridViewMode.radial)
            _NotConnectedStrip(
              cs: cs,
              label: l.gridNotConnected,
              action: l.chatConnectRadio,
              onAction: () => context.push('/connect'),
            ),
          // The picker drives mode; the body renders the chosen mode's widget
          // under its Swipe ⇄ Pan state (R109).
          Expanded(
              child: switch (_viewMode) {
            _GridViewMode.elevation => Stack(
                children: <Widget>[
                  ElevationProfileView(
                      filteredNodes: visible,
                      reduceMotion: tc.reduceMotion,
                    ),
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
                    interactive: true,
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
                              ? GridNotice(
                                  message: l.gridEmpty,
                                  icon: Icons.radar,
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
                                        // Both, not just the ticker: with
                                        // reduce-motion on, the ticker is
                                        // stopped and the dial would freeze
                                        // while the phone turned.
                                        animation:
                                            Listenable.merge(<Listenable>[
                                          _tick,
                                          _compass,
                                        ]),
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
                                            sweep: _viewMode ==
                                                    _GridViewMode.radial
                                                ? _tick.value
                                                : null,
                                            reduceMotion: tc.reduceMotion,
                                            accent: cs.primary,
                                            // The hand of the clock, in the
                                            // colour opposite this skin: a
                                            // burnt red on the forest dials, a
                                            // cyan on NERV. It must not read as
                                            // one of the marks it sweeps over.
                                            sweepColor: VizPalette.sweepFor(
                                                context.skin),
                                            format:
                                                context.formatPrefs,
                                            subtle: cs.onSurface
                                                .withValues(alpha: .12),
                                            ringStroke: cs.outline
                                                .withValues(alpha: .35),
                                            base: cs.onSurfaceVariant,
                                            type: context.skin.type,
                                            textScale:
                                                MediaQuery.textScalerOf(context)
                                                    .scale(1),
                                            rippleAt: _rippleAt,
                                            rippleDuration: _rippleDuration,
                                            scaleKm: scaleKm,
                                            northMarker: VizPalette.north,
                                            headingDegrees: _compass.heading,
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
  const _GridLegend({required this.cs, required this.scaleKm, required this.l});
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
    final String scaleValueDisplay =
        MmFormat.step(scaleKm * 1000, prefs: context.formatPrefs);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
            l.gridLegendNorth,
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
  const _NotConnectedStrip({
    required this.cs,
    required this.label,
    this.action,
    this.onAction,
  });

  final ColorScheme cs;
  final String label;

  /// The way out, on the strip. A state that says "not connected" and offers
  /// nothing is a dead end in the middle of a screen.
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      // Solid, not 85 % of the surface: this strip sits over the radar's own
      // ring labels, and at 0.85 the "3.3 km" under it showed through the
      // banner on the device. A state banner has to be readable before the
      // canvas behind it is.
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: mmRadius(context, 8),
        border: Border.all(color: cs.error.withValues(alpha: .6)),
      ),
      // The action sits on its own line rather than beside the label: at 320 dp
      // with the text at 200 % the two together overflowed by 214 px, and a
      // banner that clips its own way out is worse than a taller one.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
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
          if (action != null && onAction != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey<String>('grid-not-connected-connect'),
                onPressed: onAction,
                child: Text(action!),
              ),
            ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.textScale,
    required this.nodes,
    required this.favorites,
    required this.known,
    required this.selfLat,
    required this.selfLon,
    required this.nowUnix,
    required this.windowSec,
    required this.tick,
    required this.sweep,
    required this.reduceMotion,
    required this.sweepColor,
    required this.format,
    required this.accent,
    required this.subtle,
    required this.ringStroke,
    required this.base,
    required this.type,
    required this.rippleAt,
    required this.rippleDuration,
    required this.scaleKm,
    required this.northMarker,
    this.headingDegrees,
  });

  final List<DiscoveredNode> nodes;
  final Set<String> favorites;
  final Set<String> known;
  final double? selfLat;
  final double? selfLon;
  final int nowUnix;
  final int windowSec;
  final double tick; // 0..1, repeating

  /// The radar sweep phase (0..1) or null in a view that is not a dial.
  ///
  /// One revolution per refresh interval, set by the screen, so the line that
  /// sweeps the dial is also the thing that says how stale the picture is.
  final double? sweep;
  final bool reduceMotion;

  /// The sweep's own colour: the hue opposite this skin's accent, so the hand of
  /// the clock is never mistaken for a node.
  final Color sweepColor;

  /// The reader's units, so a ring label says miles where the reader reads miles.
  final FormatPrefs? format;

  final Color accent;
  final Color subtle;
  final Color ringStroke;
  final Color base;

  /// The active skin's type system: the ring labels are painted, not built,
  /// so the ladder reaches them through this.
  final MmType type;

  /// The user's text scale, multiplied into every label this painter draws.
  /// `MmType` carries the skin's scale only, so a painted label otherwise
  /// ignores the font setting while the widgets around it honour it.
  final double textScale;
  final DateTime? rippleAt;
  final Duration rippleDuration;
  final double scaleKm;

  /// Which way the phone is pointing, or null when nothing knows.
  ///
  /// The radar plots peers by real bearing, which is only honest while the
  /// phone faces north. With a heading the whole dial turns so its top is the
  /// phone's own facing, and the red marker on the rim says where north went.
  final double? headingDegrees;

  /// The red the north marker is drawn in. Passed in rather than written here,
  /// so it is the scheme's own red on every skin and the colour ratchet keeps
  /// its meaning.
  final Color northMarker;

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
    double? headingDegrees,
  }) {
    final bool selfGps = _selfHasGpsStatic(selfLat, selfLon);
    final double angle;
    final double radius;
    if (selfGps && node.hasLocation) {
      final double dKm = geo.haversineMeters(
              selfLat!, selfLon!, node.latitude!, node.longitude!) /
          1000.0;
      radius = (dKm / scaleKm).clamp(0.05, 1.0) * maxR;
      angle =
          geo.bearingRadians(selfLat, selfLon, node.latitude!, node.longitude!);
    } else if (node.rssi != null) {
      final int ringIdx = _ringFromRssi(node.rssi);
      radius = maxR * <double>[1 / 3, 2 / 3, 1.0][ringIdx];
      angle = _hashAngle(node.pubKeyHex);
    } else {
      radius = maxR;
      angle = _hashAngle(node.pubKeyHex);
    }
    final double shown = angle - (headingDegrees ?? 0) * math.pi / 180;
    return center + Offset(radius * math.sin(shown), -radius * math.cos(shown));
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
    // The sweep: a leading line and a faint wedge behind it, one revolution
    // per refresh interval. Drawn over the rings and under the markers so a
    // blip is never hidden by the line.
    final double? sweepPhase = sweep;
    if (sweepPhase != null && !reduceMotion) {
      final double a = sweepPhase * 2 * math.pi;
      const double trail = math.pi / 3;
      final Rect rect = Rect.fromCircle(center: center, radius: maxR);
      canvas.drawArc(
        rect,
        a - trail,
        trail,
        true,
        Paint()
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: trail,
            colors: <Color>[
              sweepColor.withValues(alpha: 0.0),
              sweepColor.withValues(alpha: 0.18),
            ],
            transform: GradientRotation(a - trail),
          ).createShader(rect),
      );
      canvas.drawLine(
        center,
        Offset(center.dx + maxR * math.cos(a),
            center.dy + maxR * math.sin(a)),
        Paint()
          ..strokeWidth = 1.4
          ..color = sweepColor.withValues(alpha: 0.55),
      );
    }

    // Ring labels. Position each label just inside the ring on the
    // right (+X) axis so they don't collide with node markers in
    // typical fleets.
    for (final double f in ringFracs) {
      // The rim is three whole steps, so each label lands on one.
      final String label =
          radarDistanceLabel(scaleKm * f * 1000, prefs: format);
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
              color: base,
              fontSize: type.sizeMicro * textScale,
              fontFamily: type.monoFamily),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(center.dx + maxR * f - tp.width - 4, center.dy - tp.height - 2),
      );
    }
    // North, as a red marker that moves with the dial — the arrow alone.
    //
    // The radar plots every peer by *real* bearing, so with a heading the dial
    // turns and north is no longer the top. The triangle is drawn at the bearing
    // north actually sits at, and stays at the top only in the north-up
    // fallback, where it is telling the truth.
    //
    // It carried an "N" outside the rim, and that letter was doing harm twice:
    // it sat on the same bearing as the arrow and collided with it at most
    // headings, and because it was painted upright it read as a label lying on
    // the rim rather than a direction. A triangle is unmistakable in every
    // rotation, and the dial's ticks already say which way is which.
    final double northAt = CompassHeading.northMarkerDegrees(headingDegrees);
    paintNorthMarker(canvas, center, maxR,
        markerDegrees: northAt, color: northMarker);
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
    canvas.drawCircle(
        center,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = accent.withValues(alpha: .6));

    // R18 anonymous-channel ripple: an incoming channel message is
    // not attributable to a node, so draw a transient centre-out
    // wave instead of a node marker. Honours reduce-motion: skipped.
    if (!reduceMotion && rippleAt != null) {
      final int ageMs = DateTime.now().difference(rippleAt!).inMilliseconds;
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
        // The dial turns with the phone, and the *markers* have to turn with
        // it. Omitting this drew every peer at its true bearing while the red
        // north marker rotated — so the marker said where north was and the dots
        // did not follow it, which is exactly what the owner reported.
        headingDegrees: headingDegrees,
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
          final double s = 0.5 + 0.5 * math.sin(tick * 2 * math.pi * 2.8);
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
      // The painted text and the north glyph are laid out from these two. They
      // were missing, and the omission was invisible only because `tick` moves
      // on every frame, so this painter had no gate at all. With the ticker
      // stopped under reduce-motion, a missing input would freeze a font-size
      // change into the dial while every widget around it resized.
      old.textScale != textScale ||
      old.northMarker != northMarker ||
      old.tick != tick ||
      old.reduceMotion != reduceMotion ||
      old.sweepColor != sweepColor ||
      old.format != format ||
      old.rippleAt != rippleAt ||
      old.scaleKm != scaleKm ||
      old.type != type ||
      // The self fix, the clock and the recency window all move markers: a
      // "refresh location from device" that lands while the node list is
      // unchanged (the common case — the nodes did not move, we did) used to
      // leave every marker where the old fix put it, because none of the
      // three was compared. The colours are here for the same reason: a
      // preset switch repaints the ring, and a stale accent is a wrong mark.
      old.selfLat != selfLat ||
      old.selfLon != selfLon ||
      // The dial turns with the phone, so a heading change moves every marker.
      old.headingDegrees != headingDegrees ||
      old.nowUnix != nowUnix ||
      old.windowSec != windowSec ||
      old.accent != accent ||
      old.subtle != subtle ||
      old.ringStroke != ringStroke ||
      old.base != base;
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          row(Icons.more_horiz, l.treeFloodShort, colour: cs.onSurfaceVariant),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          row(Icons.chat_bubble_outline, l.snsToastShort, colour: cs.tertiary),
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
