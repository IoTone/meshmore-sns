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
import '../geofence/geofence_create_sheet.dart';
import '../geofence/geofence_engine.dart';
import '../maps/geofence_render.dart';
import '../geofence/geofence_store.dart';
import '../maps/basemap.dart';
import '../cue/cue_service.dart';
import '../maps/density_overlay.dart';
import '../maps/hex_field.dart';
import '../maps/message_bubble.dart';
import '../theme/viz_palette.dart';
import '../util/mm_format.dart';
import '../maps/basemap_prefs.dart';
import '../maps/compass.dart';
import '../maps/map_centre.dart';
import '../perms/location_service.dart';
import '../perms/permissions_service.dart';
import '../maps/event_layer.dart';
import '../maps/map_source.dart';
import '../maps/map_overlay_prefs.dart';
import '../maps/map_view_state.dart';
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

  /// How many cells the column draws today: layers, zoom in, zoom out,
  /// recentre, report a place. Pinned by `test/screens/map_chrome_test.dart` so
  /// a new control has to update this rather than silently misplacing whatever
  /// is placed beside the column.
  ///
  /// The basemap cell is gone: the ground is the first section of the layers
  /// sheet now, because "what the map shows" was two menus.
  static const int controlCount = 5;

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
    // **A trail is a walk, not a join-the-dots.** The recorded fixes are whatever
    // the radio and the phone reported, and one of them can be wrong: a fix that
    // arrives with a stale or transposed position puts a point kilometres away,
    // and joining it drew a line straight across the map — the "green line
    // extending out" the owner saw, with nothing on screen to say it was a bad
    // sample rather than a route. Only the last contiguous run is drawn: a gap
    // larger than `trailMaxGapMeters` starts a new run, and everything before it
    // is dropped rather than connected.
    final List<LatLng> run = <LatLng>[];
    for (final LatLng p in pts) {
      if (run.isNotEmpty) {
        final double gap =
            const Distance().as(LengthUnit.Meter, run.last, p);
        if (gap > trailMaxGapMeters) run.clear();
      }
      run.add(p);
    }
    if (run.length < trailMinPoints) return const <LatLng>[];
    final double span =
        const Distance().as(LengthUnit.Meter, run.first, run.last);
    return span < trailMinSpanMeters ? const <LatLng>[] : run;
  }

  /// The largest gap a trail will join, in metres.
  ///
  /// Two kilometres is two minutes of driving and well under the shortest useful
  /// LoRa link, so a gap that big is a bad sample rather than a walk. Anything
  /// further apart is a different walk.
  static const double trailMaxGapMeters = 2000;

  /// Which gestures the map itself may claim.
  ///
  /// A drag that starts on a corner handle belongs to the handle: the map's pan
  /// and the handle's pan are both in the arena for it, and the map won, which is
  /// why the screen said "drag a corner to move it" while the picture slid and
  /// the corner stayed. While a finger is down on a handle the map's pan is
  /// removed; pinch and wheel zoom stay, because they are two-finger or not a
  /// pan and cannot be confused with a handle drag.
  @visibleForTesting
  static int mapFlagsFor({
    required bool interactive,
    required bool draggingCorner,
  }) {
    if (!interactive) return InteractiveFlag.none;
    if (draggingCorner) {
      return InteractiveFlag.pinchZoom | InteractiveFlag.scrollWheelZoom;
    }
    return InteractiveFlag.drag |
        InteractiveFlag.pinchZoom |
        InteractiveFlag.scrollWheelZoom |
        InteractiveFlag.doubleTapZoom;
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
  // The coverage quilt used to live here, on by default. It is gone from the
  // map: what it recorded was our own position trail plus every peer's
  // advertised position, which is a breadcrumb route and a duplicate of the
  // pins, not where reception happened. Shading a map with that reads as a
  // survey it never made, and it was the loudest thing on the map at every
  // zoom. The record itself is untouched and still has its own screen at
  // `/settings/coverage`, which is where a survey belongs: a page that states
  // what it counted.

  /// What the map has been asked to draw, read from the store at startup and
  /// written back whenever it changes.
  ///
  /// One value rather than a field per toggle: the store and the screen cannot
  /// disagree about a flag, and a second overlay becomes one more field here
  /// instead of one more piece of state that has to remember to persist itself.
  MapOverlayPrefs _overlays = MapOverlayPrefs.defaults;

  /// The corners of a fence being drawn, in the order they were tapped.
  ///
  /// Empty means not drawing. A fence used to be a circle chosen from a radius
  /// ladder, which cannot follow a property line or a parking row; drawing one
  /// is the gesture that makes the shape the reader's.
  List<LatLng> _draft = const <LatLng>[];

  /// True while a finger is on a corner handle.
  ///
  /// See `interactionOptions` above: the map must not pan a drag that belongs to
  /// a corner, and this is the flag that tells it so.
  bool _draggingCorner = false;

  /// The equal-area density overlay, off by default: it is a reading about the
  /// mesh, not a record of it, so it is something to ask for rather than
  /// something to dismiss on every visit.
  bool get _showDensity => _overlays.density;

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

  /// The field and its polygons, and the inputs they were built from.
  ///
  /// The field is the most expensive thing this screen computes: a lattice over
  /// the viewport, a cell per hexagon, and six corners per cell. It used to be
  /// rebuilt on every build, and the map rebuilds for reasons that have nothing
  /// to do with the field — a message bubble fading, a skin change, a poll, a
  /// geofence sample. Memoising it on the inputs that actually change the
  /// picture is what keeps a rebuild cheap enough to be harmless.
  List<HexCell> _hexCache = const <HexCell>[];
  List<Polygon<HexCell>> _hexPolygons = const <Polygon<HexCell>>[];
  String _hexKey = '';

  /// The polygon list's own key: the field it describes and the skin it is
  /// painted in. Readiness is deliberately *not* part of it — see
  /// [_schedulePolygonRebuild].
  String _hexPolyKey = '';

  /// Set when a coalesced readiness tick has asked for a new polygon list.
  ///
  /// The list itself is rebuilt whole and thrown away whole: a polygon is a view
  /// of one cell at one cell size, and holding them alive would keep geometry
  /// that the next zoom step invalidates. What costs is building the list a dozen
  /// times for a dozen tile arrivals, and that is what the tick prevents.
  bool _hexPolyStale = true;

  /// The readiness revision the field was last built for.
  int _hexReadyRev = -1;

  /// The camera zoom the field on screen was built for.
  ///
  /// The owner's rule, said three times and only now true: the moment the map
  /// zooms, the cells that were measured at the old zoom are *not* the cells at
  /// the new one, so they must stop being drawn at once — not when the new
  /// lattice happens to be built. While the camera is moving this differs from
  /// [_zoom] by more than [_kFieldZoomSettle], the field draws nothing, and the
  /// rebuild is scheduled for the moment the camera stops.
  double _fieldZoom = double.nan;

  static const double _kFieldZoomSettle = 0.004;

  /// True from the first frame of a camera gesture until it settles.
  ///
  /// The field is not drawn while this is set. A screen of field is ~1,600
  /// polygons, and flutter_map builds and culls every one of them on every
  /// camera frame: during a pinch that is the difference between a lattice that
  /// tracks the map and one that lags it by a visible beat. Nothing is lost by
  /// hiding it — the cells were measured for the zoom the reader is leaving.
  bool _cameraMoving = false;

  Timer? _fieldRebuild;
  void _scheduleFieldRebuild() {
    // Re-arm on every call: a gesture that keeps moving keeps pushing the
    // rebuild out, and the field only comes back when the camera has stopped for
    // the whole window.
    _fieldRebuild?.cancel();
    _fieldRebuild = Timer(const Duration(milliseconds: 140), () {
      _fieldRebuild = null;
      if (!mounted) return;
      // Re-key the field so it is rebuilt at the zoom the camera settled on: the
      // cells are a function of the zoom, and the tile readiness asked about is
      // a function of the rounded zoom.
      _hexKey = '';
      _fieldZoom = _zoom;
      _cameraMoving = false;
      setState(() {});
    });
  }

  Timer? _hexPolyTimer;

  /// One rebuild per burst of tile arrivals.
  void _schedulePolygonRebuild() {
    if (_hexPolyTimer?.isActive ?? false) return;
    _hexPolyTimer = Timer(const Duration(milliseconds: 120), () {
      _hexPolyTimer = null;
      if (!mounted) return;
      if (_hexPolyStale) return; // a field rebuild is already queued
      _hexPolyStale = true;
      setState(() {});
    });
  }

  /// The hexagon's circumradius, in metres, for the current zoom: a cell that is
  /// legible as a shape at street zoom and does not become a mosaic at a city
  /// view. Unlike the squares this replaces, the *ground* area stays fixed while
  /// the zoom changes within a band, so the field is read as one thing.
  double _hexRadiusMetres = kDefaultHexCircumradiusMetres;
  bool _centered = false;

  /// The view the user left, read once at startup. It is step three of the
  /// ladder, which is the "centred on them" that matters most in practice.
  SavedMapView? _saved;

  /// The short-term memory: where the camera was a moment ago, so a tab switch
  /// comes back to it. Null in a harness that does not provide one.
  MapViewState? _viewState;

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
      // Two memories, two lifetimes: the holder answers a tab switch, the
      // preference answers a cold start. See `MapViewState`.
      _viewState?.remember(centre: cam.center, zoom: cam.zoom);
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

  /// Warm the zoom the reader is on, and nothing else.
  ///
  /// This used to warm three scopes: the ring around this viewport, the two
  /// ancestor levels a zoom out would draw from, and the children of the middle
  /// for a zoom in. Two thirds of that work was for a gesture that may never
  /// come, and it was spent out of the same queue as the tiles the reader is
  /// actually looking at — so the picture on screen arrived later so that a
  /// hypothetical pinch could arrive sooner.
  ///
  /// The rule now is one zoom level: this viewport and one tile beyond it, at
  /// the zoom on screen, first in the queue. A zoom out draws the ancestors it
  /// already has on disk (`basemap.dart` upscales an ancestor while a tile
  /// loads) and a zoom in shows the upscaled parent for a moment, which is what
  /// the tile pyramid is for.
  ///
  /// The whole warm-up runs on one generation token: [MapsController.cancelPrefetch]
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
    await maps.prefetch(kOsmVector, ring,
        limit: kMaxWarmTiles, generation: generation);
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


  /// The app's one compass when there is one above us, so the arrow and both
  /// radars answer from the same filter; its own only when shown alone.
  late final CompassHeading _compass;
  late final bool _ownsCompass;

  /// How far away we actually heard this peer, in metres, or null.
  ///
  /// This used to be an *estimated reach*: the heard RSSI was inverted through a
  /// log-distance path-loss model and the answer drawn as a circle around the
  /// peer. Research on 2026-11-14 says that circle is not a fact and cannot be
  /// made into one:
  ///
  /// - the RSSI of a received packet describes the last hop, not the sender's
  ///   own reach, and a packet relayed by a repeater carries the repeater's
  ///   signal (the app's hop count proves it was relayed);
  /// - inverting it needs a path-loss exponent that varies from 1.58 to 4 in
  ///   published campaigns, so the same reading implies ranges a factor of two
  ///   to four apart, and the best-fitting model in the largest field study
  ///   left about 10 dB of residual;
  /// - the reading also contains the peer's transmit power, antenna gain and
  ///   feed loss, none of which the packet carries.
  ///
  /// No mainstream client draws a per-node radius for those reasons. Meshtastic
  /// bands SNR against the preset's demodulation floor and calls RSSI
  /// display-only, the MeshCore signal tester plots receptions at the position
  /// where they happened, and MeshCore One draws a neighbour map.
  ///
  /// So the ring is the one thing the app can prove: the distance between the
  /// peer's reported position and ours. With no position on either side there is
  /// no ring, because there is nothing to draw a ring around.
  static const double kPeerReachCeilingMeters = 5000;

  double? _reachMeters(
      DiscoveredNode n, MeshcoreController mc, SelfInfo? si) {
    final double? distance = mc.distanceMetersTo(n.latitude!, n.longitude!);
    if (distance == null || !distance.isFinite || distance <= 0) return null;
    return distance.clamp(200, kPeerReachCeilingMeters);
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
    // The session's own memory, read before the disk preference so a basemap
    // picked a moment ago is not overwritten by the one from last week.
    //
    // The lookup tries the non-nullable registration first: `Provider.of<X?>`
    // does not match a provider registered as `X`, and the app registers the
    // real thing. Reading only the nullable spelling returned null in the app
    // while passing in a harness that happened to use the nullable one.
    _viewState = _findViewState(context);
    _viewState?.addListener(_onViewStateRequest);
    // A request made while no map was mounted is still waiting: the reader
    // asked, left the screen, and arrived here. One frame after the first
    // render is when the camera exists and can be moved.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onViewStateRequest());
    final String? sessionSource = _viewState?.sourceId;
    if (sessionSource != null) {
      _sourceId = sessionSource;
      _rasterOverride = sessionSource;
    }
    // R90 — the basemap is remembered across launches. It was session-only,
    // which meant every restart quietly reverted a deliberate choice.
    BasemapPrefs.load().then((String? id) {
      if (!mounted || id == null) return;
      // A basemap chosen this session wins over the one on disk.
      if (_viewState?.sourceId != null) return;
      setState(() {
        _sourceId = id;
        _rasterOverride = id;
      });
    });
    // Step three of the ladder, read before the first frame so the camera
    // opens where the user left it instead of jumping once the preference
    // arrives. A malformed value is dropped by the decoder.
    // What the reader asked the map to draw. Session-only until now: a
    // reader who turned the hexagon field on found it off again on the next
    // launch, which reads as the app forgetting a decision they made.
    MapOverlayPrefsStore.load().then((MapOverlayPrefs prefs) {
      if (!mounted || prefs == _overlays) return;
      setState(() => _overlays = prefs);
    });
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

  /// The phone's bearing, kept out of `setState` on purpose.
  ///
  /// A compass sample arrives several times a second while the phone turns, and
  /// rebuilding this screen for one of them rebuilt every marker, every reach
  /// ring, the density field and the coverage quilt — the whole map, to move one
  /// arrow. The notifier rebuilds the arrow and the legend that reads it, and
  /// nothing else.
  final ValueNotifier<double?> _heading = ValueNotifier<double?>(null);

  void _onCompass() {
    final double? h = _compass.heading;
    if (!mounted) return;
    final double? current = _heading.value;
    if (h == null) {
      if (current != null) _heading.value = null;
      return;
    }
    if (current != null && (h - current).abs() < 1.0) return;
    _heading.value = h;
  }

  /// The app-scoped view memory, however it was registered.
  static MapViewState? _findViewState(BuildContext context) {
    try {
      return Provider.of<MapViewState>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Someone outside the map asked to look at a place.
  ///
  /// A request, not a memory: another screen named a camera and this is the
  /// first map that can obey it. It is taken once, so a later pan is not undone
  /// by a request that was already answered.
  void _onViewStateRequest() {
    // A reshape is asked for the same way a camera move is, and answered here
    // for the same reason: the fence list cannot reach this State, and the map
    // is the only surface that can drag a corner.
    final String? reshape = _viewState?.takeReshapeFence();
    if (reshape != null) _beginReshape(reshape);
    final ({LatLng centre, double zoom})? asked = _viewState?.takeRequest();
    if (asked == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _map.move(asked.centre, asked.zoom);
      } catch (_) {
        // The map has not rendered yet; it will, and a request that arrived
        // during that frame is one frame early rather than lost.
      }
      // A request is a deliberate move, so the position ladder must not pull
      // the camera back to the reader's own fix on the next sample.
      _userMoved = true;
      _rememberView();
    });
  }

  @override
  void dispose() {
    // Leaving the map stops the warm-up: an in-flight loop that keeps walking
    // its list after the tab is gone is the literal reading of "it stays alive".
    _warmGenerationOf?.call();
    _bubbleTick?.cancel();
    _hexPolyTimer?.cancel();
    _fieldRebuild?.cancel();
    _warm?.cancel();
    _saveView?.cancel();
    _compass.removeListener(_onCompass);
    _viewState?.removeListener(_onViewStateRequest);
    _heading.dispose();
    if (_ownsCompass) _compass.dispose();
    // The map's own controller owns a broadcast `StreamController` and an
    // `AnimationController` (flutter_map 7.0.2, `MapControllerImpl.dispose`).
    // Neither is closed by the widget: leaving the screen without this leaked
    // both, and a live `AnimationController` is a ticker that keeps asking for
    // frames. The owner's report is that the app periodically stops responding,
    // and the map is the screen that is opened and left most often.
    _map.dispose();
    super.dispose();
  }

  /// A tap on the map that landed inside a density square names its nodes.
  ///
  /// A polygon hit test was tried first and it could not work: a square's
  /// centre is where its nodes are, so the pin's own marker took every tap
  /// inside a cell and the square was never the thing that was opened. Asking
  /// which square contains the tapped point has no such ordering problem, and
  /// a tap on empty map outside every square still does nothing.
  /// What a long-press on the map makes: a place, or a fence.
  ///
  /// One extra tap on the place path, and the reason is that a fence had no
  /// map gesture at all: it could only be created from Settings, three taps
  /// away, by typing a radius. A chooser is the smallest thing that gives the
  /// fence a gesture without taking the place's away.
  Future<void> _createHere(BuildContext context, LatLng point) async {
    // While a fence is being drawn, one gesture means one thing: a **tap** adds
    // a corner (`_onMapTap`). This handler used to add one too, so a reader who
    // tapped, saw nothing they expected, and then held the map to look around
    // got a second corner a finger's width away — and the outline joined the pair
    // into the zigzag that made the whole shape look wrong.
    if (_draft.isNotEmpty) return;
    final AppLocalizations l = AppLocalizations.of(context);
    // Captured before the first await: the sheet's own context is gone by the
    // time the fence is saved, and this State is the thing that outlives it.
    final GeofenceController? fences =
        Provider.of<GeofenceController?>(context, listen: false);
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              key: const ValueKey<String>('map-create-place'),
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(l.mapReportPlace),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(sheet, 'place'),
            ),
            ListTile(
              key: const ValueKey<String>('map-create-fence'),
              leading: const Icon(Icons.radio_button_unchecked),
              title: Text(l.geofenceCreateTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(sheet, 'fence'),
            ),
            ListTile(
              key: const ValueKey<String>('map-draw-fence'),
              leading: const Icon(Icons.pentagon_outlined),
              title: Text(l.geofenceDrawTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(sheet, 'draw'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'place') {
      await _createPlace(this.context, point);
      return;
    }
    if (choice == 'draw') {
      _startDrawing(point);
      return;
    }
    // The State's own context, not the parameter: the parameter is the caller's
    // and the analyzer is right that it cannot be trusted across the await.
    final ({String label, double radiusMeters})? made =
        await showModalBottomSheet<({String label, double radiusMeters})>(
      context: this.context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => GeofenceCreateSheet(
        latitude: point.latitude,
        longitude: point.longitude,
      ),
    );
    if (made == null || !mounted || fences == null) return;
    // The State's own context, not the parameter: the parameter is the caller's
    // and cannot be trusted across the await that just happened.
    final CueService? cue = this.context.cue;
    await fences.addFence(
      label: made.label.isEmpty
          ? l.geofenceDefaultName(fences.fences.length + 1)
          : made.label,
      latitude: point.latitude,
      longitude: point.longitude,
      radiusMeters: made.radiusMeters,
    );
    // Silence after a save reads as a save that failed. `taskOk` is the pack's
    // "a thing worked" tone; there is no fence-specific cue and inventing one
    // would mean nineteen new files per theme for one action.
    cue?.play(CueKind.taskOk);
  }

  /// The fence whose corners are being dragged, or null when this is a new
  /// drawing.
  ///
  /// Reshaping reuses the drawing flow rather than a second editor: the corner
  /// handles, the drag maths and the "at least three corners" rule are the same
  /// interaction, and a second implementation would drift from the first.
  String? _reshapingId;

  /// The name the fence being reshaped already has, so the sheet opens on it
  /// rather than asking for a name it would then throw away.
  String? _reshapingLabel;

  /// Open an existing fence's corners for dragging.
  ///
  /// The fence is loaded into the draft and the camera is moved to it, so the
  /// reader starts on the shape they asked to change rather than on whatever
  /// the map was showing.
  void _beginReshape(String id) {
    final GeofenceController? fences =
        Provider.of<GeofenceController?>(context, listen: false);
    final StoredGeofence? fence = fences?.fences
        .where((StoredGeofence f) => f.id == id)
        .firstOrNull;
    final List<FencePoint>? poly = fence?.polygon;
    if (fence == null || poly == null || poly.length < 3) return;
    final List<LatLng> corners = <LatLng>[
      for (final FencePoint p in poly) LatLng(p.lat, p.lon),
    ];
    setState(() {
      _reshapingId = id;
      _reshapingLabel = fence.label;
      _draft = corners;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _map.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(corners),
          padding: EdgeInsets.all(context.skin.space.step(9) + context.skin.space.rowInset),
        ));
      } catch (_) {
        // The map has not rendered yet; the corners are still loaded and the
        // reader can pan to them.
      }
    });
    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).geofenceReshapeStarted)));
  }

  /// Begin drawing a fence, with the long-press point as its first corner.
  void _startDrawing(LatLng first) {
    setState(() => _draft = <LatLng>[first]);
    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).geofenceDrawStarted)));
  }

  void _cancelDrawing() => setState(() {
        _draft = const <LatLng>[];
        _reshapingId = null;
        _reshapingLabel = null;
      });

  /// Move one corner, from a drag on its handle.
  ///
  /// The delta is a screen distance, so it is converted through the camera
  /// rather than by adding degrees: at a high zoom a finger's width is metres,
  /// and at a low zoom it is kilometres.
  void _moveCorner(int index, Offset delta) {
    if (index < 0 || index >= _draft.length) return;
    final MapCamera cam = _map.camera;
    final math.Point<double> at = cam.latLngToScreenPoint(_draft[index]);
    final LatLng moved = cam.pointToLatLng(
        math.Point<double>(at.x + delta.dx, at.y + delta.dy));
    setState(() {
      final List<LatLng> next = <LatLng>[..._draft];
      next[index] = moved;
      _draft = next;
    });
  }

  /// Finish drawing: name it, then save it.
  Future<void> _finishDrawing() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final GeofenceController? fences =
        Provider.of<GeofenceController?>(context, listen: false);
    if (_draft.length < 3) {
      ScaffoldMessenger.maybeOf(context)
        ?..clearSnackBars()
        ..showSnackBar(
            SnackBar(content: Text(l.geofenceDrawNeedThree)));
      return;
    }
    final List<FencePoint> corners = <FencePoint>[
      for (final LatLng p in _draft) FencePoint(p.latitude, p.longitude),
    ];
    final ({String label, double radiusMeters})? made =
        await showModalBottomSheet<({String label, double radiusMeters})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => GeofenceCreateSheet(
        latitude: corners.first.lat,
        longitude: corners.first.lon,
        polygon: corners,
        // A reshape is an edit of a fence that exists, so the sheet says so and
        // opens on the name it already has. It used to open as a new fence with
        // an empty name field, and the name typed there was discarded.
        editing: _reshapingId != null,
        initialLabel: _reshapingLabel,
      ),
    );
    if (made == null || !mounted || fences == null) return;
    final CueService? cue = context.cue;
    final String? reshaping = _reshapingId;
    bool saved;
    if (reshaping != null) {
      // A reshape keeps the fence's identity and its crossing log: the reader
      // moved a boundary, they did not draw a new fence. The name is the one
      // the sheet opened on, so renaming while reshaping works and an untouched
      // field changes nothing.
      saved = await fences.updatePolygon(
        id: reshaping,
        polygon: corners,
        label: made.label,
      );
    } else {
      await fences.addPolygonFence(
        label: made.label.isEmpty
            ? l.geofenceDefaultName(fences.fences.length + 1)
            : made.label,
        polygon: corners,
      );
      saved = true;
    }
    if (!mounted) return;
    if (saved) {
      cue?.play(CueKind.taskOk);
    } else {
      // The fence was deleted while its corners were open. Saying nothing would
      // read as a save, and the cue would confirm it.
      ScaffoldMessenger.maybeOf(context)
        ?..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.geofenceReshapeGone)));
    }
    setState(() {
      _draft = const <LatLng>[];
      _reshapingId = null;
      _reshapingLabel = null;
    });
  }

  /// One fence, drawn as an area with a boundary rather than as a line.
  ///
  /// The hysteresis band is not drawn as a second ring: a reader needs one
  /// boundary, not a geometry lesson, and the band is already what the engine
  /// enforces. Drawing it was two nearly-identical circles that read as one
  /// blurred line and made the fence look like a rendering fault.
  CircleMarker _fenceCircle(
    StoredGeofence f, {
    required bool inside,
    required Color alert,
  }) {
    final GeofenceRender paint =
        GeofenceRender.of(alert: alert, inside: inside);
    return CircleMarker(
      key: ValueKey<String>('fence-ring-\${f.id}'),
      point: LatLng(f.latitude, f.longitude),
      radius: f.radiusMeters,
      useRadiusInMeter: true,
      color: paint.fill,
      borderColor: paint.ring,
      borderStrokeWidth: paint.ringWidth,
    );
  }

  void _onMapTap(TapPosition _, LatLng point) {
    // While a fence is being drawn, every tap is a corner. The density cell
    // sheet is not reachable in that mode, which is the point: one gesture, one
    // meaning.
    if (_draft.isNotEmpty) {
      // Two corners a few pixels apart are one corner with a shaky finger: the
      // outline draws a spike between them and the count claims a corner nobody
      // meant to place. The test is in screen pixels, because that is what the
      // hand moved.
      final MapCamera cam = _map.camera;
      final math.Point<double> here = cam.latLngToScreenPoint(point);
      final math.Point<double> last = cam.latLngToScreenPoint(_draft.last);
      if ((here.x - last.x).abs() < 10 && (here.y - last.y).abs() < 10) return;
      setState(() => _draft = <LatLng>[..._draft, point]);
      return;
    }
    if (!_showDensity) return;
    for (final HexCell cell in _densityCells) {
      if (hexContains(cell.centre, _hexRadiusMetres, point)) {
        // A cell with nothing in it is not a thing to open. The sheet used to
        // appear for any hexagon under the finger, titled "0 nodes" over an
        // empty list, which reads as a broken tap rather than as an empty
        // cell. A tap on empty ground does nothing, and so does a tap on an
        // empty cell.
        if (cell.points.isEmpty) return;
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
  /// The box the field covers: the viewport, unless no node is in it.
  ///
  /// A stable signature of the nodes the field describes.
  ///
  /// The memo key has to change when a node moves inside the box, and a list of
  /// records does not hash by value. Cheap and ordered: a collision reuses one
  /// field for one build, which the next node frame corrects.
  String _densitySignature(List<DensityPoint> points) {
    int h = 0;
    for (final DensityPoint p in points) {
      h = h * 31 + p.pubKey.hashCode;
      h = h * 31 + p.lat.hashCode;
      h = h * 31 + p.lon.hashCode;
    }
    return '$h';
  }

  /// The box the lattice is built over.
  ///
  /// The viewport, when a node is inside it: the field is then the shape of the
  /// ground the reader is looking at, and it is drawn no further than the basemap
  /// goes.
  ///
  /// The nodes' own box when the viewport holds none of them. Without that
  /// fallback, switching the layer on over a map panned away from every node drew
  /// a lattice of empty cells and nothing else, which reads as a switch that did
  /// nothing; the layer's job is to show the mesh it describes.
  ///
  /// No margin either way. The field used to be built a third of a screen past
  /// the viewport so that a pan landed on cells that already existed, but those
  /// margin cells sit over ground whose tiles have not arrived, and a lattice
  /// over the background colour reads as a rendering fault rather than as a
  /// reading.
  GeoBox _fieldBox(List<DensityPoint> points) {
    final GeoBox? visible = _visibleBox();
    if (visible == null) return _nodeBox(points);
    final bool any = points.any((DensityPoint p) =>
        p.lat >= visible.south &&
        p.lat <= visible.north &&
        p.lon >= visible.west &&
        p.lon <= visible.east);
    return any ? visible : _nodeBox(points);
  }

  /// The field box rounded outward to whole cells of the current radius.
  ///
  /// Done in Mercator metres because that is the projection the lattice uses: a
  /// snap in degrees would depend on the latitude and move cells as the map
  /// travels north.
  GeoBox _snapFieldBox(GeoBox box) {
    final double r = _hexRadiusMetres;
    if (r <= 0) return box;
    final double step = r; // one cell edge, which is a lattice period
    final double x0 = mercatorX(box.west);
    final double x1 = mercatorX(box.east);
    final double y0 = mercatorY(box.south);
    final double y1 = mercatorY(box.north);
    final double sx0 = (x0 / step).floorToDouble() * step;
    final double sx1 = (x1 / step).ceilToDouble() * step;
    final double sy0 = (y0 / step).floorToDouble() * step;
    final double sy1 = (y1 / step).ceilToDouble() * step;
    return GeoBox(
      west: mercatorLon(sx0),
      east: mercatorLon(sx1),
      south: mercatorLat(sy0),
      north: mercatorLat(sy1),
    );
  }

  GeoBox _nodeBox(List<DensityPoint> points) {
    double south = 90, west = 180, north = -90, east = -180;
    for (final DensityPoint p in points) {
      if (p.lat < south) south = p.lat;
      if (p.lat > north) north = p.lat;
      if (p.lon < west) west = p.lon;
      if (p.lon > east) east = p.lon;
    }
    if (south > north) {
      return const GeoBox(south: -0.01, west: -0.01, north: 0.01, east: 0.01);
    }
    const double pad = 0.004;
    return GeoBox(
        south: south - pad, west: west - pad, north: north + pad, east: east + pad);
  }

  /// The part of the ground this map is showing, as a box.
  ///
  /// Computed from the camera's centre, the laid-out size and the zoom's metres
  /// per pixel rather than read from `visibleBounds`: that getter is only valid
  /// once the map has painted, and this build runs first — and when it did answer
  /// it described a rectangle the hexagon lattice only half covered.
  /// The node pins, cached against what they draw.
  ///
  /// The map's build watches the controller, and the controller notifies for
  /// things that do not move a pin: a battery reading, an airtime tick, an
  /// incoming message. Rebuilding a Marker, a glyph, a Semantics label and a
  /// gesture for every visible node on each of those is what made the map feel
  /// slow while traffic arrived. The signature is the drawing's own inputs, so
  /// a notify that changes none of them keeps the list it already had.
  List<Marker> _nodePins(
    BuildContext context,
    MeshcoreController mc,
    List<DiscoveredNode> withLoc,
    AppLocalizations l,
  ) {
    final String sig = <Object?>[
      for (final DiscoveredNode n in withLoc)
        '${n.pubKeyHex}|${n.latitude}|${n.longitude}|'
            '${n.name}|${n.shortId}|'
            '${mc.known.contains(n.pubKeyHex)}|'
            '${mc.favorites.contains(n.pubKeyHex)}',
      context.skin.preset.name,
    ].join(';');
    final List<Marker>? cached = _nodePinCache;
    if (cached != null && _nodePinSignature == sig) return cached;
    final List<Marker> pins = <Marker>[
      for (final DiscoveredNode n in withLoc)
        Marker(
          point: LatLng(n.latitude!, n.longitude!),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Semantics(
            button: true,
            label:
                l.nodeMarkerSemantics(n.name.isEmpty ? n.shortId : n.name),
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
    ];
    _nodePinSignature = sig;
    _nodePinCache = pins;
    return pins;
  }

  /// The last node-pin list and the signature it was built for.
  List<Marker>? _nodePinCache;
  String? _nodePinSignature;

  GeoBox? _visibleBox() {
    try {
      final MapCamera cam = _map.camera;
      final math.Point<double> size = cam.nonRotatedSize;
      if (size.x <= 0 || size.y <= 0) return null;
      final double mpp = StreetMapView.metersPerPixel(
          cam.zoom, cam.center.latitude);
      final double halfLat = size.y / 2 * mpp / kMetresPerDegLatHex;
      final double cosLat =
          math.cos(cam.center.latitude * math.pi / 180).abs().clamp(0.05, 1.0);
      final double halfLon = size.x / 2 * mpp / (kMetresPerDegLatHex * cosLat);
      return GeoBox(
        south: cam.center.latitude - halfLat,
        north: cam.center.latitude + halfLat,
        west: cam.center.longitude - halfLon,
        east: cam.center.longitude + halfLon,
      );
    } catch (_) {
      return null;
    }
  }

  /// The cell size of the layer currently drawn, so the sheet can say what one
  /// square covers. Kept as a field because the sheet outlives the build.
  double _densityCellMetresShown = kDensityCellMetres;

  Future<void> _showDensityCell(
      BuildContext ctx, MeshcoreController mc, HexCell cell) {
    // Belt and braces: the tap path already refuses an empty cell, and this is
    // the one place that would otherwise draw a sheet about nothing.
    if (cell.points.isEmpty) return Future<void>.value();
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

  /// Choose the basemap, from the one place the map's own appearance is set.
  ///
  /// This used to be a second control in the map's column with its own sheet,
  /// so "what the map shows" was two menus: one for the ground and one for
  /// everything drawn on it. The owner asked for one, and the ground is the
  /// first thing a layer panel lists.
  void _applySourceId(String id) {
    setState(() {
      if (id == kOsmVector.id) {
        _rasterOverride = null;
      } else {
        _sourceId = id;
        // Vector is the default, so any raster pick is an override of it.
        _rasterOverride = id;
      }
    });
    _viewState?.rememberSource(_rasterOverride ?? kOsmVector.id);
    BasemapPrefs.save(_rasterOverride);
  }

  /// Drop a basemap choice whose source no longer exists.
  ///
  /// Called one frame after a build noticed the mismatch, so the map is already
  /// drawing the default. Both memories are cleared: the field, and the
  /// preference that would otherwise bring the dead id back on the next launch.
  void _forgetMissingSource() {
    if (!mounted || _rasterOverride == null) return;
    setState(() => _rasterOverride = null);
    _viewState?.rememberSource(kOsmVector.id);
    unawaited(BasemapPrefs.save(null));
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
              // A ring, not a filled dot: the bubble on the map is a 54 dp
              // radial ring, and drawing it as the client's circle made two
              // different marks look identical in the key.
              row(
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: VizPalette.companion, width: 2))),
                  l.mapKeyMessage),
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
      (maps?.layers.any((EventLayer e) => e.visible) ?? false);

  /// Turn the density field on or off, and remember the answer.
  ///
  /// One writer for one preference: the switch, a future gesture and anything
  /// else that changes the field all go through here, so the store cannot be
  /// left holding a value the screen is not showing.
  void _setDensity(bool on) {
    if (_overlays.density == on) return;
    final MapOverlayPrefs next = _overlays.copyWith(density: on);
    setState(() => _overlays = next);
    unawaited(MapOverlayPrefsStore.save(next));
  }

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
    List<MapSource> sources, {
    required String currentSourceId,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext c) {
        final MmSkin skin = c.skin;
        final ColorScheme cs = Theme.of(c).colorScheme;
        return StatefulBuilder(
          builder: (BuildContext c2, StateSetter setSheet) {
          // Read the layers on every rebuild of the sheet. It used to be read
          // once, outside the builder, so the list the switches were drawn from
          // was captured before the tap: `setSheet` rebuilt the sheet with the
          // same stale `visible` flags, and a layer's switch did not move until
          // the sheet was closed and reopened.
          final List<EventLayer> layers =
              maps?.layers ?? const <EventLayer>[];
          return SafeArea(
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
                // The ground first: a layer panel that lists what is drawn on
                // the map and not what the map is drawn on is half a panel.
                // Each source carries its own attribution, so the choice and
                // the credit are read together.
                for (final MapSource src in sources)
                  ListTile(
                    key: ValueKey<String>('map-basemap-${src.id}'),
                    dense: true,
                    leading: Icon(Icons.map_outlined,
                        color: skin.color.fgMuted),
                    title: Text(src.name,
                        style: TextStyle(
                            color: skin.color.fg,
                            fontSize: skin.type.sizeBody)),
                    // The affordance is the radio, in the trailing slot where
                    // this app puts "which one is chosen", and there is no
                    // chevron: this row selects the basemap where it stands, and
                    // an arrow promised a page that never opened.
                    trailing: Icon(
                      src.id == currentSourceId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: src.id == currentSourceId
                          ? skin.color.accent
                          : skin.color.fgMuted,
                    ),
                    subtitle: src.attribution.isEmpty
                        ? null
                        : Text(src.attribution,
                            style: TextStyle(
                                color: skin.color.fgMuted,
                                fontSize: skin.type.sizeSm)),
                    onTap: () {
                      _applySourceId(src.id);
                      setSheet(() {});
                      setState(() {});
                    },
                  ),
                Divider(color: cs.outlineVariant, height: 16),
                SwitchListTile(
                  key: const ValueKey<String>('map-density-toggle'),
                  value: _showDensity,
                  title: Text(l.mapDensityShow,
                      style: TextStyle(
                          color: skin.color.fg, fontSize: skin.type.sizeBody)),
                  subtitle: _showDensity
                      ? Text(
                          l.mapDensityCellSize(densityCellLabel(
                              _densityCellMetresShown, prefs: c.formatPrefs)),
                          style: TextStyle(
                              color: skin.color.fgMuted,
                              fontSize: skin.type.sizeSm))
                      : null,
                  onChanged: (bool v) {
                    _setDensity(v);
                    setSheet(() {});
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
                  trailing: const Icon(Icons.chevron_right),
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
          );
          },
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
    //
    // **Read without listening, and subscribe to a signature instead.**
    // `GeofenceController` ticks once a second and calls `notifyListeners()` on
    // every sample, so watching it here rebuilt this entire view — the hex
    // field, a polygon per cell, the vector layer and its tile provider — once
    // a second, for ever, whether or not a fence existed. That is the
    // out-of-memory and the "isn't responding" report: a full-screen rebuild
    // per second that allocates thousands of objects and never lets the heap
    // settle.
    //
    // The map draws exactly two things from the controller: the fences, and
    // whether the reader is inside each one. So it selects that, and a sample
    // that changes neither rebuilds nothing.
    final GeofenceController? geofences =
        Provider.of<GeofenceController?>(context, listen: false);
    context.select<GeofenceController?, String>((GeofenceController? g) {
      if (g == null) return '';
      final StringBuffer b = StringBuffer();
      for (final StoredGeofence f in g.fences) {
        b
          ..write(f.id)
          ..write(f.label)
          ..write(f.radiusMeters)
          ..write(g.isInside(f.id) ? '1' : '0');
      }
      return b.toString();
    });
    final List<StoredGeofence> fences =
        geofences?.fences ?? const <StoredGeofence>[];
    final List<MapSource> sources = maps?.sources ?? kBuiltInSources;
    // A raster source the reader chose and then deleted.
    //
    // The preference outlives the source, so `_rasterOverride` could name an id
    // that is no longer in the catalogue. The old code then fell through
    // `firstWhere(orElse: tileSource)` to the *raster* OSM source — a basemap
    // that is not even offered any more — and stayed there on every launch,
    // because the stale id was never cleared. A deleted source means "no
    // override", which is the skin's own vector basemap.
    final bool overrideExists = _rasterOverride != null &&
        sources.any((MapSource s) => s.id == _rasterOverride);
    if (_rasterOverride != null && !overrideExists) {
      // After the frame: this is a build, and clearing it here would be a
      // setState during build. The drawing decision below is already correct
      // for this frame, so the cleanup can wait one.
      WidgetsBinding.instance.addPostFrameCallback((_) => _forgetMissingSource());
    }
    final String? rasterId = overrideExists ? _rasterOverride : null;
    final MapSource tileSource = sources.firstWhere(
        (MapSource s) => s.id == _sourceId,
        orElse: () => kOsmStandard);
    // R84 - what is actually drawn: the skin's vector style, or a raster
    // source the user picked over it.
    final MapSource shownSource = rasterId == null
        ? tileSource
        : sources.firstWhere((MapSource s) => s.id == rasterId,
            orElse: () => tileSource);
    // R90 — the vector basemap is available on every skin, not only the one
    // whose shape opted in: the style asset is a neutral dark palette, and
    // gating it made "switch the basemap" a dead control on six presets.
    final bool vectorDrawn = rasterId == null;
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
      fresh: _viewState?.freshView,
    );
    // **Where *we* are is a fact about the radio, not about the camera.**
    //
    // This used to be read off the camera ladder: "the centre came from the phone
    // or the radio, therefore we have a fix". The ladder prefers a recent view
    // and then the remembered one, so in the two commonest cases — the reader
    // panned a moment ago, or the app restored last week's view — the screen said
    // "Your position is not known yet" while the marker, the trail's last point
    // and every reach estimate were drawn from wherever the camera happened to
    // be. That is the banner the owner saw over a radio that had a position, and
    // the stray line is the same bug: the trail was anchored on the camera.
    final OwnLocation? own = mc.ownLocation;
    final bool hasPersonalPosition = own != null;
    final double? selfLat = own?.latitude;
    final double? selfLon = own?.longitude;
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
    final double metresPerPixel = StreetMapView.metersPerPixel(
        _zoom, hasFix ? start.centre.latitude : 39);
    // Fill and number appear and disappear together, or a filled square with no
    // number reads as a large node pin. Hysteresis: appear at the readable size,
    // leave only once comfortably below it, so a pinch on the boundary does not
    // make the whole overlay blink.
    final double cellPx = _densityCellMetresShown / metresPerPixel;
    final bool wantCells = _densityCellsDrawn
        ? cellPx >= kDensityLabelMinPx - 6
        : cellPx >= kDensityLabelMinPx;
    if (wantCells != _densityCellsDrawn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _densityCellsDrawn = wantCells);
      });
    }
    // One size for the hexagons and for the chip that names them: a constant
    // size on the glass, so the ground area is the only thing a zoom changes.
    //
    // The size is in the projection's metres, which is why it comes from the
    // zoom rather than from the ground metres under the camera. A cell size
    // taken from the ground scale carries the latitude, and the latitude is a
    // property of the box: every resize or return from the app switcher moved
    // the lattice by a fraction of a cell. Quantised as well, because a
    // continuous radius changed the memo key on every frame of a pinch, so the
    // lattice was rebuilt and re-anchored under the finger.
    _hexRadiusMetres = hexRadiusForZoomLevel(_zoom);
    if (_fieldZoom.isNaN) _fieldZoom = _zoom;
    // The drawn radius in logical pixels, which is what the cap must be sized
    // from: it is not `kHexRadiusPx` once quantisation has moved it.
    final double drawnRadiusPx = _hexRadiusMetres / hexMetresPerPixel(_zoom);
    // The chip speaks ground metres, so it converts back at the camera's own
    // latitude: the cell is one size on the glass everywhere, which is a
    // different ground size at every latitude.
    _densityCellMetresShown = math.sqrt(3) *
        _hexRadiusMetres *
        groundPerProjectionMetre(start.centre.latitude);
    final List<DensityPoint> densityPoints = _showDensity
        ? <DensityPoint>[
            for (final DiscoveredNode n in mc.nodes)
              if (n.hasLocation)
                (lat: n.latitude!, lon: n.longitude!, pubKey: n.pubKeyHex),
          ]
        : const <DensityPoint>[];
    // The field, not a scatter of boxes: `hexField` returns every hexagon that
    // holds a node, each the same size on the glass, and the shade
    // comes from the count. The lattice is anchored to the visible box's own
    // north-west corner, so panning moves the field with the ground instead of
    // re-anchoring it on the operator's fix (which made the old squares step as
    // they walked).
    // ignore: avoid_print

    // The field is memoised on the inputs that change the picture: the box, the
    // cell size, the nodes in it, and the skin (the fill and the edge come from
    // the palette). Everything else that rebuilds this screen reuses it.
    // A hexagon is an overlay on the basemap, so one is drawn only where the
    // basemap under it exists. The owner's rule: no raw hexagons over black.
    // A cell over a tile that has not arrived is a lattice floating on the
    // background colour, which reads as a rendering fault rather than as a
    // reading of anything; a partly loaded view therefore shows the field over
    // the part that is there and nothing over the part that is not.
    final MapsController? mapsForReady =
        Provider.of<MapsController?>(context, listen: false);
    final int hexZoom = _zoom.round().clamp(0, kOsmVector.maxNativeZoom);
    // The field's box is snapped to the cell lattice before it is used.
    //
    // It used to be the exact viewport, which meant every frame of a pan moved
    // the box, changed the key and rebuilt the whole lattice — a thousand cells
    // and a thousand polygons per frame, for a pan of two pixels. Snapping the
    // edges outward to whole cells keeps the key still while the map slides
    // inside the same cells, so a pan costs nothing until it crosses a cell
    // boundary, and the cells that are drawn do not shift when it does.
    final GeoBox fieldBox = _snapFieldBox(_fieldBox(densityPoints));
    final String hexKey = densityPoints.isEmpty
        ? ''
        : '${fieldBox.south},${fieldBox.west},${fieldBox.north},'
            '${fieldBox.east}|$_hexRadiusMetres|$hexZoom|'
            '${context.skin.preset.name}|${_densitySignature(densityPoints)}';
    if (hexKey != _hexKey) {
      _hexKey = hexKey;
      _hexCache = densityPoints.isEmpty
          ? const <HexCell>[]
          : hexField(
              points: densityPoints,
              box: fieldBox,
              circumradiusMetres: _hexRadiusMetres,
              includeEmpty: true,
              // The bound is the viewport at the radius the cells are actually
              // drawn at: `includeEmpty` emits the lattice in row order, so a
              // bound short of the viewport drops the last rows and the bottom of
              // the map simply has no field.
              // The snapped box is up to one cell wider on each side than the
              // viewport, so the bound carries a row and a column more than the
              // view itself needs. A bound short of the box drops the last rows,
              // and the bottom of the map simply has no field.
              maxCells: hexCellsForViewport(
                    width: MediaQuery.sizeOf(context).width,
                    height: MediaQuery.sizeOf(context).height,
                    radiusPx: drawnRadiusPx,
                  ) +
                  hexCellsForViewport(
                    width: MediaQuery.sizeOf(context).width,
                    height: MediaQuery.sizeOf(context).height,
                    radiusPx: drawnRadiusPx * 0.25,
                  ) +
                  8,
            );
    }

    // A cell is drawn only where its own tile has been drawn, so the field is
    // the shape of the loaded map rather than a lattice over black. Filtered on
    // every build because the readiness set grows while tiles stream in; the
    // polygons are only rebuilt when that set has changed for this zoom.
    final int readyRev = mapsForReady?.tilesReadyRevision ?? 0;
    bool mappable(HexCell c) =>
        mapsForReady == null ||
        mapsForReady.tileReady(kOsmVector, hexZoom,
            lonToTileX(c.centre.longitude, hexZoom),
            latToTileY(c.centre.latitude, hexZoom));
    // Any zoom at all clears the field on the next frame. A pinch that has not
    // crossed a lattice step still changes what the cells mean on the glass, and
    // the previous set was measured for a different one.
    final bool zooming = !_fieldZoom.isNaN &&
        (_zoom - _fieldZoom).abs() > _kFieldZoomSettle;
    if (zooming) _scheduleFieldRebuild();
    // Nothing is drawn while the camera is in motion: see [_cameraMoving].
    final List<HexCell> hexes = (zooming || _cameraMoving)
        ? const <HexCell>[]
        : _hexCache.where(mappable).toList(growable: false);

    // A tile arriving used to rebuild every polygon in the field, and a zoom
    // streams a dozen tiles: the field re-shaped itself a dozen times after the
    // map had already drawn, which is the "slow repopulate" the owner saw. Two
    // things fix it.
    //
    // First, coalescing: a readiness change schedules one rebuild a fraction of a
    // second later, so a burst of tile loads is one pass rather than twelve.
    // Until it lands the previous polygons stay on screen, which is what a reader
    // expects while the map fills in.
    //
    // Second, no rebuild here at all unless the *field* changed (its key) or the
    // preset did: cells that were already built are reused by id, so a readiness
    // change only adds the cells that just became drawable.
    final String fieldKey = '$hexKey|${context.skin.preset.name}';
    if (fieldKey != _hexPolyKey) {
      _hexPolyKey = fieldKey;
      _hexPolyStale = true;
      // The old cells describe a lattice that no longer exists — a different
      // radius, or a different set of cells. Nothing is drawn for them: the new
      // field is built below in this same build, so what appears is the new
      // lattice, and cells whose tile has not arrived appear when it does.
      _hexPolygons = const <Polygon<HexCell>>[];
      _hexPolyTimer?.cancel();
      _hexPolyTimer = null;
    }
    if (readyRev != _hexReadyRev) {
      _hexReadyRev = readyRev;
      _schedulePolygonRebuild();
    }
    // One list per field, or per coalesced tick. Until then the previous list is
    // what is drawn, which is exactly what the map looked like a moment ago.
    if (_hexPolyStale) {
      _hexPolyStale = false;
      final Color accent = VizPalette.of(context.skin).accent;
      final Color edge = cs.onSurface;
      _hexPolygons = <Polygon<HexCell>>[
        for (final HexCell c in hexes)
          Polygon<HexCell>(
            // The cell's own corners, drawn with the projection scale the
            // lattice laid it out with.
            //
            // Clamped to the projection's limit: at a wide zoom a cell is
            // hundreds of kilometres across, so one whose centre is near the
            // pole reaches past 90 degrees and `LatLngBounds` asserts, which took
            // the whole layer down.
            points: <LatLng>[
              for (final LatLng p in c.corners)
                LatLng(p.latitude.clamp(-85.0, 85.0), p.longitude),
            ],
            hitValue: c,
            // The fill carries the count and the ink; the *edge* is what makes
            // it a field. An accent-coloured lattice over a satellite photograph
            // disappeared into the vegetation it was measuring, so the line is
            // the skin's foreground — the one colour guaranteed to differ from
            // the ground it is drawn on — and the fill keeps the accent.
            // One palette lookup for the whole field, not one per cell: the
            // palette is a map of a dozen colours and building it inside the
            // loop made a thousand of them per rebuild.
            color: accent.withValues(alpha: hexAlpha(c.count)),
            borderColor: edge.withValues(alpha: c.count == 0 ? 0.22 : 0.55),
            borderStrokeWidth: c.count == 0 ? 0.7 : 1.1,
          ),
      ];
    }
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

    // Peers inside the viewport, with a margin. flutter_map culls a marker's
    // child when it is off screen, but it is handed the whole list: on a mesh
    // with hundreds of located nodes that is a Marker object, a reach-ring
    // estimate (a haversine and a link-budget calculation) and a hit area for
    // every node in the fabric, every time the map builds. The margin is a fifth
    // of the view, so a pan brings the next cells in before they are needed.
    final GeoBox? cull = _visibleBox();
    // Always cull when there is a box: the box is read from the camera on this
    // build, so it describes the view even mid-gesture.
    final bool cullable = cull != null;
    final double padLat = cull == null ? 0 : (cull.north - cull.south) * 0.2;
    final double padLon = cull == null ? 0 : (cull.east - cull.west) * 0.2;
    final List<DiscoveredNode> source = widget.filteredNodes ?? mc.nodes;
    final List<DiscoveredNode> withLoc = <DiscoveredNode>[
      for (final DiscoveredNode n in source)
        if (n.hasLocation)
          if (!cullable ||
              (n.latitude! >= cull.south - padLat &&
                  n.latitude! <= cull.north + padLat &&
                  n.longitude! >= cull.west - padLon &&
                  n.longitude! <= cull.east + padLon))
            n
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
              color: Colors.transparent,
              borderColor: cs.tertiary.withValues(alpha: .55),
              borderStrokeWidth: 1.0,
            ),
    ];
    // Who has spoken in the last minute, at the place they spoke from. A node
    // with no position is left out rather than pinned to our own fix: a bubble
    // at the wrong place is a worse answer than no bubble.
    final DateTime now = DateTime.now();
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
                //
                // **Map panning is off while a corner is being dragged.** The
                // map's own pan recogniser and the handle's both claim a drag
                // that starts on the handle, and the map won: the reader saw
                // the picture slide and the corner stay put, which is what "you
                // cannot drag a corner" means. The flag is set on pointer-down
                // on a handle and cleared on release, so panning is normal
                // everywhere else and only a drag that starts on a corner is
                // denied to the map.
                flags: StreetMapView.mapFlagsFor(
                  interactive: widget.interactive,
                  draggingCorner: _draggingCorner,
                ),
              ),
              onPositionChanged: (MapCamera cam, bool hasGesture) {
                // A gesture is the user's own move: it suppresses the
                // automatic re-centre for the rest of this visit and it is
                // what the next launch should reopen at.
                if (hasGesture) {
                  _userMoved = true;
                  // Hide the field for the duration of the gesture and bring it
                  // back when the camera stops. One `setState` per gesture, not
                  // one per frame.
                  if (!_cameraMoving) {
                    _cameraMoving = true;
                    _scheduleFieldRebuild();
                  }
                  _userCentre = cam.center;
                  // A zoom step changes the cell size, and the field is built for
                  // one cell size at a time: the old cells describe a lattice that
                  // no longer exists, so they must stop being drawn the moment the
                  // step is crossed rather than at whatever rebuild happens next.
                  //
                  // This used to assign `_zoom` and nothing else, so a pinch moved
                  // the map over a lattice anchored at the previous step and the
                  // cells only caught up when a tile arrival happened to rebuild
                  // the screen. Comparing the quantised radius means one rebuild
                  // per √2 of zoom, not one per frame of the gesture.
                  final double nextRadius = hexRadiusForZoomLevel(cam.zoom);
                  final bool step = nextRadius != _hexRadiusMetres;
                  _zoom = cam.zoom;
                  _hexRadiusMetres = nextRadius;
                  if (step) setState(() {});
                  _rememberView();
                }
                _scheduleWarm(moved: true);
              },
              // A long-press drops a place where the finger is: the map point
              // is what the user aimed at, so the report travels at exact
              // precision rather than the snapped default that belongs to
              // "here" (meshmore-places-spec.md §9).
              onTap: _onMapTap,
              // Long-press is the map's one "make something here" gesture, and
              // it already made a place. A fence is the other thing a reader
              // draws on a map, so the gesture now asks which, rather than
              // taking a second gesture that would fight the pan and the
              // shell's horizontal page drag.
              onLongPress: (TapPosition _, LatLng point) =>
                  _createHere(context, point),
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
              // The equal-area density grid: node counts in kilometre
              // squares, so the map can answer "how many per square km" the
              // way the radar cannot. Under the pins and the reach circles,
              // over the quilt, because a cell is about where nodes are and a
              // ring is about how far they reach.
              if (hexes.isNotEmpty && _densityCellsDrawn)
                PolygonLayer<HexCell>(
                  // A continuous field rather than a scatter of boxes: every
                  // hexagon is the same size on the glass at every zoom, its
                  // ground area is what the chip states, and its shade is its
                  // count. Built once per change of the field, not once per
                  // build: see [_hexPolygons].
                  polygons: _hexPolygons,
                ),
              // R61 — event maps (festival streets, courses, camps).
              const EventLayersOverlay(),
              // R25+1 — range circle for self. Uses our radio-tuple
              // anchor (we know TX power + modulation).
              // R48 — per-peer reach circles. Sized via
              // [estimatedPeerReachMeters] from heard RSSI + known
              // distance instead of a flat radius. Drawn before the
              // marker icons so the pins stay on top.
              // Drawn fences. A polygon is an area with a boundary, so it is a
              // `Polygon` rather than a circle: the shape is the fence, and
              // approximating it with a circle would be a different fence.
              if (fences.any((StoredGeofence f) => f.isPolygon))
                PolygonLayer<StoredGeofence>(
                  polygons: <Polygon<StoredGeofence>>[
                    for (final StoredGeofence f in fences)
                      if (f.isPolygon)
                        Polygon<StoredGeofence>(
                          hitValue: f,
                          points: <LatLng>[
                            for (final FencePoint p in f.polygon!)
                              LatLng(p.lat, p.lon),
                          ],
                          color: GeofenceRender.of(
                            alert: context.skin.color.alert,
                            inside: geofences?.isInside(f.id) ?? false,
                          ).fill,
                          borderColor: GeofenceRender.of(
                            alert: context.skin.color.alert,
                            inside: geofences?.isInside(f.id) ?? false,
                          ).ring,
                          borderStrokeWidth: GeofenceRender.of(
                            alert: context.skin.color.alert,
                            inside: geofences?.isInside(f.id) ?? false,
                          ).ringWidth,
                        ),
                  ],
                ),
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
                        color: Colors.transparent,
                        borderColor: cs.tertiary.withValues(alpha: .75),
                        borderStrokeWidth: 1.4,
                      ),
                  // A fence is a boundary that fires, so it is the loudest
                  // thing on the map rather than the quietest. It was two
                  // 1.6 px rings in the secondary colour with no fill, which
                  // is invisible over a busy basemap: the one element that is
                  // supposed to shout could not be seen at all.
                  //
                  // The fill makes the boundary an area, and the state
                  // (`isInside`) is what changes it: standing inside a fence
                  // is the thing the reader needs to know at a glance, and the
                  // controller already computed it with nobody listening.
                  for (final StoredGeofence f in fences)
                    _fenceCircle(
                      f,
                      inside: geofences?.isInside(f.id) ?? false,
                      alert: context.skin.color.alert,
                    ),
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
              // Fence names above the pins, because a fence is a boundary the
              // reader drew and a pin is a node that arrived: if the two
              // collide, the reader's own label wins.
              if (fences.isNotEmpty)
                MarkerLayer(
                  markers: <Marker>[
                    for (final StoredGeofence f in fences)
                      Marker(
                        key: ValueKey<String>('fence-label-${f.id}'),
                        point: LatLng(f.latitude, f.longitude),
                        width: 140,
                        height: 28,
                        alignment: Alignment.center,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          // The label names one fence, so it opens that fence
                          // rather than the list it shares with nineteen others.
                          onTap: () => context
                              .push('/settings/geofences?id=${f.id}'),
                          child: IgnorePointer(
                            child: Text(
                              f.label,
                              key: ValueKey<String>('fence-name-${f.id}'),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.skin.color.alert,
                                fontSize: context.skin.type.sizeSm,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .5,
                                // A halo in the skin's own ground, not a
                                // black one: on a paper theme a dark halo
                                // behind dark text is a smudge, and the point
                                // of the halo is to separate the label from
                                // whatever the basemap put under it.
                                shadows: <Shadow>[
                                  Shadow(
                                    blurRadius: 3,
                                    color: context.skin.color.base
                                        .withValues(alpha: .85),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              // The fence being drawn: the outline so far, and a handle per
              // corner. The handles are above everything else because they are
              // the only thing a drag can move.
              if (_draft.length >= 2)
                PolygonLayer<LatLng>(
                  polygons: <Polygon<LatLng>>[
                    Polygon<LatLng>(
                      points: _draft,
                      color: context.skin.color.alert.withValues(alpha: .14),
                      borderColor:
                          context.skin.color.alert.withValues(alpha: .9),
                      borderStrokeWidth: 2.4,
                    ),
                  ],
                ),
              if (_draft.isNotEmpty)
                MarkerLayer(
                  markers: <Marker>[
                    for (int i = 0; i < _draft.length; i++)
                      Marker(
                        key: ValueKey<String>('fence-draft-corner-$i'),
                        point: _draft[i],
                        // The dot was 18 dp on a 44 dp target: it could be
                        // tapped but it could not be *seen*, so on a street map
                        // full of labels a reader could not find the corner
                        // their own finger had just placed. The dot is the size
                        // of a fingertip's centre now and carries its order, so
                        // the outline reads as a sequence rather than a scatter.
                        width: 48,
                        height: 48,
                        // A drag handle is a control, so it says what it is: a
                        // screen reader that finds an unlabelled gesture area
                        // has found something it cannot describe.
                        child: Semantics(
                          label: l.geofenceCornerHandle(i + 1),
                          // The Listener is what makes the drag *work*: it takes
                          // the raw pointer, and while a finger is down on a
                          // handle the map's own pan is switched off
                          // (`interactionOptions`), so the two recognisers never
                          // compete for the same gesture.
                          child: Listener(
                            onPointerDown: (_) {
                              if (!_draggingCorner) {
                                setState(() => _draggingCorner = true);
                              }
                            },
                            onPointerUp: (_) {
                              if (_draggingCorner) {
                                setState(() => _draggingCorner = false);
                              }
                            },
                            onPointerCancel: (_) {
                              if (_draggingCorner) {
                                setState(() => _draggingCorner = false);
                              }
                            },
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanUpdate: (DragUpdateDetails d) =>
                                  _moveCorner(i, d.delta),
                              child: Center(
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: context.skin.color.base,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: context.skin.color.alert,
                                        width: 2.5),
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      color: context.skin.color.alert,
                                      fontSize: context.skin.type.size(11),
                                      fontWeight: FontWeight.w700,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              MarkerLayer(
                markers: <Marker>[
                  ..._nodePins(context, mc, withLoc, l),
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
                  // Self marker last so it sits on top. Drawn at the fix, not at
                  // the camera: `start.centre` is the ladder's answer for where
                  // to look, which is a remembered view or the last place the
                  // reader panned to. Putting the marker there said "you are
                  // here" about the centre of the screen, wherever the reader had
                  // scrolled, while every distance, the trail and the fences were
                  // computed from the real fix.
                  if (hasFix)
                    Marker(
                      key: const ValueKey<String>('map-self-marker'),
                      point: LatLng(selfLat!, selfLon!),
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      // Only this subtree rebuilds on a compass sample: the
                      // marker's arrow, not the map, the pins or the overlays.
                      child: ValueListenableBuilder<double?>(
                        valueListenable: _heading,
                        builder: (BuildContext _, double? heading, Widget? __) =>
                            _SelfGlyph(
                          colour: cs.primary,
                          // The ring is a skin token, not white: on the light
                          // skin a white ring around a pale dot disappears.
                          ring: context.skin.color.fg,
                          headingDeg: heading,
                        ),
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
        // The inset is read here, not written: the map is the one screen that
        // does not sit inside `MmScaffold` (it is full-bleed and wants no
        // ground colour), so nothing else lifts its bottom column clear of the
        // navigation area. The attribution is a licence obligation and it was
        // being cut in half by the gesture handle.
        // While a fence is being drawn, the map is in one mode and says so:
        // how many corners there are, how to add one, and the two ways out.
        if (_draft.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + 72,
            child: Center(
              child: Container(
                key: const ValueKey<String>('fence-draw-bar'),
                margin: EdgeInsets.symmetric(horizontal: context.skin.space.step(4)),
                padding: EdgeInsets.symmetric(
                    horizontal: context.skin.space.step(3),
                    vertical: context.skin.space.step(2)),
                decoration: BoxDecoration(
                  color: context.skin.color.surface,
                  borderRadius: mmRadius(context, 6),
                  border: Border.all(color: context.skin.color.alert),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l.geofenceCorners(_draft.length),
                      key: const ValueKey<String>('fence-draw-count'),
                      style: TextStyle(
                          color: context.skin.color.fg,
                          fontSize: context.skin.type.sizeBody,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      l.geofenceDrawHint,
                      style: TextStyle(
                          color: context.skin.color.fgMuted,
                          fontSize: context.skin.type.sizeSm),
                    ),
                    SizedBox(height: context.skin.space.step(2)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        MmAction(
                          key: const ValueKey<String>('fence-draw-cancel'),
                          label: l.geofenceDrawCancel,
                          dense: true,
                          onPressed: _cancelDrawing,
                        ),
                        SizedBox(width: context.skin.space.step(2)),
                        MmAction(
                          key: const ValueKey<String>('fence-draw-done'),
                          label: l.geofenceDrawDone,
                          dense: true,
                          onPressed: _finishDrawing,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.paddingOf(context).bottom,
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
              // The wedge on the self marker is the one heading in the app, and
              // it comes from the phone's magnetometer, not from the radio: a
              // MeshCore node reports a position, never a facing. It used to
              // carry a legend line ("The arrow is this phone's compass"), which
              // the owner removed: a compass needle needs no caption, and the line
              // was a permanent piece of text under a map that is already busy.

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
            // 92 dp above the navigation area, not above the glass: the chip
            // floats over the map, which is full-bleed, so the inset is added
            // rather than inherited.
            bottom: 92 + MediaQuery.paddingOf(context).bottom,
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
                  l.mapDensityCellSize(densityCellLabel(
                      _densityCellMetresShown,
                      prefs: context.formatPrefs)),
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
                  // Layers, not a sparkle: this control is the map's layer
                  // panel, and the icon every map app uses for one is a stack.
                  icon: Icon(_anyOverlayShown(maps)
                      ? Icons.layers
                      : Icons.layers_outlined),
                  onPressed: () => _showOverlays(context, l, maps, sources,
                      currentSourceId:
                          vectorDrawn ? kOsmVector.id : shownSource.id),
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
                padding: EdgeInsets.symmetric(
                    horizontal: context.skin.space.rowGap,
                    vertical: context.skin.space.step(3)),
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
