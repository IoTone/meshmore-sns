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
    this.browseWithoutFix = false,
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
  final bool browseWithoutFix;

  /// Controls the host page contributes to this column, rendered under the
  /// five built-in ones. Every map tool lives in one column on one edge, so
  /// a host never has to place a second column on the other side (the Map
  /// tab passed its offline-maps and places buttons that way, and they were
  /// the buttons a thumb never found).
  final List<Widget> controlExtras;

  /// R69 — the honest default centre when there is no fix: a world view
  /// (the middle of the Atlantic/Africa band), not a guess at the user's
  /// region. [browseZoom] shows the whole globe's land masses.
  static const LatLng browseCentre = LatLng(20.0, 0.0);
  static const double browseZoom = 2.0;

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

  /// True when a ring of [radiusMeters] is small enough to read on a screen
  /// [viewportMeters] tall. Half the viewport is the cut: past it the circle
  /// is an arc through the middle of the map with its centre off screen, which
  /// is the "stray line" the map used to show instead of a range.
  @visibleForTesting
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
  static const double _zoomMin = 6.0;

  /// R83 — the Studio basemap is Shortbread, whose tiles stop at z14, so
  /// every level past it is an upscale. Past z17 the upscale is 8x linear
  /// and the map stops carrying information; the raster presets keep the
  /// deeper native range.
  double get _zoomMax => _vectorSkin ? 17.0 : 18.5;
  static const double _zoomStep = 1.0;
  late final MapController _map = MapController();
  double _zoom = 14.0; // metro default; pinned to self on first build
  bool _centered = false;

  /// R69 — true while this view is showing the no-fix world view, so the
  /// first real fix can reset the zoom from world to metro.
  bool _browsing = false;

  /// R83 - warms the ring around a settled viewport so the next pan paints
  /// from storage. Debounced, and only when nothing else is fetching.
  Timer? _warm;

  /// Read during build; `context.skin` watches a provider and must not be
  /// touched from a timer or an async callback.
  bool _vectorSkin = false;

  void _scheduleWarm() {
    _warm?.cancel();
    _warm = Timer(const Duration(milliseconds: 500), _warmAround);
  }

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
    if (widget.browseWithoutFix) {
      // The context-free read of the fix happens in build; here we only
      // pre-seed the world zoom so the first frame is not zoom 14 over
      // (0,0) while the controller is still resolving.
      _zoom = StreetMapView.browseZoom;
      _browsing = true;
    }
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

  /// R69 — the world view needs a lower floor than the metro default.
  double get _minZoom => _browsing ? StreetMapView.browseZoom : _zoomMin;

  void _recenterOnSelf(double lat, double lon) {
    _map.move(LatLng(lat, lon), _zoom);
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
    final String? packZoomNotice = maps == null ||
            maps.online ||
            packSpan == null ||
            (zoomLevel >= packSpan.minZoom && zoomLevel <= packSpan.maxZoom)
        ? null
        : l.mapPackZoomOutside(packSpan.minZoom, packSpan.maxZoom);

    final double? selfLat = mc.ownLocation?.latitude;
    final double? selfLon = mc.ownLocation?.longitude;
    final bool hasFix = selfLat != null && selfLon != null;
    if (!hasFix && !widget.browseWithoutFix) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.equalGridAwaitingFix,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    // R69 — a fix arrived after browsing: leave the world view.
    if (hasFix && _browsing) {
      _browsing = false;
      _zoom = 14.0;
    }
    // First build after the controller has a location: centre on self.
    if (hasFix && !_centered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _map.move(LatLng(selfLat, selfLon), _zoom);
        } catch (_) {/* map not laid out yet */}
        _centered = true;
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
              initialCenter: hasFix
                  ? LatLng(selfLat, selfLon)
                  : StreetMapView.browseCentre,
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
              onPositionChanged: (MapCamera cam, bool hasGesture) =>
                  _scheduleWarm(),
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
                        point: LatLng(selfLat, selfLon),
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
                  // Self marker last so it sits on top.
                  if (hasFix)
                    Marker(
                      point: LatLng(selfLat, selfLon),
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
              // R114 — a pack has a zoom range. Outside it, offline, the map is
              // showing coarser tiles on purpose, and saying so once is the
              // difference between "working as designed" and "broken".
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
              if (!hasFix)
                Container(
                  key: const ValueKey<String>('map-no-fix-banner'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(top: BorderSide(color: cs.outlineVariant)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.location_disabled,
                          size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.mapNoFixBanner,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
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
                          fontSize: 10,
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
                  tooltip: l.equalGridZoomIn,
                  iconSize: 18,
                  constraints: const BoxConstraints(
                      minWidth: StreetMapView.controlCell,
                      minHeight: StreetMapView.controlCell),
                  icon: const Icon(Icons.add),
                  onPressed: _zoom < _zoomMax ? _zoomIn : null,
                ),
                IconButton(
                  tooltip: l.equalGridZoomOut,
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
                  onPressed:
                      hasFix ? () => _recenterOnSelf(selfLat, selfLon) : null,
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
