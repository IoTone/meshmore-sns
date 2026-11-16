// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/maps/tile_math.dart';

/// The centre-of-viewport tiles a zoom-in gesture is about to need.
///
/// This helper exists because the version it replaces was a private method on the
/// map's State that paired the current zoom's x/y with a hardcoded zoom 0, so the
/// prefetcher asked for zoom-1 tiles at street-zoom indices — requests that cannot
/// exist, each of which filed a 404 into the absence cache.
void main() {
  test('the centre tiles carry the viewport zoom', () {
    // z14, a viewport of 4x4 tiles starting at 9000/6000.
    const TileRange r = TileRange(14, 9000, 6000, 9003, 6003);
    final List<(int, int, int)> tiles = centreTiles(r);
    expect(tiles.length, 9);
    for (final (int z, int x0, int y0) in tiles) {
      expect(x0, isNonNegative);
      expect(y0, isNonNegative);
      expect(z, 14, reason: 'a child prefetch must start from this zoom');
    }
    // The middle of that range, plus one either side.
    expect(tiles, contains((14, 9001, 6001)));
    expect(tiles, contains((14, 9002, 6002)));
  });

  test('a single-tile viewport gives a 3x3 block around it', () {
    const TileRange r = TileRange(10, 512, 384, 512, 384);
    final List<(int, int, int)> tiles = centreTiles(r);
    expect(tiles.length, 9);
    expect(tiles.first, (10, 511, 383));
    expect(tiles.last, (10, 513, 385));
  });

  test('x wraps at the antimeridian, y clamps at the poles', () {
    // The top-left corner of the world at z2 (4x4 tiles).
    const TileRange r = TileRange(2, 0, 0, 0, 0);
    final List<(int, int, int)> tiles = centreTiles(r);
    for (final (int z0, int x, int y0) in tiles) {
      expect(z0, 2);
      expect(y0, isNonNegative);
      expect(x, inInclusiveRange(0, 3), reason: 'x wraps into the world');
    }
    for (final (int z1, int x1, int y) in tiles) {
      expect(z1, 2);
      expect(x1, inInclusiveRange(0, 3));
      expect(y, greaterThanOrEqualTo(0), reason: 'y cannot go above the pole');
    }
    expect(tiles.length, 6, reason: 'the three tiles above the world are dropped');
    expect(tiles, contains((2, 3, 0)), reason: 'west of column 0 is column 3');
  });

  test('a radius of zero is the centre alone', () {
    const TileRange r = TileRange(8, 100, 100, 104, 104);
    expect(centreTiles(r, radius: 0), <(int, int, int)>[(8, 102, 102)]);
  });

  test('a negative radius asks for nothing', () {
    expect(centreTiles(const TileRange(8, 0, 0, 0, 0), radius: -1), isEmpty);
  });
}
