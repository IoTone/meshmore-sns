// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
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
import '../maps/basemap_prefs.dart';
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

  /// R70 — the control column's geometry, shared with the Map tab's
  /// edge band so the band's inset is derived, not a magic number: five
  /// controls (zoom in, zoom out, recentre, basemap picker, tile
  /// toggle), each 48 dp, `controlsInset` from the top-right corner.
  static const double controlCell = 48;
  static const int controlCount = 5;
  static const double controlsInset = 12;
  static const double controlsBottom =
      controlsInset + controlCount * controlCell;

  /// Bottom edge of the column when the host adds [extras] controls, so the
  /// Map tab's edge band starts below the last button rather than under it.
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

  void _scheduleWarm() {
    _warm?.cancel();
    _warm = Timer(const Duration(milliseconds: 500), _warmAround);
  }

  /// True when the view on screen is outside every finished region pack
  /// while the map has no connection: the one case where "no tiles" is a
  /// fact to say out loud rather than a tile that has not arrived.
  bool _outsidePacks = false;

  Future<void> _warmAround() async {
    if (!mounted || !_vectorSkin) return;
    final MapsController? maps =
        Provider.of<MapsController?>(context, listen: false);
    if (maps == null || !maps.online || !maps.viewIdle) return;
    final MapCamera cam = _map.camera;
    final int z = cam.zoom.round().clamp(0, kOsmVector.maxNativeZoom);
    final LatLngBounds b = cam.visibleBounds;
    final TileRange r = tileRange(
        GeoBox(south: b.south, west: b.west, north: b.north, east: b.east), z);
    _noteCoverage(maps, GeoBox(
        south: b.south, west: b.west, north: b.north, east: b.east), z);
    final List<(int, int, int)> ring = <(int, int, int)>[];
    for (int x = r.minX - 1; x <= r.maxX + 1 && ring.length < 24; x++) {
      for (int y = r.minY - 1; y <= r.maxY + 1 && ring.length < 24; y++) {
        ring.add((z, x, y));
      }
    }
    await maps.prefetch(kOsmVector, ring);
    // R114 — the parents of what is on screen, so a zoom out draws a coarser
    // picture straight away instead of waiting for the finer tiles to fail.
    await maps.prefetchParents(kOsmVector, ring);
  }

  /// The self marker's bearing comes from the **phone's magnetometer**
  /// (flutter_compass), never from the radio: a MeshCore GPS reports a
  /// position, not a heading. A peer marker is therefore never rotated, and
  /// this stays null on a phone with no compass, which drops the wedge.
  void _noteCoverage(MapsController maps, GeoBox box, int z) {
    final bool outside = maps.archives.isNotEmpty && !maps.archiveCovers(box, z);
    if (outside == _outsidePacks) return;
    if (!mounted) return;
    setState(() => _outsidePacks = outside);
  }

  double? _headingDeg;
  StreamSubscription<CompassEvent>? _compassSub;

  /// A peer's reach estimate in metres, from its signal and role.
  double _reachMeters(DiscoveredNode n, MeshcoreController mc, SelfInfo? si) =>
      estimatedPeerReachMeters(
        rssiDbm: n.rssi?.toDouble(),
        distanceMeters: mc.distanceMetersTo(n.latitude!, n.longitude!),
        peerType: n.type,
        ourSpreadingFactor: si?.spreadingFactor ?? 7,
        ourBandwidthKhz: si?.bandwidthKhz ?? 125.0,
        ourTxPowerDbm: si?.txPowerDbm ?? 14,
      );

  /// R25+3 / R61 — basemap source. Starts on OSM; the picker offers
  /// every source in the maps catalogue (built-ins + custom servers).
  /// Session-scoped like the grid's view mode.
  static String _sourceId = kOsmStandard.id;

  /// R84 - a raster basemap chosen from the picker while the skin renders
  /// vector by default. Null means "the skin's own basemap". Without this
  /// the Studio picker was a dead control: it changed [_sourceId] and the
  /// vector layer ignored it, so choosing USGS Imagery did nothing.
  String? _rasterOverride;

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
    _compassSub = FlutterCompass.events?.listen((CompassEvent e) {
      final double? h = e.heading;
      if (h == null || !mounted) return;
      if (_headingDeg != null && (h - _headingDeg!).abs() < 1.0) return;
      setState(() => _headingDeg = h);
    });
  }

  @override
  void dispose() {
    _warm?.cancel();
    _saveView?.cancel();
    _compassSub?.cancel();
    super.dispose();
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
        if (StreetMapView.reachRingReadable(
            _reachMeters(n, mc, si), viewportMeters))
          CircleMarker(
            point: LatLng(n.latitude!, n.longitude!),
            radius: _reachMeters(n, mc, si),
            useRadiusInMeter: true,
            color: const Color(0x00000000),
            borderColor: cs.tertiary.withValues(alpha: .55),
            borderStrokeWidth: 1.0,
          ),
    ];
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
                _scheduleWarm();
              },
              // A long-press drops a place where the finger is: the map point
              // is what the user aimed at, so the report travels at exact
              // precision rather than the snapped default that belongs to
              // "here" (meshmore-places-spec.md §9).
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
                            companion: cs.tertiary,
                            repeater: cs.primary,
                            known: mc.known.contains(n.pubKeyHex),
                            favourite: mc.favorites.contains(n.pubKeyHex),
                          ),
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
              // Reporting a place is a labelled control, not only a
              // long-press: a hidden gesture was the only way in and the
              // empty state had to teach it in a sentence (UX audit C7). The
              // long-press stays as the fast path, and the point reported is
              // the one at the middle of the screen.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: cs.surface.withValues(alpha: .92),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: mmRadius(context, 6),
                      side: BorderSide(color: cs.outline.withValues(alpha: .4)),
                    ),
                    child: InkWell(
                      key: const ValueKey<String>('map-report-place'),
                      onTap: () => _createPlace(context, _map.camera.center),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.add_location_alt_outlined,
                                size: context.skin.type.sizeLg,
                                color: cs.onSurface),
                            Text(
                              l.mapReportPlace,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: context.skin.type.sizeMicro),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
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
                  Text(l.globePaused,
                      style: TextStyle(
                          color: cs.onTertiaryContainer,
                          fontSize: context.skin.type.sizeMicro,
                          letterSpacing: 1)),
                ],
              ),
            ),
          ),
        // Zoom +/- + re-centre. Stacked vertically, top-right.
        Positioned(
          right: StreetMapView.controlsInset,
          top: StreetMapView.controlsInset,
          child: Material(
            key: const ValueKey<String>('map-controls'),
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
                PopupMenuButton<String>(
                  key: const ValueKey<String>('map-basemap-picker'),
                  tooltip: l.mapsSourcePick,
                  iconSize: 18,
                  constraints: const BoxConstraints(
                      minWidth: StreetMapView.controlCell,
                      minHeight: StreetMapView.controlCell),
                  icon: const Icon(Icons.map),
                  initialValue: vectorDrawn ? kOsmVector.id : shownSource.id,
                  onSelected: (String id) {
                    setState(() {
                      if (id == kOsmVector.id) {
                        _rasterOverride = null;
                      } else {
                        _sourceId = id;
                        // Vector is the default, so any raster pick is an
                        // override of it.
                        _rasterOverride = id;
                      }
                    });
                    BasemapPrefs.save(_rasterOverride);
                  },
                  itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
                    for (final MapSource s in sources)
                      PopupMenuItem<String>(
                        value: s.id,
                        child: Text(s.name),
                      ),
                  ],
                ),
                // R90 — event maps belong on the map. They used to be a
                // switch buried in Settings > Offline maps, which is where
                // you manage a layer, not where you look at one. Visibility
                // toggles here; add / refresh / delete stays in Settings.
                Builder(
                  builder: (BuildContext ctx) {
                    final MapsController? maps =
                        Provider.of<MapsController?>(ctx);
                    final List<EventLayer> layers =
                        maps?.layers ?? const <EventLayer>[];
                    final bool anyShown =
                        layers.any((EventLayer e) => e.visible);
                    return PopupMenuButton<String>(
                      key: const ValueKey<String>('map-layers-menu'),
                      tooltip: l.mapsLayers,
                      iconSize: 18,
                      constraints: const BoxConstraints(
                          minWidth: StreetMapView.controlCell,
                          minHeight: StreetMapView.controlCell),
                      icon:
                          Icon(anyShown ? Icons.layers : Icons.layers_outlined),
                      itemBuilder: (BuildContext _) {
                        if (layers.isEmpty) {
                          return <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              enabled: false,
                              child: Text(l.mapsNoLayersShort),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem<String>(
                              value: '__manage',
                              child: Text(l.mapsManageLayers),
                            ),
                          ];
                        }
                        return <PopupMenuEntry<String>>[
                          for (final EventLayer e in layers)
                            CheckedPopupMenuItem<String>(
                              value: e.id,
                              checked: e.visible,
                              child: Row(
                                children: <Widget>[
                                  Flexible(
                                    child: Text(e.name,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  // A layer that is on but has nothing to
                                  // draw says so, instead of looking like an
                                  // empty map.
                                  if (e.visible &&
                                      !(maps?.isLayerLoaded(e) ?? false))
                                    const Padding(
                                      padding: EdgeInsets.only(left: 6),
                                      child:
                                          Icon(Icons.error_outline, size: 14),
                                    ),
                                ],
                              ),
                            ),
                          const PopupMenuDivider(),
                          PopupMenuItem<String>(
                            value: '__manage',
                            child: Text(l.mapsManageLayers),
                          ),
                        ];
                      },
                      onSelected: (String id) {
                        if (id == '__manage') {
                          ctx.push('/settings/maps');
                          return;
                        }
                        for (final EventLayer e in layers) {
                          if (e.id == id) {
                            maps?.setLayerVisible(e, !e.visible);
                            break;
                          }
                        }
                      },
                    );
                  },
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
            right: 12,
            top: 12,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: .85),
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
