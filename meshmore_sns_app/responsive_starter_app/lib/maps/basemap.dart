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
import 'tile_ancestor.dart';

/// The edge of one slippy tile in pixels. flutter_map's `TileLayer` default,
/// and the size a cropped ancestor is emitted at so it lands in the cell
/// without a second scale.
const int kTilePixelSize = 256;

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
    if (bytes != null) {
      return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    }
    // R114 — nothing at this zoom yet: draw the nearest coarser tile that is
    // on disk, cropped to the slice this cell owns. The alternative is the
    // black hole the owner reported when a zoom out outruns the network.
    final TileAncestor? ancestor = await maps.ancestorTile(source, z, x, y);
    if (ancestor == null) {
      // Offline and never seen, at any zoom: flutter_map leaves the cell
      // blank and the image cache forgets the failure, so it is tried again.
      throw StateError('tile ${source.id}/$z/$x/$y unavailable');
    }
    return _codecFromAncestor(ancestor, decode);
  }

  /// Decode the ancestor once, take this cell's slice out of it, and hand the
  /// slice back as a 256 px tile so it fills the cell exactly.
  ///
  /// Raw RGBA in, raw RGBA out: no image is re-encoded, and the ancestor's
  /// own pixels are what the user sees, only coarser.
  Future<ui.Codec> _codecFromAncestor(
      TileAncestor ancestor, ImageDecoderCallback decode) async {
    final TileAncestorCoord a = ancestor.coord;
    final ui.Codec codec =
        await decode(await ui.ImmutableBuffer.fromUint8List(ancestor.bytes));
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image whole = frame.image;
    try {
      final ({double left, double top, double width, double height}) slice =
          cropRectInAncestor(x, y, a.levelsUp, whole.width.toDouble());
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final double side = kTilePixelSize.toDouble();
      canvas.drawImageRect(
        whole,
        Rect.fromLTWH(slice.left, slice.top, slice.width, slice.height),
        Rect.fromLTWH(0, 0, side, side),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final ui.Image cropped =
          await recorder.endRecording().toImage(kTilePixelSize, kTilePixelSize);
      final ByteData? raw =
          await cropped.toByteData(format: ui.ImageByteFormat.rawRgba);
      cropped.dispose();
      if (raw == null) {
        throw StateError('tile ${source.id}/$z/$x/$y unreadable');
      }
      final ui.ImageDescriptor desc = ui.ImageDescriptor.raw(
        await ui.ImmutableBuffer.fromUint8List(raw.buffer.asUint8List()),
        width: kTilePixelSize,
        height: kTilePixelSize,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      return await desc.instantiateCodec();
    } finally {
      whole.dispose();
    }
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
/// [dim] draws each tile through [mmDimTileFilter] (R79).
TileLayer basemapLayer(BuildContext context, MapSource source,
    {bool dim = false}) {
  final MapsController? maps =
      Provider.of<MapsController?>(context, listen: false);
  return TileLayer(
    urlTemplate: source.urlTemplate,
    subdomains: source.subdomains,
    maxNativeZoom: source.maxNativeZoom,
    userAgentPackageName: 'com.iotone.meshmore_sns_app',
    tileProvider: maps == null ? null : CachedTileProvider(maps, source),
    tileBuilder: dim ? mmDimTileBuilder : null,
  );
}

/// R79 — dim a raster basemap for a dark chrome **without touching hue**:
/// `out = gain * in`, a pure RGB scale. Water stays blue, parks stay
/// green, and the aerial-imagery source stays recognisable.
///
/// R70-R73 inverted luminance and desaturated to 0.15 so a pale basemap
/// would not be the brightest surface. Honest about what that cost: the
/// invert flips hue (OSM's blue water read orange), the desaturation then
/// threw the hue away, and because the filter is per-tile and global it
/// also destroyed the *satellite* basemap, which has no luminance
/// structure to invert. Colour in map imagery is content, not theme
/// accent, so the correct treatment is a dim, not a de-colouring.
///
/// Measured on the OSM palette (0-255): land 169, sea 119/148/156, label
/// text 36 (6.7:1 on land). See [kMmDimTileGain] to retune.
ColorFilter mmDimTileFilter({double gain = kMmDimTileGain}) =>
    ColorFilter.matrix(mmDimTileMatrix(gain: gain));

/// How much of the tile's own luminance survives (R79). Low enough that a
/// pale basemap sits under the chrome, high enough to keep label contrast
/// (6.7:1 at 0.70); the map is deliberately a *content* surface, so it is
/// allowed to be brighter than the page around it.
const double kMmDimTileGain = 0.70;

/// The 4x5 matrix behind [mmDimTileFilter] (exposed so it can be tested).
List<double> mmDimTileMatrix({double gain = kMmDimTileGain}) {
  final double g = gain;
  return <double>[
    g, 0, 0, 0, 0, //
    0, g, 0, 0, 0, //
    0, 0, g, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// [TileLayer.tileBuilder] applying [mmDimTileFilter].
Widget mmDimTileBuilder(BuildContext context, Widget tile, TileImage image) =>
    ColorFiltered(colorFilter: mmDimTileFilter(), child: tile);

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
    // One colour per layer, cycling through the scheme's data colours, so
    // two event maps can be told apart and a single layer stays legible
    // over both the dark vector basemap and a pale USGS raster. Every
    // layer used to be `tertiary`, which made overlapping layers and pale
    // imagery unreadable.
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<Color> palette = <Color>[cs.tertiary, cs.primary, cs.secondary];
    return Stack(children: <Widget>[
      for (final (int i, EventLayer l) in shown.indexed)
        _OneEventLayer(
            key: ValueKey<String>('${l.id}@${l.updatedMs}'),
            maps: maps,
            layer: l,
            color: palette[i % palette.length]),
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
  const _OneEventLayer(
      {super.key,
      required this.maps,
      required this.layer,
      required this.color});
  final MapsController maps;
  final EventLayer layer;
  final Color color;

  @override
  State<_OneEventLayer> createState() => _OneEventLayerState();
}

class _OneEventLayerState extends State<_OneEventLayer> {
  late final Future<GeoShapes?> _shapes = widget.maps.shapesFor(widget.layer);

  @override
  Widget build(BuildContext context) {
    final Color c = widget.color;
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
              // 24 dp box around a 10 dp dot: the marker is where the
              // label's tooltip is reachable from, and 10 dp is below the
              // project's own 48 dp floor by a wide margin.
              for (final GeoPoint p in s.points.take(2000))
                Marker(
                  point: p.at,
                  width: 24,
                  height: 24,
                  child: Center(child: SizedBox(width: 10, height: 10, child: _dot(c, p.label))),
                ),
            ]),
        ]);
      },
    );
  }
}
