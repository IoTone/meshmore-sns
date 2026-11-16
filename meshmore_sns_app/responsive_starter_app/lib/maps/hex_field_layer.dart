// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'hex_field.dart';

/// The density field, drawn as one vector pass.
///
/// It used to be a `PolygonLayer` of one `Polygon` per cell. A cell is a fixed
/// size on the glass, so a phone screen holds about 3,400 of them at every zoom:
/// every camera frame built and culled 3,400 polygons, each carrying six
/// `LatLng` corners, and every field rebuild allocated twenty thousand points.
/// That is the work that made the map stop answering while a pinch was in
/// flight.
///
/// The lattice is regular and its size is constant, so the cells do not need
/// geometry at all: one hexagon path, translated to each cell's projected
/// centre, is the same picture. The painter culls by screen position, reuses one
/// path and two paints, and allocates nothing per cell.
class HexFieldLayer extends StatelessWidget {
  const HexFieldLayer({
    super.key,
    required this.cells,
    required this.radiusPx,
    required this.accent,
    required this.edge,
  });

  /// The cells to draw, already filtered to the ones whose tile has loaded.
  final List<HexCell> cells;

  /// The hexagon's circumradius in logical pixels. Constant by design: the
  /// lattice is a size on the glass, and the ground area is what a zoom changes.
  final double radiusPx;

  /// The fill colour; its alpha comes from the cell's count.
  final Color accent;

  /// The edge colour, which is the skin's foreground so the lattice reads over
  /// any basemap.
  final Color edge;

  @override
  Widget build(BuildContext context) {
    final MapCamera camera = MapCamera.of(context);
    return IgnorePointer(
      child: CustomPaint(
        size: Size(camera.size.x, camera.size.y),
        painter: _HexFieldPainter(
          camera: camera,
          cells: cells,
          radiusPx: radiusPx,
          accent: accent,
          edge: edge,
        ),
      ),
    );
  }
}

class _HexFieldPainter extends CustomPainter {
  _HexFieldPainter({
    required this.camera,
    required this.cells,
    required this.radiusPx,
    required this.accent,
    required this.edge,
  });

  final MapCamera camera;
  final List<HexCell> cells;
  final double radiusPx;
  final Color accent;
  final Color edge;

  /// One pointy-top hexagon of [radiusPx], built once per paint.
  ///
  /// Pointy-top is the lattice's own orientation: a cell is `√3·R` wide and
  /// `1.5·R` from row to row, which is a hexagon with a corner at the top.
  Path _hexagon(double r) {
    final Path p = Path();
    for (int i = 0; i < 6; i++) {
      final double a = -math.pi / 2 + i * math.pi / 3;
      final double x = math.cos(a) * r;
      final double y = math.sin(a) * r;
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    return p..close();
  }

  /// The hexagon's radius in pixels, measured from a cell's own corners.
  ///
  /// The lattice is uniform, so one cell gives the size for all of them, and
  /// measuring it is what makes the cells tile. A radius derived from the zoom
  /// is only right while the camera is at the zoom the field was built for: a
  /// pinch that settles a fraction of a level away, or a camera moved by
  /// anything other than the app's own zoom buttons, left the hexagons a few
  /// per cent smaller than their pitch — a lattice of separated cells with a
  /// gap between them, which is what the owner saw.
  double _measuredRadius() {
    final HexCell c = cells.first;
    if (c.corners.length < 4) return radiusPx;
    final Offset a = camera.getOffsetFromOrigin(c.corners[0]);
    final Offset b = camera.getOffsetFromOrigin(c.corners[3]);
    final double r = (a - b).distance / 2;
    return r.isFinite && r > 0 ? r : radiusPx;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (cells.isEmpty || radiusPx <= 0) return;
    final double r = _measuredRadius();
    final Path hex = _hexagon(r);
    final Paint fill = Paint()..style = PaintingStyle.fill;
    final Paint stroke = Paint()..style = PaintingStyle.stroke;
    // A cell whose centre is this far outside the viewport cannot show any of
    // itself, so it is not drawn. The margin is the hexagon's own reach.
    final double margin = r * 2;
    for (final HexCell c in cells) {
      final Offset o = camera.getOffsetFromOrigin(c.centre);
      if (o.dx < -margin ||
          o.dy < -margin ||
          o.dx > size.width + margin ||
          o.dy > size.height + margin) {
        continue;
      }
      canvas.save();
      canvas.translate(o.dx, o.dy);
      fill.color = accent.withValues(alpha: hexAlpha(c.count));
      canvas.drawPath(hex, fill);
      stroke
        ..color = edge.withValues(alpha: c.count == 0 ? 0.22 : 0.55)
        ..strokeWidth = c.count == 0 ? 0.7 : 1.1;
      canvas.drawPath(hex, stroke);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _HexFieldPainter old) =>
      old.camera != camera ||
      old.cells != cells ||
      old.radiusPx != radiusPx ||
      old.accent != accent ||
      old.edge != edge;
}
