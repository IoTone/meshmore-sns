// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

/// R61 — slippy-map (Web Mercator, XYZ) tile arithmetic. Pure; no
/// Flutter, so the pack planner and its tests run anywhere.

/// A lat/lon box. South < north; west < east (packs never cross the
/// antimeridian — a pack is a neighbourhood, not an ocean).
class GeoBox {
  const GeoBox(
      {required this.south,
      required this.west,
      required this.north,
      required this.east});

  final double south;
  final double west;
  final double north;
  final double east;

  /// The box that holds a circle of [radiusKm] around a point.
  factory GeoBox.around(double lat, double lon, double radiusKm) {
    const double kmPerDegLat = 111.32;
    final double dLat = radiusKm / kmPerDegLat;
    final double cosLat = math.cos(lat * math.pi / 180).abs();
    final double dLon = radiusKm / (kmPerDegLat * math.max(cosLat, 0.01));
    return GeoBox(
      south: math.max(lat - dLat, -85.0511),
      north: math.min(lat + dLat, 85.0511),
      west: math.max(lon - dLon, -180),
      east: math.min(lon + dLon, 180),
    );
  }

  bool intersects(GeoBox o) =>
      south <= o.north && north >= o.south && west <= o.east && east >= o.west;

  bool contains(double lat, double lon) =>
      lat >= south && lat <= north && lon >= west && lon <= east;

  Map<String, Object> toJson() =>
      <String, Object>{'s': south, 'w': west, 'n': north, 'e': east};

  static GeoBox fromJson(Map<String, Object?> j) => GeoBox(
        south: (j['s']! as num).toDouble(),
        west: (j['w']! as num).toDouble(),
        north: (j['n']! as num).toDouble(),
        east: (j['e']! as num).toDouble(),
      );
}

int lonToTileX(double lon, int z) {
  final int n = 1 << z;
  return ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
}

int latToTileY(double lat, int z) {
  final int n = 1 << z;
  final double r = lat.clamp(-85.0511, 85.0511) * math.pi / 180;
  final double y =
      (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n;
  return y.floor().clamp(0, n - 1);
}

/// Inclusive tile range of [box] at zoom [z].
class TileRange {
  const TileRange(this.z, this.minX, this.minY, this.maxX, this.maxY);
  final int z;
  final int minX;
  final int minY;
  final int maxX;
  final int maxY;

  int get count => (maxX - minX + 1) * (maxY - minY + 1);

  Iterable<(int, int, int)> get tiles sync* {
    for (int x = minX; x <= maxX; x++) {
      for (int y = minY; y <= maxY; y++) {
        yield (z, x, y);
      }
    }
  }
}

TileRange tileRange(GeoBox box, int z) => TileRange(
      z,
      lonToTileX(box.west, z),
      latToTileY(box.north, z), // north is the smaller y
      lonToTileX(box.east, z),
      latToTileY(box.south, z),
    );

/// Every tile in [box] from [minZoom] to [maxZoom], low zoom first so a
/// half-finished pack is still useful zoomed out.
Iterable<(int, int, int)> tilesIn(GeoBox box, int minZoom, int maxZoom) sync* {
  for (int z = minZoom; z <= maxZoom; z++) {
    yield* tileRange(box, z).tiles;
  }
}

int tileCount(GeoBox box, int minZoom, int maxZoom) {
  int n = 0;
  for (int z = minZoom; z <= maxZoom; z++) {
    n += tileRange(box, z).count;
  }
  return n;
}
