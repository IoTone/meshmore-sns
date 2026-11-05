// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

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
  }

  double? _headingDeg;
  StreamSubscription<CompassEvent>? _compassSub;

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

    final List<DiscoveredNode> source =
        widget.filteredNodes ?? mc.nodes;
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
              backgroundColor: vectorDrawn
                  ? kVectorBasemapBackground
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
                  for (final DiscoveredNode n in withLoc)
                    CircleMarker(
                      point: LatLng(n.latitude!, n.longitude!),
                      radius: estimatedPeerReachMeters(
                        rssiDbm: n.rssi?.toDouble(),
                        distanceMeters: mc.distanceMetersTo(
                            n.latitude!, n.longitude!),
                        peerType: n.type,
                        ourSpreadingFactor: si?.spreadingFactor ?? 7,
                        ourBandwidthKhz: si?.bandwidthKhz ?? 125.0,
                        ourTxPowerDbm: si?.txPowerDbm ?? 14,
                      ),
                      useRadiusInMeter: true,
                      color: const Color(0x00000000),
                      borderColor: cs.tertiary.withValues(alpha: .55),
                      borderStrokeWidth: 1.0,
                    ),
                ],
              ),
              // R25+1 — own-movement trail, oldest faded → newest
              // solid. Drawn as a single Polyline; per-segment alpha
              // would need multiple polylines so we go with a
              // single mid-alpha line for now.
              if (mc.ownTrail.length >= 2)
                PolylineLayer(
                  polylines: <Polyline>[
                    Polyline(
                      points: <LatLng>[
                        for (final ({
                          double latitude,
                          double longitude,
                          int unixSec
                        }) p in mc.ownTrail)
                          LatLng(p.latitude, p.longitude),
                      ],
                      strokeWidth: 3.0,
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
              // The credit line follows what is actually drawn. R82 draws
              // OSM's own vector service, so one credit covers the tiles and
              // the data; a raster source keeps its own credit.
              MapAttribution(vectorDrawn
                  ? kOsmVector.attribution
                  : shownSource.attribution),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer.withValues(alpha: .85),
                borderRadius: BorderRadius.circular(kRadiusMd),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.pause,
                      size: 12, color: cs.onTertiaryContainer),
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
              side: BorderSide(
                  color: cs.outline.withValues(alpha: .4)),
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
                  onPressed: hasFix
                      ? () => _recenterOnSelf(selfLat, selfLon)
                      : null,
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
                    final bool anyShown = layers.any((EventLayer e) => e.visible);
                    return PopupMenuButton<String>(
                      key: const ValueKey<String>('map-layers-menu'),
                      tooltip: l.mapsLayers,
                      iconSize: 18,
                      constraints: const BoxConstraints(
                          minWidth: StreetMapView.controlCell,
                          minHeight: StreetMapView.controlCell),
                      icon: Icon(
                          anyShown ? Icons.layers : Icons.layers_outlined),
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
                                      child: Icon(Icons.error_outline,
                                          size: 14),
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
    required this.companion,
    required this.repeater,
    required this.known,
    required this.favourite,
  });
  final DiscoveredNode node;
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
          // Triangle.
          CustomPaint(
            size: const Size(16, 16),
            painter: _TrianglePainter(color: base),
          )
        else
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: base,
              border: Border.all(color: Colors.white, width: 1.0),
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

class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = color;
    final Paint stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final Path p = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(p, fill);
    canvas.drawPath(p, stroke);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter old) =>
      color != old.color;
}

class _SelfGlyph extends StatelessWidget {
  const _SelfGlyph({required this.colour, required this.headingDeg});
  final Color colour;
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
            border: Border.all(color: Colors.white, width: 1.5),
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
  bool shouldRepaint(covariant _HeadingWedgePainter old) =>
      color != old.color;
}
