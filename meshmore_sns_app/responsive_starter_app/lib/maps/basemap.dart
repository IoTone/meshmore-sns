// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'event_layer.dart';
import 'map_source.dart';
import 'maps_controller.dart';

/// R61 — tiles come from [MapsController]: disk first, network second.
class CachedTileProvider extends TileProvider {
  CachedTileProvider(this.maps, this.source);
  final MapsController maps;
  final MapSource source;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MapTileImage(maps, source, coordinates.z, coordinates.x, coordinates.y);
}

@immutable
class MapTileImage extends ImageProvider<MapTileImage> {
  const MapTileImage(this.maps, this.source, this.z, this.x, this.y);
  final MapsController maps;
  final MapSource source;
  final int z;
  final int x;
  final int y;

  @override
  Future<MapTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<MapTileImage>(this);

  @override
  ImageStreamCompleter loadImage(
          MapTileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final Uint8List? bytes = await maps.loadTile(source, z, x, y);
    if (bytes == null) {
      // Offline and never seen: flutter_map leaves the cell blank and
      // the image cache forgets the failure, so it is tried again.
      throw StateError('tile ${source.id}/$z/$x/$y unavailable');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is MapTileImage &&
      other.source.id == source.id &&
      other.z == z &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(source.id, z, x, y);
}

/// The basemap layer for [source]. With a [MapsController] in the tree
/// it is cached; without one (tests, previews) it is plain network.
///
/// [dark] (R70) draws each tile through [mmDarkTileFilter].
TileLayer basemapLayer(BuildContext context, MapSource source,
    {bool dark = false}) {
  final MapsController? maps =
      Provider.of<MapsController?>(context, listen: false);
  return TileLayer(
    urlTemplate: source.urlTemplate,
    subdomains: source.subdomains,
    maxNativeZoom: source.maxNativeZoom,
    userAgentPackageName: 'com.iotone.meshmore_sns_app',
    tileProvider: maps == null ? null : CachedTileProvider(maps, source),
    tileBuilder: dark ? mmDarkTileBuilder : null,
  );
}

/// R70 — a colour-matrix filter that turns a light raster basemap dark
/// without washing it out: it **inverts luminance** (so land, water and
/// road casings go dark and labels/road fills go light, keeping the
/// contrast that makes text readable) and then **desaturates** to
/// [saturation] so the inverted hues (OSM's blue water becomes orange)
/// do not read as colour. Unlike a semi-transparent scrim, contrast is
/// preserved, not reduced. Trade-off: it is a global per-tile transform,
/// so coloured features (a red road, green park) lose their hue
/// distinction; shape and label contrast stay.
ColorFilter mmDarkTileFilter({double saturation = 0.15}) =>
    ColorFilter.matrix(mmDarkTileMatrix(saturation: saturation));

/// The 4x5 matrix behind [mmDarkTileFilter] (exposed so it can be tested).
List<double> mmDarkTileMatrix({double saturation = 0.15}) {
  // out = s*inv + (1-s)*lum(inv),  inv = 255 - in
  const double r = 0.2126, g = 0.7152, b = 0.0722;
  final double s = saturation;
  final double k = 1 - s;
  List<double> row(int ch) {
    final List<double> w = <double>[r * k, g * k, b * k];
    w[ch] += s;
    // out = -(w . in) + 255 * (sum of w)
    final double sum = w[0] + w[1] + w[2];
    return <double>[-w[0], -w[1], -w[2], 0, 255 * sum];
  }

  return <double>[
    ...row(0),
    ...row(1),
    ...row(2),
    0,
    0,
    0,
    1,
    0,
  ];
}

/// [TileLayer.tileBuilder] applying [mmDarkTileFilter].
Widget mmDarkTileBuilder(BuildContext context, Widget tile, TileImage image) =>
    ColorFiltered(colorFilter: mmDarkTileFilter(), child: tile);

/// Credit line for the visible basemap — OSM and CC-BY-SA require it.
class MapAttribution extends StatelessWidget {
  const MapAttribution(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        color: cs.surface.withValues(alpha: .75),
        child: Text(text,
            style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
      ),
    );
  }
}

/// Every visible event layer, drawn over the basemap.
class EventLayersOverlay extends StatelessWidget {
  const EventLayersOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final MapsController? maps = Provider.of<MapsController?>(context);
    if (maps == null) return const SizedBox.shrink();
    final List<EventLayer> shown =
        maps.layers.where((EventLayer l) => l.visible).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Stack(children: <Widget>[
      for (final EventLayer l in shown)
        _OneEventLayer(
            key: ValueKey<String>('${l.id}@${l.updatedMs}'),
            maps: maps,
            layer: l),
    ]);
  }
}

Widget _dot(Color c, String? label) {
  final Widget dot = DecoratedBox(
    decoration: BoxDecoration(
      color: c,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.black54),
    ),
  );
  return label == null ? dot : Tooltip(message: label, child: dot);
}

class _OneEventLayer extends StatefulWidget {
  const _OneEventLayer({super.key, required this.maps, required this.layer});
  final MapsController maps;
  final EventLayer layer;

  @override
  State<_OneEventLayer> createState() => _OneEventLayerState();
}

class _OneEventLayerState extends State<_OneEventLayer> {
  late final Future<GeoShapes?> _shapes = widget.maps.shapesFor(widget.layer);

  @override
  Widget build(BuildContext context) {
    final Color c = Theme.of(context).colorScheme.tertiary;
    return FutureBuilder<GeoShapes?>(
      future: _shapes,
      builder: (BuildContext context, AsyncSnapshot<GeoShapes?> snap) {
        final GeoShapes? s = snap.data;
        if (s == null) return const SizedBox.shrink();
        return Stack(children: <Widget>[
          if (s.polygons.isNotEmpty)
            PolygonLayer(polygons: <Polygon>[
              for (final List<LatLng> r in s.polygons)
                Polygon(
                  points: r,
                  color: c.withValues(alpha: .10),
                  borderColor: c.withValues(alpha: .7),
                  borderStrokeWidth: 1,
                ),
            ]),
          if (s.lines.isNotEmpty)
            PolylineLayer(polylines: <Polyline>[
              for (final List<LatLng> l in s.lines)
                Polyline(points: l, color: c, strokeWidth: 1.5),
            ]),
          if (s.points.isNotEmpty)
            MarkerLayer(markers: <Marker>[
              for (final GeoPoint p in s.points.take(2000))
                Marker(
                  point: p.at,
                  width: 10,
                  height: 10,
                  child: _dot(c, p.label),
                ),
            ]),
        ]);
      },
    );
  }
}
