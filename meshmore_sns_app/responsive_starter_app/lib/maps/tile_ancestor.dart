// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// R114 — slippy-map ancestor arithmetic, pure so it runs anywhere.
///
/// A tile at zoom `z` has a parent at `z - 1` that covers it and three
/// neighbours. When the exact tile is not on disk (zooming out faster than
/// the network answers, or offline outside a pack's range) the parent is
/// still a true picture of the area, just coarser, and drawing it where the
/// child belongs reads as "the map is thinking" instead of a black hole.
///
/// The child's place inside an ancestor is the low [levelsUp] bits of its x
/// and y: a parent covers `1 << levelsUp` children per side, and the child
/// sits at `(x & mask, y & mask)` of them.
library;

/// One ancestor of a requested tile.
class TileAncestorCoord {
  const TileAncestorCoord({
    required this.z,
    required this.x,
    required this.y,
    required this.levelsUp,
  });

  final int z;
  final int x;
  final int y;

  /// How many zooms above the requested tile this ancestor sits. 1 = the
  /// parent, 2 = the grandparent.
  final int levelsUp;

  /// Size of the ancestor measured in child tiles, per side.
  int get span => 1 << levelsUp;

  @override
  String toString() => 'TileAncestorCoord($z/$x/$y up $levelsUp)';
}

/// The ancestor [up] levels above `(z, x, y)`.
///
/// Returns null when `up` is not above the tile at all (0, or deeper than the
/// tile itself): zoom 0 has no parent, and asking for one would be a
/// different picture rather than a coarser one.
TileAncestorCoord? ancestorOf(int z, int x, int y, int up) {
  if (up <= 0 || up > z) return null;
  final int az = z - up;
  final int n = 1 << az;
  return TileAncestorCoord(
    z: az,
    x: (x >> up).clamp(0, n - 1),
    y: (y >> up).clamp(0, n - 1),
    levelsUp: up,
  );
}

/// Where `(x, y)` sits inside the ancestor `up` levels above it.
///
/// The ancestor covers `span` child tiles per side, so the child occupies its
/// `1/span` slice of the ancestor at `(column, row)`.
({int column, int row, int span}) sliceInAncestor(int x, int y, int up) {
  final int mask = (1 << up) - 1;
  return (column: x & mask, row: y & mask, span: 1 << up);
}

/// The rectangle of the ancestor, in its own pixels, that belongs to the
/// child, given the ancestor's pixel [size] (slippy tiles are square).
///
/// Plain doubles so this file stays Flutter-free and the planner tests can
/// run without a binding.
({double left, double top, double width, double height}) cropRectInAncestor(
    int x, int y, int up, double size) {
  final ({int column, int row, int span}) slice = sliceInAncestor(x, y, up);
  final double side = size / slice.span;
  return (
    left: slice.column * side,
    top: slice.row * side,
    width: side,
    height: side,
  );
}
