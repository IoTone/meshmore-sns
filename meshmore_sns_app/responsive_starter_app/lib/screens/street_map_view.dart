// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:math' as math;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:meshcore/meshcore.dart' show SelfInfo;
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../field/relationship.dart';
import '../meshcore/own_location.dart';
import '../geofence/geofence_controller.dart';
import '../geofence/geofence_store.dart';
import '../maps/basemap.dart';
import '../maps/coverage_quilt.dart';
import '../maps/density_overlay.dart';
import '../maps/hex_field.dart';
import '../maps/message_bubble.dart';
import '../theme/viz_palette.dart';
import '../maps/basemap_prefs.dart';
import '../maps/compass.dart';
import '../maps/map_centre.dart';
import '../perms/location_service.dart';
import '../perms/permissions_service.dart';
import '../maps/event_layer.dart';
import '../maps/map_source.dart';
import '../maps/maps_controller.dart';
import '../maps/tile_math.dart';
import '../maps/vector_basemap.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/meshcore_controller.dart';
import '../places/place.dart';
import '../places/place_create_sheet.dart';
import '../places/place_detail_sheet.dart';
import '../places/place_layer.dart';
import '../places/place_store.dart';
import '../places/place_wiring.dart';
import '../theme/mm_skin.dart';
import '../util/lora_range.dart';
import 'node_detail_sheet.dart';
import '../ui/mm_components.dart';
import '../ui/mm_shape.dart';

/// R25+2 — fourth view in the hyperlocal-grid sub-mode swipe stack.
///
/// Unlike the equal-grid view (cells in screen space), this view is
/// a **standard interactive street map**: full-colour OSM tiles,
/// native pan + pinch zoom on the map itself, and peer / self / trail
/// rendered via flutter_map's own layer primitives (Marker, Polyline,
/// CircleMarker) rather than a CustomPaint overlay.
///
/// Reuses the same data (filtered nodes + frozen state piped from the
/// radial grid) and the same R25+1 polish — distinctive self pin,
/// heading arrow, ownTrail polyline, estimated LoRa range rings.
/// What's different vs the equal-grid is *what* the user sees
/// underneath: an actual street map you can pan and zoom through,
/// not a tinted basemap clipped to a 5×5 cell viewport.
class StreetMapView extends StatefulWidget {
  const StreetMapView({
    super.key,
    this.filteredNodes,
    this.frozen = false,
    this.interactive = true,
    this.controlExtras = const <Widget>[],
  });

  final List<DiscoveredNode>? filteredNodes;
  final bool frozen;

  /// R109 — false while the grid is in swipe mode: the map is a still picture
  /// so a horizontal drag pages the shell. Taps still reach the pins, which is
  /// why this is not an `IgnorePointer`.
  final bool interactive;

  /// R69 — with no position fix, render the map at a world view (and a
  /// quiet "no fix" row) instead of the empty "awaiting fix" text.
  /// Default **off**: the Hyperlocal grid's street-map mode keeps its
  /// original empty state; only the first-class Map tab opts in.

  /// Controls the host page contributes to this column, rendered under the
  /// five built-in ones. Every map tool lives in one column on one edge, so
  /// a host never has to place a second column on the other side (the Map
  /// tab passed its offline-maps and places buttons that way, and they were
  /// the buttons a thumb never found).
  final List<Widget> controlExtras;

  /// R69 — the honest default centre when there is no fix: a world view
  /// (the middle of the Atlantic/Africa band), not a guess at the user's
  /// region. [browseZoom] shows the whole globe's land masses.
  static const LatLng browseCentre = MapCentre.worldCentre;
  static const double browseZoom = MapCentre.worldZoom;

  /// The control column's cell size and inset, in logical pixels.
  ///
  /// The column is one right-hand edge with one cell per tool, so anything
  /// placed on the right edge has to know how wide it is: `controlsInset` from
  /// the screen edge plus one cell is where the map itself begins.
  static const double controlCell = 48;
  static const double controlsInset = 12;

  /// How many cells the column draws today: zoom in, zoom out, recentre,
  /// basemap, overlays, report a place. Pinned by
  /// `test/screens/map_chrome_test.dart` so a new control has to update this
  /// rather than silently misplacing whatever is placed beside the column.
  static const int controlCount = 6;

  /// Bottom edge of the column when the host adds [extras] controls.
  static double controlsBottomFor(int extras) =>
      controlsInset + (controlCount + extras) * controlCell;

  /// Ground metres per logical pixel at [zoom] for [latitude]. Web-Mercator on
  /// 256 px tiles: 156543.03392 m/px at zoom 0 on the equator, halved per level
  /// and scaled by the latitude's cosine. Static so the rule can be tested
  /// without a laid-out map.
  @visibleForTesting
  static double metersPerPixel(double zoom, double latitude) {
    final double c = math.cos(latitude * math.pi / 180).abs().clamp(0.05, 1.0);
    return 156543.03392 * c / math.pow(2, zoom).toDouble();
  }

  /// Where the camera starts, given what the ladder resolved and whether the
  /// user has moved the map themselves.
  ///
  /// A panned map is never moved again: a position that arrives after the user
  /// has taken the camera stays where they put it, and the ladder's answer is
  /// used only while they have not. This is the one rule the map has about
  /// taking control from a finger, so it is a function with a name rather than
  /// a `??` inside a widget literal.
  @visibleForTesting
  static LatLng initialCentreFor({
    required MapCentre resolved,
    required LatLng? userCentre,
  }) =>
      userCentre ?? resolved.centre;

  /// The one line the map says when nothing is arriving from the network.
  ///
  /// The copy was written for the degraded model and never drawn: a user
  /// offline with an empty cache saw a blank grey grid and no reason for it.
  /// It is a function so the rule can be tested without standing up a live
  /// map, which schedules timers and animations a widget test cannot settle.
  static String? tilesOfflineNoticeFor(
          AppLocalizations l, MapsController? maps) =>
      maps == null || maps.online ? null : l.degradedMapOffline;

  /// True when a ring of [radiusMeters] is small enough to read on a screen
  /// [viewportMeters] tall. Half the viewport is the cut: past it the circle
  /// is an arc through the middle of the map with its centre off screen, which
  /// is the "stray line" the map used to show instead of a range.
  static bool reachRingReadable(double radiusMeters, double viewportMeters) =>
      radiusMeters <= viewportMeters * .5;

  /// The movement trail as drawn: three fixes and twenty metres of travel, or
  /// nothing. A two-point trail is one GPS sample apart from the current fix
  /// and drew as a stray segment beside the marker. The live fix is appended
  /// when it is not already the last sample, so the line ends on the marker.
  @visibleForTesting
  static const int trailMinPoints = 3;
  @visibleForTesting
  static const double trailMinSpanMeters = 20;

  @visibleForTesting
  static List<LatLng> trailPathFor(
    List<({double latitude, double longitude, int unixSec})> trail, {
    double? selfLat,
    double? selfLon,
  }) {
    final List<LatLng> pts = <LatLng>[
      for (final ({double latitude, double longitude, int unixSec}) p in trail)
        LatLng(p.latitude, p.longitude),
    ];
    if (selfLat != null && selfLon != null) {
      final LatLng live = LatLng(selfLat, selfLon);
      if (pts.isEmpty || pts.last != live) pts.add(live);
    }
    if (pts.length < trailMinPoints) return const <LatLng>[];
    final double span =
        const Distance().as(LengthUnit.Meter, pts.first, pts.last);
    return span < trailMinSpanMeters ? const <LatLng>[] : pts;
  }

  @override
  State<StreetMapView> createState() => _StreetMapViewState();
}

class _StreetMapViewState extends State<StreetMapView> {
  /// Discrete zoom levels. Pinch on the map also works; these
  /// buttons are an explicit affordance for users on devices
  /// without multi-touch or who prefer one-handed operation.
  /// R83 — the Studio basemap is Shortbread, whose tiles stop at z14, so
  /// every level past it is an upscale. Past z17 the upscale is 8x linear
  /// and the map stops carrying information; the raster presets keep the
  /// deeper native range.
  double get _zoomMax => _vectorSkin ? 17.0 : 18.5;
  static const double _zoomStep = 1.0;
  late final MapController _map = MapController();

  /// The camera starts where [MapCentre.resolve] says, and [MapCentre] keeps
  /// the reasoning in one testable place: the phone's position, then the
  /// radio's own, then the view the user left, then the world.
  double _zoom = MapCentre.personalZoom;

  /// The reception quilt, on by default: it is why the grid's Coverage view
  /// left, and a layer nobody can see on the tab that replaced it would make
  /// that removal a loss. The toggle exists because it is an overlay on a map
  /// whose labels matter underneath it.
  bool _showCoverage = true;

  /// The equal-area density overlay, off by default: it is a reading about the
  /// mesh, not a record of it, so it is something to ask for rather than
  /// something to dismiss on every visit.
  bool _showDensity = false;

  /// Whether the density cells are large enough on screen to carry their
  /// counts. The fills and the numbers are one piece of information, so they
  /// appear and disappear together: a filled square with no number in it reads
  /// as a large node pin, which is what the owner reported being confused by.
  /// The band between the two thresholds is hysteresis, so a pinch that sits on
  /// the boundary does not make the overlay flicker.
  bool _densityCellsDrawn = true;

  /// The squares last drawn, so a tap on the map can name the one it landed in.
  /// Rebuilt with the layer, because the set depends on where the nodes are.
  List<HexCell> _densityCells = const <HexCell>[];

  /// The hexagon's circumradius, in metres, for the current zoom: a cell that is
  /// legible as a shape at street zoom and does not become a mosaic at a city
  /// view. Unlike the squares this replaces, the *ground* area stays fixed while
  /// the zoom changes within a band, so the field is read as one thing.
  double _hexRadiusMetres = kDefaultHexCircumradiusMetres;
  bool _centered = false;

  /// The view the user left, read once at startup. It is step three of the
  /// ladder, which is the "centred on them" that matters most in practice.
  SavedMapView? _saved;

  /// True once the user pans or zooms the map. A position that arrives after
  /// that must not move the camera out from under their finger.
  bool _userMoved = false;

  /// The ladder rung the camera is currently centred on. A rebuild that
  /// resolves to the same rung must not move anything.
  MapCentreSource? _centredOn;

  /// Where the user left the camera when they last moved it themselves. While
  /// they have, this is the honest `initialCenter`: the resolved ladder must
  /// not be handed to the map again, or a late position would take the view
  /// back.
  LatLng? _userCentre;

  /// Why the last attempt to get a position produced none. Null means either
  /// no attempt yet or a position is known; the banner says which.
  LocationFailure? _locationFailure;
  bool _askingForFix = false;

  /// Debounced so a pan does not write a preference on every frame.
  Timer? _saveView;

  /// R83 - warms the ring around a settled viewport so the next pan paints
  /// from storage. Debounced, and only when nothing else is fetching.
  Timer? _warm;

  /// The region a downloaded map region covers, largest first, so the map can
  /// open on the area the user went to the trouble of keeping offline. Null
  /// when nothing is installed.
  void _rememberView() {
    _saveView?.cancel();
    _saveView = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      final MapCamera cam = _map.camera;
      unawaited(MapViewPrefs.save(SavedMapView(
        latitude: cam.center.latitude,
        longitude: cam.center.longitude,
        zoom: cam.zoom,
      )));
    });
  }

  /// Read during build; `context.skin` watches a provider and must not be
  /// touched from a timer or an async callback.
  bool _vectorSkin = false;

  void _scheduleWarm({bool moved = false}) {
    _warm?.cancel();
    // A moving camera kills the warm-up in flight. Without this the queue kept
    // walking a ring around the place the user had already left — up to 36
    // sequential requests — while the tiles they were actually looking at
    // queued behind it. That is the "the tile queue gets bogged and stays
    // alive" report.
    if (moved) _warmGenerationOf?.call();
    _warm = Timer(const Duration(milliseconds: 500), _warmAround);
  }

  /// Cancels warm-up work in the controller, when there is a controller.
  void Function()? _warmGenerationOf;

  /// The most tiles one warm-up may queue. A screenful at street zoom is a
  /// dozen; at world zoom it is one. The cap is what stops a wide view from
  /// putting a hundred requests in front of the tile the reader is looking at.
  static const int kMaxWarmTiles = 18;


  /// True when the view on screen is outside every finished region pack
  /// while the map has no connection: the one case where "no tiles" is a
  /// fact to say out loud rather than a tile that has not arrived.
  bool _outsidePacks = false;

  /// Warm the tiles the next gesture will need, and only those.
  ///
  /// The scopes, in the order a reader meets them:
  ///
  ///  * **this zoom, one tile beyond the viewport** — the pan that is about to
  ///    happen, and never more than a screenful plus a ring;
  ///  * **the next zoom in, for the middle of the viewport** — a zoom in lands
  ///    on the centre, and fetching every child of a full screen is four times
  ///    the screen for a fifth of the benefit;
  ///  * **the zoom out levels up to two steps** — a zoom out draws from parents
  ///    immediately instead of showing blank until the finer tiles fail.
  ///
  /// Everything here runs on one generation token: [MapsController.cancelPrefetch]
  /// bumps it, and a loop from an older view stops at its next tile instead of
  /// finishing a list nobody is looking at.
  Future<void> _warmAround() async {
    if (!mounted || !_vectorSkin) return;
    final MapsController? maps =
        Provider.of<MapsController?>(context, listen: false);
    if (maps == null || !maps.online || !maps.viewIdle) return;
    _warmGenerationOf = maps.cancelPrefetch;
    final int generation = maps.warmGeneration;
    final MapCamera cam = _map.camera;
    final int z = cam.zoom.round().clamp(0, kOsmVector.maxNativeZoom);
    final LatLngBounds b = cam.visibleBounds;
    final GeoBox box =
        GeoBox(south: b.south, west: b.west, north: b.north, east: b.east);
    final TileRange r = tileRange(box, z);
    _noteCoverage(maps, box, z);

    // A ring of one tile around the viewport, capped: a very zoomed-out view can
    // cover hundreds of tiles, and a hundred queued requests is the bog.
    final List<(int, int, int)> ring = <(int, int, int)>[];
    for (int x = r.minX - 1; x <= r.maxX + 1 && ring.length < kMaxWarmTiles; x++) {
      for (int y = r.minY - 1;
          y <= r.maxY + 1 && ring.length < kMaxWarmTiles;
          y++) {
        ring.add((z, x, y));
      }
    }
    // One budget for the whole warm-up, not one per phase: three phases with
    // their own limits enqueued more after a settle than the thing they replaced
    // (46 against 36), which is the "queue gets bogged" report with a fresh coat
    // of paint.
    int left = kMaxWarmTiles;
    final int gotRing =
        await maps.prefetch(kOsmVector, ring, limit: left, generation: generation);
    left -= gotRing;
    if (left > 0) {
      // R114 — parents, so a zoom out draws a coarser picture straight away.
      left -= await maps.prefetchParents(kOsmVector, ring,
          limit: math.min(left, 8), generation: generation);
    }
    if (left > 0) {
      // Children of the middle, so a zoom in has detail rather than a blur.
      await maps.prefetchChildren(kOsmVector, centreTiles(r),
          limit: left, generation: generation);
    }
  }

  /// The self marker's bearing comes from the **phone's magnetometer**
  /// (`CompassHeading`), never from the radio: a MeshCore GPS reports a
  /// position, not a heading. A peer marker is therefore never rotated, and
  /// this stays null on a phone with no compass, which drops the wedge.
  void _noteCoverage(MapsController maps, GeoBox box, int z) {
    final bool outside = maps.archives.isNotEmpty && !maps.archiveCovers(box, z);
    if (outside == _outsidePacks) return;
    if (!mounted) return;
    setState(() => _outsidePacks = outside);
  }

  double? _headingDeg;

  /// The app's one compass when there is one above us, so the arrow and both
  /// radars answer from the same filter; its own only when shown alone.
  late final CompassHeading _compass;
  late final bool _ownsCompass;

  /// A peer's reach estimate in metres, from its signal and role.
  /// The radius of a peer's reach ring, or null when nothing was measured.
  ///
  /// A ring is a claim about *this peer*, so it needs evidence: a signal
  /// strength, or at least the distance we heard it from. Without either, the
  /// honest drawing is no ring — the old fallback drew the *radio's* link-budget
  /// range, which for the USA/Canada preset is tens of kilometres, so every
  /// unmeasured peer got a circle far larger than anything the map could show
  /// and the picture read as a field of huge green bubbles rather than as a
  /// mesh.
  ///
  /// The cap is the second half of the same point: on the ground, with a mast at
  /// one end and a handset at the other, a few kilometres is the practical
  /// ceiling whatever the link budget says. A ring beyond that would describe the
  /// radio rather than the peer, which is the self ring's job.
  static const double kPeerReachCeilingMeters = 5000;

  double? _reachMeters(
      DiscoveredNode n, MeshcoreController mc, SelfInfo? si) {
    final double? distance = mc.distanceMetersTo(n.latitude!, n.longitude!);
    if (n.rssi == null && distance == null) return null;
    final double meters = estimatedPeerReachMeters(
      rssiDbm: n.rssi?.toDouble(),
      distanceMeters: distance,
      peerType: n.type,
      ourSpreadingFactor: si?.spreadingFactor ?? 7,
      ourBandwidthKhz: si?.bandwidthKhz ?? 125.0,
      ourTxPowerDbm: si?.txPowerDbm ?? 14,
    );
    return meters.clamp(200, kPeerReachCeilingMeters);
  }

  /// R25+3 / R61 — basemap source. Starts on OSM; the picker offers
  /// every source in the maps catalogue (built-ins + custom servers).
  /// Session-scoped like the grid's view mode.
  static String _sourceId = kOsmStandard.id;

  /// R84 - a raster basemap chosen from the picker while the skin renders
  /// vector by default. Null means "the skin's own basemap". Without this
  /// the Studio picker was a dead control: it changed [_sourceId] and the
  /// vector layer ignored it, so choosing USGS Imagery did nothing.
  String? _rasterOverride;

  /// One-second tick that keeps a message bubble's fade honest.
  ///
  /// Only runs while a bubble is alive: a map that ticks every second forever
  /// to fade a mark that is not drawn is a battery complaint waiting to happen.
  Timer? _bubbleTick;

  void _ensureBubbleTick(bool anyLive) {
    if (anyLive && _bubbleTick == null) {
      _bubbleTick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
      });
    } else if (!anyLive && _bubbleTick != null) {
      _bubbleTick!.cancel();
      _bubbleTick = null;
    }
  }

  @override
  void initState() {
    super.initState();
    // R90 — the basemap is remembered across launches. It was session-only,
    // which meant every restart quietly reverted a deliberate choice.
    BasemapPrefs.load().then((String? id) {
      if (!mounted || id == null) return;
      setState(() {
        _sourceId = id;
        _rasterOverride = id;
      });
    });
    // Step three of the ladder, read before the first frame so the camera
    // opens where the user left it instead of jumping once the preference
    // arrives. A malformed value is dropped by the decoder.
    MapViewPrefs.load().then((SavedMapView? view) {
      if (!mounted || view == null) return;
      setState(() {
        _saved = view;
        if (!_centered) _zoom = view.zoom;
      });
    });
    // The same compass the radars use, rather than a second one from another
    // plugin: two sensors answering "which way am I facing" gave two answers,
    // and the map arrow and the dial disagreed at exactly the moment a user
    // would look at both.
    final CompassHeading? shared = context.sharedCompass;
    _ownsCompass = shared == null;
    _compass = shared ?? CompassHeading();
    _compass.addListener(_onCompass);
    _compass.start();
  }

  void _onCompass() {
    final double? h = _compass.heading;
    if (!mounted) return;
    if (h == null) {
      if (_headingDeg == null) return;
      setState(() => _headingDeg = null);
      return;
    }
    if (_headingDeg != null && (h - _headingDeg!).abs() < 1.0) return;
    setState(() => _headingDeg = h);
  }

  @override
  void dispose() {
    // Leaving the map stops the warm-up: an in-flight loop that keeps walking
    // its list after the tab is gone is the literal reading of "it stays alive".
    _warmGenerationOf?.call();
    _bubbleTick?.cancel();
    _warm?.cancel();
    _saveView?.cancel();
    _compass.removeListener(_onCompass);
    if (_ownsCompass) _compass.dispose();
    super.dispose();
  }

  /// A tap on the map that landed inside a density square names its nodes.
  ///
  /// A polygon hit test was tried first and it could not work: a square's
  /// centre is where its nodes are, so the pin's own marker took every tap
  /// inside a cell and the square was never the thing that was opened. Asking
  /// which square contains the tapped point has no such ordering problem, and
  /// a tap on empty map outside every square still does nothing.
  void _onMapTap(TapPosition _, LatLng point) {
    if (!_showDensity) return;
    for (final HexCell cell in _densityCells) {
      if (hexContains(cell.centre, _hexRadiusMetres, point)) {
        final MeshcoreController mc =
            Provider.of<MeshcoreController>(context, listen: false);
        _showDensityCell(context, mc, cell);
        return;
      }
    }
  }

  /// The camera's visible box, or null before the map has been laid out.
  ///
  /// `MapController.camera` throws until the map has rendered once, and this
  /// build runs on the first frame — before that. Reading it unguarded is a
  /// crash on every cold open, which is exactly what the basemap picker test
  /// caught.
  GeoBox? _visibleBox() {
    try {
      final LatLngBounds b = _map.camera.visibleBounds;
      return GeoBox(south: b.south, west: b.west, north: b.north, east: b.east);
    } catch (_) {
      return null;
    }
  }

  /// The cell size of the layer currently drawn, so the sheet can say what one
  /// square covers. Kept as a field because the sheet outlives the build.
  double _densityCellMetresShown = kDensityCellMetres;

  Future<void> _showDensityCell(
      BuildContext ctx, MeshcoreController mc, HexCell cell) {
    final Map<String, DiscoveredNode> byKey = <String, DiscoveredNode>{
      for (final DiscoveredNode n in mc.nodes) n.pubKeyHex: n,
    };
    final List<DiscoveredNode> inside = <DiscoveredNode>[
      for (final String k in cell.points)
        if (byKey[k] != null) byKey[k]!,
    ];
    final AppLocalizations l = AppLocalizations.of(ctx);
    final ColorScheme cs = Theme.of(ctx).colorScheme;
    return showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l.mapDensityCellTitle(cell.count),
                style: TextStyle(
                    fontSize: ctx.skin.type.sizeBodyLg,
                    fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l.mapDensityCellArea(densityCellLabel(_densityCellMetresShown)),
                style: TextStyle(
                    fontSize: ctx.skin.type.sizeBody,
                    color: cs.onSurfaceVariant),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final DiscoveredNode n in inside)
                    // MmPickerTile, not a bare ListTile: a row of this shape is
                    // a picker row by the product's own rule, and the guard
                    // that enforces it did its job here.
                    MmPickerTile(
                      title: n.name.isEmpty ? n.shortId : n.name,
                      value: l.mapDensityCellOpen,
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _showDetail(ctx, mc, n);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _zoomIn() {
    final double next = (_zoom + _zoomStep).clamp(_minZoom, _zoomMax);
    if (next == _zoom) return;
    setState(() => _zoom = next);
    _map.move(_map.camera.center, _zoom);
  }

  void _zoomOut() {
    final double next = (_zoom - _zoomStep).clamp(_minZoom, _zoomMax);
    if (next == _zoom) return;
    setState(() => _zoom = next);
    _map.move(_map.camera.center, _zoom);
  }

  /// The floor is the world view: zooming out to the whole globe is allowed,
  /// because the map's own fallback is that view and clamping it would snap
  /// the first frame.
  double get _minZoom => MapCentre.worldZoom;

  void _recenterOnSelf(LatLng centre, MapCentreSource rung) {
    _userMoved = false;
    _userCentre = null;
    _centredOn = rung;
    _map.move(centre, _zoom);
    _rememberView();
  }

  /// One explicit ask for a position, used by the banner's action. It reports
  /// why it failed so the banner can name the real problem rather than
  /// telling a user with location switched off to go outside.
  Future<void> _askForFix() async {
    if (_askingForFix) return;
    setState(() => _askingForFix = true);
    final MeshcoreController mc = context.read<MeshcoreController>();
    final LocationOutcome outcome = await mc.requestPhoneLocationFixOutcome();
    if (!mounted) return;
    setState(() {
      _askingForFix = false;
      _locationFailure = outcome.failure;
    });
  }

  /// The basemap picker: the app's one pick-one-of-N sheet, with each source's
  /// own attribution under it so the choice and the credit are read together.
  Future<void> _pickBasemap(
    BuildContext context,
    AppLocalizations l,
    List<MapSource> sources, {
    required String current,
  }) async {
    final String? id = await showMmPicker<String>(
      context: context,
      title: l.mapsSourcePick,
      current: current,
      items: <MmPickerItem<String>>[
        for (final MapSource s in sources)
          MmPickerItem<String>.option(
            s.id,
            s.name,
            detail: s.attribution.isEmpty ? null : s.attribution,
          ),
      ],
    );
    if (id == null || !mounted) return;
    setState(() {
      if (id == kOsmVector.id) {
        _rasterOverride = null;
      } else {
        _sourceId = id;
        // Vector is the default, so any raster pick is an override of it.
        _rasterOverride = id;
      }
    });
    BasemapPrefs.save(_rasterOverride);
  }

  /// The map's key: one row per mark, in the order they are drawn.
  Future<void> _showKey(
      BuildContext context, AppLocalizations l) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext c) {
        final MmSkin skin = c.skin;
        final ColorScheme cs = Theme.of(c).colorScheme;
        Widget row(Widget glyph, String label) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: <Widget>[
                  SizedBox(width: 32, height: 20, child: Center(child: glyph)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                            color: skin.color.fg,
                            fontSize: skin.type.sizeBodyLg)),
                  ),
                ],
              ),
            );
        Widget square(Color colour) => Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                  color: colour,
                  border: Border.all(color: skin.color.fg, width: 1)),
            );
        Widget circle(Color colour) => Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                  color: colour,
                  shape: BoxShape.circle,
                  border: Border.all(color: skin.color.fg, width: 1)),
            );
        return SafeArea(
          top: false,
          child: ListView(
            key: const ValueKey<String>('map-key-sheet'),
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(l.mapKeyTitle,
                    style: TextStyle(
                        color: skin.color.fgMuted,
                        fontSize: skin.type.sizeSm,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w600)),
              ),
              row(square(VizPalette.repeater), l.mapKeyRepeater),
              row(circle(VizPalette.companion), l.mapKeyClient),
              row(circle(skin.color.fg), l.mapKeyYou),
              row(
                  Icon(Icons.navigation,
                      size: 16, color: skin.color.fgMuted),
                  l.mapKeyHeading),
              row(
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: skin.color.accent, width: 1.2)),
                  ),
                  l.mapKeyReach),
              row(
                  Container(
                    width: 16,
                    height: 16,
                    color: VizPalette.of(skin)
                        .accent
                        .withValues(alpha: 0.35)),
                  l.mapKeyDensity),
              // The rest of what this map draws. The key named six of the marks
              // and left the four layers that change what the map *means*
              // unlabelled, which is how three different coloured things came to
              // look like one.
              row(
                  Container(
                    width: 20,
                    height: 12,
                    decoration: BoxDecoration(
                        color: cs.secondary.withValues(alpha: 0.35),
                        border: Border.all(color: cs.secondary)),
                  ),
                  l.mapKeyCoverage),
              row(
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: skin.color.alert, width: 2)),
                  ),
                  l.mapKeyGeofence),
              row(
                  Container(
                    width: 20,
                    height: 3,
                    color: cs.secondary.withValues(alpha: 0.7)),
                  l.mapKeyTrail),
              row(circle(VizPalette.companion), l.mapKeyMessage),
            ],
          ),
        );
      },
    );
  }

  /// Whether anything the overlays sheet owns is currently drawn, so the one
  /// control can say so at a glance.
  bool _anyOverlayShown(MapsController? maps) =>
      _showDensity ||
      _showCoverage ||
      (maps?.layers.any((EventLayer e) => e.visible) ?? false);

  /// Everything the map shows, in one sheet.
  ///
  /// The map had eleven controls down its right edge — a column taller than a
  /// phone is wide — and five of them were one switch each. A reader who wants to
  /// change what the map shows has one place to look now, and the column is short
  /// enough to leave the map itself a full edge.
  Future<void> _showOverlays(
    BuildContext context,
    AppLocalizations l,
    MapsController? maps,
    List<MapSource> sources,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext c) {
        final MmSkin skin = c.skin;
        final ColorScheme cs = Theme.of(c).colorScheme;
        final List<EventLayer> layers = maps?.layers ?? const <EventLayer>[];
        return StatefulBuilder(
          builder: (BuildContext c2, StateSetter setSheet) => SafeArea(
            top: false,
            child: ListView(
              key: const ValueKey<String>('map-overlays-sheet'),
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Text(l.mapOverlaysTitle,
                      style: TextStyle(
                          color: skin.color.fgMuted,
                          fontSize: skin.type.sizeSm,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w600)),
                ),
                SwitchListTile(
                  key: const ValueKey<String>('map-density-toggle'),
                  value: _showDensity,
                  title: Text(l.mapDensityShow,
                      style: TextStyle(
                          color: skin.color.fg, fontSize: skin.type.sizeBody)),
                  subtitle: _showDensity
                      ? Text(
                          l.mapDensityCellSize(
                              densityCellLabel(_densityCellMetresShown)),
                          style: TextStyle(
                              color: skin.color.fgMuted,
                              fontSize: skin.type.sizeSm))
                      : null,
                  onChanged: (bool v) {
                    setSheet(() => _showDensity = v);
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  key: const ValueKey<String>('map-coverage-toggle'),
                  value: _showCoverage,
                  title: Text(l.mapCoverageShow,
                      style: TextStyle(
                          color: skin.color.fg, fontSize: skin.type.sizeBody)),
                  onChanged: (bool v) {
                    setSheet(() => _showCoverage = v);
                    setState(() {});
                  },
                ),
                Divider(color: cs.outlineVariant, height: 16),
                if (layers.isEmpty)
                  // Said out loud rather than left blank: an overlay section
                  // with nothing under it reads as a loading state.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(l.mapsNoLayersShort,
                        key: const ValueKey<String>('map-overlays-no-layers'),
                        style: TextStyle(
                            color: skin.color.fgMuted,
                            fontSize: skin.type.sizeSm)),
                  ),
                if (layers.isNotEmpty) ...<Widget>[
                  for (final EventLayer e in layers)
                    SwitchListTile(
                      key: ValueKey<String>('map-layer-${e.id}'),
                      value: e.visible,
                      title: Text(e.name,
                          style: TextStyle(
                              color: skin.color.fg,
                              fontSize: skin.type.sizeBody)),
                      onChanged: (bool v) {
                        maps?.setLayerVisible(e, v);
                        setSheet(() {});
                        setState(() {});
                      },
                    ),
                ],
                Divider(color: cs.outlineVariant, height: 16),
                ListTile(
                  key: const ValueKey<String>('map-key-button'),
                  leading: Icon(Icons.key_outlined, color: skin.color.accent),
                  title: Text(l.mapKeyTitle,
                      style: TextStyle(
                          color: skin.color.fg, fontSize: skin.type.sizeBody)),
                  onTap: () => _showKey(context, l),
                ),
                ListTile(
                  key: const ValueKey<String>('map-offline-maps-button'),
                  leading: Icon(Icons.download_for_offline_outlined,
                      color: skin.color.accent),
                  title: Text(l.mapsTitle,
                      style: TextStyle(
                          color: skin.color.fg, fontSize: skin.type.sizeBody)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => c.push('/settings/maps'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  /// Drops a pin where the long-press landed and reports it on the active
  /// channel. The budget, the label check and the identity check all answer
  /// inside the sheet, so a refusal is explained where the user typed.
  Future<void> _createPlace(BuildContext ctx, LatLng point) async {
    final PlaceStore store = ctx.read<PlaceStore>();
    final Place? place = await PlaceCreateSheet.show(
      ctx,
      latitude: point.latitude,
      longitude: point.longitude,
      composer: placeComposerOf(ctx),
    );
    if (!mounted || place == null) return;
    store.markSeen(place.id);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).placeSent)),
    );
  }

  /// The node's distance trend, fed from this call. A caller that never opens
  /// the sheet never records a reading, which is why the first open says
  /// nothing about direction.
  RelationshipReading? _relationship(
      BuildContext ctx, MeshcoreController mc, DiscoveredNode n) {
    final RelationshipTracker? tracker =
        Provider.of<RelationshipTracker?>(context, listen: false);
    if (tracker == null || !n.hasLocation) return null;
    final OwnLocation? own = mc.ownLocation;
    if (own == null) return null;
    return tracker.updateBetween(
      n.pubKeyHex,
      fromLat: own.latitude,
      fromLon: own.longitude,
      toLat: n.latitude!,
      toLon: n.longitude!,
      at: DateTime.now(),
    );
  }

  Future<void> _showDetail(
      BuildContext ctx, MeshcoreController mc, DiscoveredNode n) {
    return showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => NodeDetailSheet(
        node: n,
        distanceMeters: n.hasLocation
            ? mc.distanceMetersTo(n.latitude!, n.longitude!)
            : null,
        // A trend needs two readings, so it is only claimed when there are
        // two: the first time a node is opened there is nothing to compare.
        relationship: _relationship(ctx, mc, n),
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
    // Kept for the warm-up timer and the zoom ceiling, which run outside a
    // build and so must not read a watching provider.

    final MapsController? maps = Provider.of<MapsController?>(context);
    // Fences are drawn when the app provides them; a harness that builds this
    // view on its own simply has none.
    final GeofenceController? geofences =
        Provider.of<GeofenceController?>(context);
    final List<StoredGeofence> fences =
        geofences?.fences ?? const <StoredGeofence>[];
    final List<MapSource> sources = maps?.sources ?? kBuiltInSources;
    final MapSource tileSource = sources.firstWhere(
        (MapSource s) => s.id == _sourceId,
        orElse: () => kOsmStandard);
    // R84 - what is actually drawn: the skin's vector style, or a raster
    // source the user picked over it.
    final MapSource shownSource = _rasterOverride == null
        ? tileSource
        : sources.firstWhere((MapSource s) => s.id == _rasterOverride,
            orElse: () => tileSource);
    // R90 — the vector basemap is available on every skin, not only the one
    // whose shape opted in: the style asset is a neutral dark palette, and
    // gating it made "switch the basemap" a dead control on six presets.
    final bool vectorDrawn = _rasterOverride == null;
    _vectorSkin = vectorDrawn;

    // R114 — is the current zoom outside what the downloaded pack holds, and
    // are we offline? That is the one case where a coarser tile is the
    // deliberate picture rather than a gap the network is filling.
    final int zoomLevel = _zoom.round();
    final ({int minZoom, int maxZoom})? packSpan =
        maps?.packZoomSpan(shownSource);
    final String? tilesOfflineNotice =
        StreetMapView.tilesOfflineNoticeFor(l, maps);

    final String? packZoomNotice = maps == null ||
            maps.online ||
            packSpan == null ||
            (zoomLevel >= packSpan.minZoom && zoomLevel <= packSpan.maxZoom)
        ? null
        : l.mapPackZoomOutside(packSpan.minZoom, packSpan.maxZoom);

    // One ladder decides both the camera and where "me" is drawn, so the two
    // cannot disagree: the phone's position, the radio's own position, the
    // view the user left, then the world view. A downloaded pack is not a
    // position and is not a rung.
    final MapCentre start = MapCentre.resolve(
      phone: mc.phoneLocationFix,
      radio: mc.selfInfo,
      last: _saved,
    );
    final bool hasPersonalPosition = start.source == MapCentreSource.phone ||
        start.source == MapCentreSource.radio;
    final double? selfLat = hasPersonalPosition ? start.centre.latitude : null;
    final double? selfLon = hasPersonalPosition ? start.centre.longitude : null;
    final bool hasFix = hasPersonalPosition;

    // The density squares, computed once per build rather than per layer: the
    // grouping walks every located node, and there are three layers to feed
    // (squares, counts, and the hit notifier's payloads).
    //
    // The anchor is our own fix when there is one, and otherwise the centroid
    // of the nodes themselves. Two anchors were tried and both were wrong: the
    // camera's centre is (0, 0) before the map controller attaches on the first
    // build, which threw every cell eleven degrees of longitude west of the
    // nodes it was describing, and refusing to draw without a fix made a control
    // that does nothing on the tab whose whole point is that it always draws.
    // The cell size follows the zoom, so a reading is legible at every scale
    // rather than only at the one zoom 250 m happened to suit.
    final double densityCellMetres = densityCellMetresFor(
      metresPerPixel: StreetMapView.metersPerPixel(
          _zoom, hasFix ? start.centre.latitude : 39),
    );
    _densityCellMetresShown = densityCellMetres;
    // Fill and number appear and disappear together, or a filled square with no
    // number reads as a large node pin. Hysteresis: appear at the readable size,
    // leave only once comfortably below it, so a pinch on the boundary does not
    // make the whole overlay blink.
    final double cellPx = densityCellMetres /
        StreetMapView.metersPerPixel(
            _zoom, hasFix ? start.centre.latitude : 39);
    final bool wantCells = _densityCellsDrawn
        ? cellPx >= kDensityLabelMinPx - 6
        : cellPx >= kDensityLabelMinPx;
    if (wantCells != _densityCellsDrawn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _densityCellsDrawn = wantCells);
      });
    }
    // The hexagon radius follows the zoom in bands, so the ground area is a
    // constant inside each band rather than creeping with every pinch.
    final double pxPerMetre = 1 /
        StreetMapView.metersPerPixel(
            _zoom, hasFix ? start.centre.latitude : 39);
    _hexRadiusMetres = hexRadiusForZoom(pxPerMetre);
    final List<DensityPoint> densityPoints = _showDensity
        ? <DensityPoint>[
            for (final DiscoveredNode n in mc.nodes)
              if (n.hasLocation)
                (lat: n.latitude!, lon: n.longitude!, pubKey: n.pubKeyHex),
          ]
        : const <DensityPoint>[];
    // The field, not a scatter of boxes: `hexField` returns every hexagon that
    // holds a node, each the same ground area within a zoom band, and the shade
    // comes from the count. The lattice is anchored to the visible box's own
    // north-west corner, so panning moves the field with the ground instead of
    // re-anchoring it on the operator's fix (which made the old squares step as
    // they walked).
    final List<HexCell> hexes = densityPoints.isEmpty
        ? const <HexCell>[]
        : hexField(
            points: densityPoints,
            box: _visibleBox() ??
                GeoBox(
                  south: start.centre.latitude - 0.01,
                  west: start.centre.longitude - 0.01,
                  north: start.centre.latitude + 0.01,
                  east: start.centre.longitude + 0.01,
                ),
            circumradiusMetres: _hexRadiusMetres,
            includeEmpty: true,
            maxCells: 260,
          );
    // The tap handler reads this, and it is the same list the layer draws, so
    // the cell that opens is the cell that was tapped.
    _densityCells = hexes;

    // The Map tab always draws: the world view is a real answer to "where am
    // I", and the owner asked for exactly that when no position is known. This
    // widget therefore has no "needs your position" screen at all — the grid's
    // street-map mode, which was the only caller that wanted one, has left the
    // picker, and the ladder above already centres on a real position when one
    // exists.
    // Take the ladder's camera on the first build, and again only when the
    // *source* improves (a fix arrives) while the user has not moved the map.
    // Comparing the source rather than the point is what keeps a rebuild - a
    // skin change, a toast, a poll - from yanking the camera.
    final bool sourceChanged = start.source != _centredOn;
    if (!_centered || (!_userMoved && sourceChanged)) {
      _zoom = start.zoom;
      _centredOn = start.source;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _map.move(start.centre, start.zoom);
        } catch (_) {/* map not laid out yet */}
        _centered = true;
        _rememberView();
      });
    }

    final List<DiscoveredNode> source = widget.filteredNodes ?? mc.nodes;
    final List<DiscoveredNode> withLoc = <DiscoveredNode>[
      for (final DiscoveredNode n in source)
        if (n.hasLocation) n
    ];

    final SelfInfo? si = mc.selfInfo;
    final double rangeM = si == null
        ? 1500.0
        : estimatedLoraRangeMeters(
            spreadingFactor: si.spreadingFactor,
            bandwidthKhz: si.bandwidthKhz,
            txPowerDbm: si.txPowerDbm,
          );

    // A reach ring and the movement trail are both estimates, and both used
    // to be drawn whether or not the screen could show them: a 6-20 km
    // estimate at street zoom is one arc sweeping the viewport with no centre
    // in sight, which reads as a stray line rather than a range, and a trail
    // of two fixes is one point of GPS jitter drawn as a segment beside the
    // marker. Both are now gated on being readable, and the trail is closed
    // onto the live fix so it ends on the marker.
    final double viewportMeters = MediaQuery.sizeOf(context).height *
        StreetMapView.metersPerPixel(_zoom, selfLat ?? 0);
    final List<CircleMarker> peerReachRings = <CircleMarker>[
      for (final DiscoveredNode n in withLoc)
        if (_reachMeters(n, mc, si) case final double meters)
          if (StreetMapView.reachRingReadable(meters, viewportMeters))
            CircleMarker(
              point: LatLng(n.latitude!, n.longitude!),
              radius: meters,
              useRadiusInMeter: true,
              color: const Color(0x00000000),
              borderColor: cs.tertiary.withValues(alpha: .55),
              borderStrokeWidth: 1.0,
            ),
    ];
    // Who has spoken in the last minute, at the place they spoke from. A node
    // with no position is left out rather than pinned to our own fix: a bubble
    // at the wrong place is a worse answer than no bubble.
    final DateTime now = DateTime.now();
    // One copy of the coverage record for the whole build. The getter returns an
    // unmodifiable copy, so reading it twice per build copies a mesh-sized map
    // twice.
    final Map<String, int> coverage = mc.coverageCells;

    final List<MessageBubbleMark> bubbles = <MessageBubbleMark>[
      for (final MapEntry<String, DateTime> e in mc.recentSpeakers.entries)
        if (now.difference(e.value) <= MeshcoreController.recentSpeakerWindow)
          if (mc.nodeByPubKey(e.key) case final DiscoveredNode n)
            if (n.latitude != null && n.longitude != null)
              MessageBubbleMark(
                node: n,
                remaining: 1 -
                    now.difference(e.value).inMilliseconds /
                        MeshcoreController.recentSpeakerWindow.inMilliseconds,
              ),
    ];
    _ensureBubbleTick(bubbles.isNotEmpty);

    final List<LatLng> trail = StreetMapView.trailPathFor(
      mc.ownTrail,
      selfLat: hasFix ? selfLat : null,
      selfLon: hasFix ? selfLon : null,
    );

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: StreetMapView.initialCentreFor(
                  resolved: start, userCentre: _userCentre),
              initialZoom: _zoom,
              minZoom: _minZoom,
              maxZoom: _zoomMax,
              interactionOptions: InteractionOptions(
                // Pan + pinch + scroll-wheel zoom; no rotation
                // (heading still works via the self-marker arrow).
                flags: widget.interactive
                    ? InteractiveFlag.drag |
                        InteractiveFlag.pinchZoom |
                        InteractiveFlag.scrollWheelZoom |
                        InteractiveFlag.doubleTapZoom
                    : InteractiveFlag.none,
              ),
              onPositionChanged: (MapCamera cam, bool hasGesture) {
                // A gesture is the user's own move: it suppresses the
                // automatic re-centre for the rest of this visit and it is
                // what the next launch should reopen at.
                if (hasGesture) {
                  _userMoved = true;
                  _userCentre = cam.center;
                  _zoom = cam.zoom;
                  _rememberView();
                }
                _scheduleWarm(moved: true);
              },
              // A long-press drops a place where the finger is: the map point
              // is what the user aimed at, so the report travels at exact
              // precision rather than the snapped default that belongs to
              // "here" (meshmore-places-spec.md §9).
              onTap: _onMapTap,
              onLongPress: (TapPosition _, LatLng point) =>
                  _createPlace(context, point),
              // R115 — the vector map is painted from this skin's tokens, so
              // the underlay has to be this skin's ground: a tile that has not
              // arrived yet must read as land in this skin, not as Studio's
              // charcoal in all seven.
              backgroundColor: vectorDrawn
                  ? context.skin.color.base
                  : cs.surfaceContainerHighest,
            ),
            children: <Widget>[
              // R25+3 / R61 — swappable basemap, served from the
              // offline map cache when one is in the tree.
              // R80 — Studio renders from a vector style: no raster
              // filter, sharp at every zoom, and the same tile store
              // behind it. The dimmed raster layer stays as the fallback
              // for a skin that has not opted in.
              // R90 — the basemap is not optional. The old layers button
              // could remove it entirely, leaving pins and range rings on
              // the bare skin; a map with no map underneath is not a state
              // worth offering.
              if (vectorDrawn)
                const VectorBasemapLayer()
              else
                basemapLayer(context, shownSource,
                    dim: context.skin.shape.dimmedBasemap),
              // The reception quilt, moved here from the grid's Coverage view
              // (that view was a second map doing the map's job). Drawn under
              // the reach circles so a cell never hides a range, and only when
              // there is something to draw.
              // Bound once. `mc.coverageCells` copies the whole record into an
              // unmodifiable map on every call, and this read it twice per
              // rebuild — on a mesh that has heard a few thousand adverts that is
              // two full map copies for one layer.
              if (coverage.isNotEmpty && _showCoverage)
                PolygonLayer(
                  polygons: coveragePolygons(
                    cells: coverage,
                    nowUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    color: cs.secondary,
                  ),
                ),
              // The equal-area density grid: node counts in kilometre
              // squares, so the map can answer "how many per square km" the
              // way the radar cannot. Under the pins and the reach circles,
              // over the quilt, because a cell is about where nodes are and a
              // ring is about how far they reach.
              if (hexes.isNotEmpty && _densityCellsDrawn)
                PolygonLayer<HexCell>(
                  // A continuous field rather than a scatter of boxes: every
                  // hexagon is the same ground area at every zoom, and its shade
                  // is its count. The skin's viz accent, not the theme's primary:
                  // a cell drawn in primary over this skin's own basemap was
                  // invisible on the phone.
                  polygons: <Polygon<HexCell>>[
                    for (final HexCell c in hexes)
                      Polygon<HexCell>(
                        points: hexCorners(c.centre, _hexRadiusMetres),
                        hitValue: c,
                        // The fill carries the count and the ink; the *edge* is
                        // what makes it a field. An accent-coloured lattice over
                        // a satellite photograph disappeared into the vegetation
                        // it was measuring, so the line is the skin's foreground
                        // — the one colour guaranteed to differ from the ground
                        // it is drawn on — and the fill keeps the accent.
                        color: VizPalette.of(context.skin)
                            .accent
                            .withValues(alpha: hexAlpha(c.count)),
                        borderColor: cs.onSurface
                            .withValues(alpha: c.count == 0 ? 0.22 : 0.55),
                        borderStrokeWidth: c.count == 0 ? 0.7 : 1.1,
                      ),
                  ],
                ),
              // R61 — event maps (festival streets, courses, camps).
              const EventLayersOverlay(),
              // R25+1 — range circle for self. Uses our radio-tuple
              // anchor (we know TX power + modulation).
              // R48 — per-peer reach circles. Sized via
              // [estimatedPeerReachMeters] from heard RSSI + known
              // distance instead of a flat radius. Drawn before the
              // marker icons so the pins stay on top.
              CircleLayer(
                circles: <CircleMarker>[
                  if (hasFix)
                    // The self range estimate, on the same readability rule:
                    // at street zoom a multi-kilometre circle is an arc with
                    // no centre in sight.
                    if (StreetMapView.reachRingReadable(rangeM, viewportMeters))
                      CircleMarker(
                        point: start.centre,
                        radius: rangeM,
                        useRadiusInMeter: true,
                        // Outline-only: even modest fill alpha accumulates
                        // unreadably over OSM tiles when many circles
                        // overlap. Border carries the signal; map stays
                        // legible underneath.
                        color: const Color(0x00000000),
                        borderColor: cs.tertiary.withValues(alpha: .75),
                        borderStrokeWidth: 1.4,
                      ),
                  // A fence is drawn as its radius plus the margin band the
                  // hysteresis actually uses: an entry is at 95 % of this
                  // circle, a leave at 105 %, so the pair of rings is the
                  // fence's real extent rather than a decoration.
                  for (final StoredGeofence f in fences) ...<CircleMarker>[
                    CircleMarker(
                      point: LatLng(f.latitude, f.longitude),
                      radius: f.radiusMeters,
                      useRadiusInMeter: true,
                      color: Colors.transparent,
                      borderColor: cs.secondary.withValues(alpha: .85),
                      borderStrokeWidth: 1.6,
                    ),
                    CircleMarker(
                      point: LatLng(f.latitude, f.longitude),
                      radius: f.radiusMeters * 1.05,
                      useRadiusInMeter: true,
                      color: Colors.transparent,
                      borderColor: cs.secondary.withValues(alpha: .35),
                      borderStrokeWidth: 1.0,
                    ),
                  ],
                  // Reach estimates, drawn only where the screen can show
                  // them (see `peerReachRings` above).
                  ...peerReachRings,
                ],
              ),
              // R25+1 — own-movement trail, oldest faded → newest
              // solid. Drawn as a single Polyline; per-segment alpha
              // would need multiple polylines so we go with a
              // single mid-alpha line for now. `trail` is empty unless the
              // fixes are a path (three points, twenty metres) and it ends on
              // the live fix, so a stray two-point segment cannot appear
              // beside the marker.
              if (trail.isNotEmpty)
                PolylineLayer(
                  polylines: <Polyline>[
                    Polyline(
                      points: trail,
                      strokeWidth: 3.0,
                      strokeCap: StrokeCap.round,
                      strokeJoin: StrokeJoin.round,
                      color: cs.secondary.withValues(alpha: .65),
                    ),
                  ],
                ),
              // Places (meshmore-places-spec.md §10): live reports only, a
              // countdown under each pin, neutral once opened, clustered
              // where pins would overlap.
              ListenableBuilder(
                listenable: context.read<PlaceStore>(),
                builder: (BuildContext c, Widget? _) => PlaceLayer(
                  store: context.read<PlaceStore>(),
                  onOpen: (Place place) => PlaceDetailSheet.show(
                    c,
                    place: place,
                    store: context.read<PlaceStore>(),
                    composer: placeComposerOf(c),
                    // A key-bound confirm/refute goes out as a DM to the
                    // reporter's own key, so the tally records it as binding
                    // rather than as a name the sender typed.
                    sendDirect: (Uint8List key, String text) async {
                      final String hex = key
                          .map((int b) => b.toRadixString(16).padLeft(2, '0'))
                          .join();
                      return await context
                              .read<MeshcoreController>()
                              .sendDirectText(hex, text) !=
                          null;
                    },
                  ),
                  onClusterTap: (LatLng centre) => _map.move(
                    centre,
                    (_zoom + 2).clamp(_minZoom, _zoomMax),
                  ),
                ),
              ),
              // Peer markers.
              MarkerLayer(
                markers: <Marker>[
                  for (final DiscoveredNode n in withLoc)
                    Marker(
                      point: LatLng(n.latitude!, n.longitude!),
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      child: Semantics(
                        button: true,
                        label: l.nodeMarkerSemantics(
                            n.name.isEmpty ? n.shortId : n.name),
                        child: GestureDetector(
                          onTap: () => _showDetail(context, mc, n),
                          child: _PeerGlyph(
                            node: n,
                            ring: context.skin.color.fg,
                            companion: VizPalette.companion,
                            repeater: VizPalette.repeater,
                            known: mc.known.contains(n.pubKeyHex),
                            favourite: mc.favorites.contains(n.pubKeyHex),
                          ),
                        ),
                      ),
                    ),
                  // A bubble over whoever just spoke, under the self marker so
                  // the reader's own position is never covered.
                  for (final MessageBubbleMark b in bubbles)
                    Marker(
                      point: LatLng(b.node.latitude!, b.node.longitude!),
                      width: MessageBubble.size,
                      height: MessageBubble.size,
                      alignment: Alignment.center,
                      child: IgnorePointer(
                        child: MessageBubble(
                          key: ValueKey<String>(
                              'map-msg-bubble-${b.node.pubKeyHex}'),
                          remaining: b.remaining,
                          color: VizPalette.companion,
                          label: l.mapMessageBubble(
                              b.node.name.isEmpty ? b.node.shortId : b.node.name),
                        ),
                      ),
                    ),
                  // Self marker last so it sits on top.
                  if (hasFix)
                    Marker(
                      point: start.centre,
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      child: _SelfGlyph(
                        colour: cs.primary,
                        // The ring is a skin token, not white: on the light
                        // skin a white ring around a pale dot disappears.
                        ring: context.skin.color.fg,
                        // The self bearing is the phone's magnetometer, the
                        // one heading in the app a radio never supplies.
                        headingDeg: _headingDeg,
                      ),
                    ),
                ],
              ),
              // The counts, above the pins: a count is the square's own tap
              // target, 48 dp square like any other control, with the number
              // drawn small inside it. Below the pins it was unreachable — a
              // pin's own box covers its cell's centre, which is where a badge
              // there would sit — and a tap meant for the square opened the
              // node instead.
              if (hexes.isNotEmpty && _densityCellsDrawn)
                MarkerLayer(
                  markers: <Marker>[
                    // Only cells that hold something get a number. The field
                    // is a continuous lattice now, so the empty cells are drawn
                    // as faint shapes; a "0" badge on each of them was a row of
                    // chips across the top of the map.
                    for (final HexCell c in hexes)
                      if (c.count > 0)
                      Marker(
                        point: c.centre,
                        width: 48,
                        height: 48,
                        // Centred on the cell's own centre. `topRight` put the
                        // badge's corner at the centre, so it covered the cell
                        // that was tapped and three neighbours with it.
                        alignment: Alignment.center,
                        child: Semantics(
                          key: ValueKey<String>('density-count-${c.id}'),
                          button: true,
                          label: l.mapDensityCellTitle(c.count),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _showDensityCell(context, mc, c),
                            child: Center(
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: context.skin.space.insideText,
                                    vertical: context.skin.space.insideText /
                                        2),
                                decoration: BoxDecoration(
                                  // Solid: a count sits over pins and route
                                  // strokes, and a wash let them show through
                                  // the digit.
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(kRadiusXs),
                                  border: Border.all(color: cs.outline),
                                ),
                                child: Text(
                                  '${c.count}',
                                  style: TextStyle(
                                    fontSize: context.skin.type.sizeMicro,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        // R69 — quiet, non-modal, not dismissable, no fill: a hairline
        // row that says why the map is not on you. Gone once a fix lands.
        // R70 — the credit line shares this bottom column with the banner
        // so the banner can never cover it (it did: R69 stacked the
        // banner over the bottom-left attribution).
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // The credit line follows what is actually drawn. R82 draws
              // OSM's own vector service, so one credit covers the tiles and
              // the data; a raster source keeps its own credit.
              MapAttribution(vectorDrawn
                  ? kOsmVector.attribution
                  : shownSource.attribution),
              // The wedge on the self marker is the one heading in the app,
              // and it comes from the phone's magnetometer, not from the
              // radio: a MeshCore node reports a position, never a facing. It
              // is drawn only while a compass reading exists, so the legend
              // for it appears only while there is an arrow to explain.
              if (_headingDeg != null && hasPersonalPosition)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.navigation,
                          size: context.skin.type.sizeMicro,
                          color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          l.mapCompassLegend,
                          key: const ValueKey<String>('map-compass-legend'),
                          softWrap: true,
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: context.skin.type.sizeMicro),
                        ),
                      ),
                    ],
                  ),
                ),
              // R114 — a pack has a zoom range. Outside it, offline, the map is
              // showing coarser tiles on purpose, and saying so once is the
              // difference between "working as designed" and "broken".
              if (tilesOfflineNotice != null)
                Container(
                  key: const ValueKey<String>('map-tiles-offline'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  color: cs.surface,
                  child: Text(tilesOfflineNotice,
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: context.skin.type.sizeSm)),
                ),
              if (packZoomNotice != null)
                Container(
                  key: const ValueKey<String>('map-pack-zoom-banner'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  color: cs.surface,
                  child: Text(packZoomNotice,
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: context.skin.type.sizeSm)),
                ),
              if (!hasPersonalPosition)
                _NoPositionBanner(
                  failure: _locationFailure,
                  asking: _askingForFix,
                  onAsk: _askForFix,
                  onOpenSettings: () =>
                      context.read<PermissionsService>().openAppSettingsPage(),
                  colour: cs,
                  skin: context.skin,
                ),
            ],
          ),
        ),
        if (widget.frozen)
          Positioned(
            left: 12,
            top: 12,
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
                  Text(l.mapFrozenBadge,
                      style: TextStyle(
                          color: cs.onTertiaryContainer,
                          fontSize: context.skin.type.sizeMicro,
                          letterSpacing: 1)),
                ],
              ),
            ),
          ),
        // The density cell size, stated where the counts are: a count only means
        // something next to the distance it is a count per.
        if (hexes.isNotEmpty)
          Positioned(
            left: StreetMapView.controlsInset,
            bottom: 92,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey<String>('map-density-size'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(kRadiusSm),
                  border: Border.all(color: cs.outline),
                ),
                child: Text(
                  l.mapDensityCellSize(densityCellLabel(densityCellMetres)),
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: context.skin.type.sizeMicro),
                ),
              ),
            ),
          ),
        // Zoom +/- + re-centre. Stacked vertically, top-right.
        Positioned(
          right: StreetMapView.controlsInset,
          top: StreetMapView.controlsInset,
          child: Material(
            key: const ValueKey<String>('map-controls'),
            // The control column carries icon-only buttons over the tiles:
            // 90 % of the surface let a bright label cross a glyph, so it is
            // the surface itself and the control-border tier, not a wash.
            color: cs.surface,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: mmRadius(context, 6),
              side: BorderSide(color: cs.outline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // One control for everything the map *shows*: the density
                // field, the reception quilt, the event layers and the key. Four
                // separate buttons put four cells in a column that was already
                // taller than the phone, and a reader who wanted two overlays had
                // to find two buttons that each said one word.
                IconButton(
                  key: const ValueKey<String>('map-overlays-button'),
                  tooltip: l.mapOverlaysTitle,
                  iconSize: 18,
                  constraints: const BoxConstraints(
                      minWidth: StreetMapView.controlCell,
                      minHeight: StreetMapView.controlCell),
                  icon: Icon(_anyOverlayShown(maps)
                      ? Icons.auto_awesome
                      : Icons.auto_awesome_outlined),
                  onPressed: () => _showOverlays(context, l, maps, sources),
                ),
                IconButton(
                  tooltip: l.gridZoomTighter,
                  iconSize: 18,
                  constraints: const BoxConstraints(
                      minWidth: StreetMapView.controlCell,
                      minHeight: StreetMapView.controlCell),
                  icon: const Icon(Icons.add),
                  onPressed: _zoom < _zoomMax ? _zoomIn : null,
                ),
                IconButton(
                  tooltip: l.gridZoomWider,
                  iconSize: 18,
                  constraints: const BoxConstraints(
                      minWidth: StreetMapView.controlCell,
                      minHeight: StreetMapView.controlCell),
                  icon: const Icon(Icons.remove),
                  onPressed: _zoom > _minZoom ? _zoomOut : null,
                ),
                IconButton(
                  tooltip: l.streetMapRecenter,
                  iconSize: 18,
                  constraints: const BoxConstraints(
                      minWidth: StreetMapView.controlCell,
                      minHeight: StreetMapView.controlCell),
                  icon: const Icon(Icons.my_location),
                  // Always available: with a position it re-centres, and
                  // without one it asks for a position and says what went
                  // wrong instead of being a dead button.
                  onPressed: () {
                    if (hasPersonalPosition) {
                      _recenterOnSelf(start.centre, start.source);
                    } else {
                      _askForFix();
                    }
                  },
                ),
                // R25+3 / R61 — basemap picker.
                //
                // A `PopupMenuButton`, until the owner read it on the device:
                // a bare list floating over the map with no title, no tick and
                // the skin's type and shape nowhere in it, which is the one
                // shape R104 removed from the grid's pickers. It is the app's
                // own picker now — a sheet with the source named, the current
                // one ticked and an attribution line, because a picker that
                // names a source without its credit is a licensing gap as well
                // as a plain-looking menu.
                IconButton(
                  key: const ValueKey<String>('map-basemap-picker'),
                  tooltip: l.mapsSourcePick,
                  iconSize: 18,
                  constraints: const BoxConstraints(
                      minWidth: StreetMapView.controlCell,
                      minHeight: StreetMapView.controlCell),
                  icon: const Icon(Icons.map),
                  onPressed: () => _pickBasemap(context, l, sources,
                      current: vectorDrawn ? kOsmVector.id : shownSource.id),
                ),
                // Reporting a place is a control in this column, not a panel
                // on the left: a labelled box at the bottom left overlapped the
                // density chip above the attribution, and put one map tool on
                // the opposite edge from every other one. The long-press stays
                // as the fast path, and the point reported is the one at the
                // middle of the screen either way.
                IconButton(
                  key: const ValueKey<String>('map-report-place'),
                  tooltip: l.mapReportPlace,
                  iconSize: 18,
                  constraints: const BoxConstraints(
                      minWidth: StreetMapView.controlCell,
                      minHeight: StreetMapView.controlCell),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  onPressed: () => _createPlace(context, _map.camera.center),
                ),
                // Host tools (the Map tab's offline maps and places) join the
                // same column, under the built-in controls, so every map tool
                // sits on one edge instead of two.
                ...widget.controlExtras,
              ],
            ),
          ),
        ),
        // R84 — no connection and no pack over this view: the tiles will not
        // arrive, so the map says why instead of leaving a blank area that
        // looks like a rendering fault.
        if (_outsidePacks && !(maps?.online ?? true))
          Positioned(
            left: 12,
            // Clear of the right-hand control column, whose top cell is the
            // density toggle: the banner and "you are offline" co-occur, so this
            // used to cover the control exactly when it mattered.
            right: StreetMapView.controlsInset + StreetMapView.controlCell,
            top: 12,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: mmRadius(context, 4),
                ),
                child: Text(
                  l.mapsOutsidePacks,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: cs.onSurface, fontSize: context.skin.type.sizeSm),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PeerGlyph extends StatelessWidget {
  const _PeerGlyph({
    required this.node,
    required this.ring,
    required this.companion,
    required this.repeater,
    required this.known,
    required this.favourite,
  });
  final DiscoveredNode node;

  /// R115 — the outline that separates a coloured dot from the basemap. It
  /// was white, which is invisible on a light basemap; the skin's foreground
  /// is light on the dark presets and dark on the light one, so one rule
  /// holds in every theme.
  final Color ring;
  final Color companion;
  final Color repeater;
  final bool known;
  final bool favourite;

  @override
  Widget build(BuildContext context) {
    final bool isRepeater = node.type == 2;
    final Color base = isRepeater ? repeater : companion;
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        if (isRepeater)
          // A square, not a triangle: a triangle reads as a heading arrow and
          // a radio reports no bearing, so the shape must not imply one.
          CustomPaint(
            size: const Size(13, 13),
            painter: _SquareGlyphPainter(color: base, ring: ring),
          )
        else
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: base,
              border: Border.all(color: ring, width: 1.0),
            ),
          ),
        if (favourite)
          Positioned(
            top: 0,
            right: 0,
            child: Icon(Icons.star, size: 10, color: repeater),
          )
        else if (known)
          Positioned(
            top: 0,
            right: 0,
            child: Icon(Icons.circle, size: 8, color: companion),
          ),
      ],
    );
  }
}

class _SquareGlyphPainter extends CustomPainter {
  _SquareGlyphPainter({required this.color, required this.ring});
  final Color color;
  final Color ring;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = color;
    final Paint stroke = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final RRect r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(1),
    );
    canvas.drawRRect(r, fill);
    canvas.drawRRect(r, stroke);
  }

  @override
  bool shouldRepaint(covariant _SquareGlyphPainter old) =>
      color != old.color || ring != old.ring;
}

class _SelfGlyph extends StatelessWidget {
  const _SelfGlyph(
      {required this.colour, required this.ring, required this.headingDeg});
  final Color colour;
  final Color ring;
  final double? headingDeg;

  @override
  Widget build(BuildContext context) {
    final double rot =
        headingDeg == null ? 0.0 : headingDeg! * 3.141592653589793 / 180.0;
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        // Three-ring bullseye.
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colour.withValues(alpha: .18),
          ),
        ),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colour.withValues(alpha: .35),
          ),
        ),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colour,
            border: Border.all(color: ring, width: 1.5),
          ),
        ),
        if (headingDeg != null)
          Transform.rotate(
            angle: rot,
            child: CustomPaint(
              size: const Size(40, 40),
              painter: _HeadingWedgePainter(color: colour),
            ),
          ),
      ],
    );
  }
}

class _HeadingWedgePainter extends CustomPainter {
  _HeadingWedgePainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = color;
    final double cx = size.width / 2;
    final Path p = Path()
      ..moveTo(cx, 2) // tip toward "up" at 0° heading
      ..lineTo(cx - 5, 12)
      ..lineTo(cx + 5, 12)
      ..close();
    canvas.drawPath(p, fill);
  }

  @override
  bool shouldRepaint(covariant _HeadingWedgePainter old) => color != old.color;
}

/// What the map says when it has no position, and the one action that helps.
///
/// Two different problems used to share one sentence: permission is missing
/// (nothing can produce a position until the user allows it) and no position
/// has arrived yet (the phone or the radio may yet report one). They read
/// differently and act differently, which is the whole point of the split.
class _NoPositionBanner extends StatelessWidget {
  const _NoPositionBanner({
    required this.failure,
    required this.asking,
    required this.onAsk,
    required this.onOpenSettings,
    required this.colour,
    required this.skin,
  });

  final LocationFailure? failure;
  final bool asking;
  final VoidCallback onAsk;
  final VoidCallback onOpenSettings;
  final ColorScheme colour;
  final MmSkin skin;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String message;
    final String action;
    final VoidCallback press;
    switch (failure) {
      case LocationFailure.permissionDenied:
        message = l.mapLocationOffApp;
        action = l.mapLocationAllow;
        press = onAsk;
      case LocationFailure.permissionDeniedForever:
        message = l.mapLocationBlockedApp;
        action = l.mapLocationOpenSettings;
        press = onOpenSettings;
      case LocationFailure.servicesDisabled:
        message = l.mapLocationOffDevice;
        action = l.mapLocationOpenSettings;
        press = onOpenSettings;
      case LocationFailure.timeout:
      case LocationFailure.failed:
      case null:
        message = l.mapNoPositionYet;
        action = l.mapNoPositionFind;
        press = onAsk;
    }
    return Container(
      key: const ValueKey<String>('map-no-position-banner'),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: colour.surface,
        border: Border(top: BorderSide(color: colour.outlineVariant)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.location_searching,
              size: 16, color: colour.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colour.onSurfaceVariant,
                fontSize: skin.type.sizeSm,
              ),
            ),
          ),
          MmAction(
            key: const ValueKey<String>('map-no-position-action'),
            dense: true,
            label: asking ? l.mapNoPositionAsking : action,
            onPressed: asking ? null : press,
          ),
        ],
      ),
    );
  }
}
