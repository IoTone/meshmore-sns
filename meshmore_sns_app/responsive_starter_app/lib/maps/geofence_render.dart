// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../geofence/geofence_engine.dart';

/// How a fence is drawn on the map, as data rather than as paint.
///
/// A fence was two 1.6 px rings in the secondary colour with no fill, which is
/// invisible over a busy basemap: the one thing on the map that is supposed to
/// shout was the quietest. This is the decision extracted so it can be asserted
/// without a map, and so the same numbers reach the map and the preview in the
/// create sheet.
///
/// The ring is the skin's `alert` role, not a literal and not the accent. A fence
/// is a boundary that fires, so it belongs to the same colour family as an alarm,
/// and every preset already states that role with a measured contrast against its
/// own ground. The fill is the same colour at a low alpha, so the boundary reads
/// as an area rather than as a line, and the inside state raises both.
class GeofenceRender {
  const GeofenceRender({
    required this.fill,
    required this.ring,
    required this.ringWidth,
    required this.inside,
  });

  /// The area inside the fence.
  final Color fill;

  /// The boundary itself.
  final Color ring;

  final double ringWidth;

  /// Whether the reader is currently inside this fence.
  final bool inside;

  /// The fill alpha. Low enough that the basemap and the node pins stay legible
  /// through it, high enough that the area is unmistakable at a glance.
  static const double fillAlpha = 0.14;

  /// The fill alpha once the reader is inside, which is the state that matters:
  /// a fence you are standing in should look different from one you are not.
  static const double fillAlphaInside = 0.26;

  /// The ring alpha, and the ring alpha inside.
  static const double ringAlpha = 0.85;
  static const double ringAlphaInside = 1.0;

  /// The ring width, and the ring width inside. Thick enough to survive a busy
  /// basemap at a glance, thin enough not to hide the streets under it.
  static const double ringWidthOutside = 2.4;
  static const double ringWidthInside = 3.4;

  /// Derive the paint for one fence.
  ///
  /// [alert] is the skin's own alert role. Nothing here is a literal colour, so
  /// all eleven presets get a fence that is loud in their own palette, and the
  /// light presets get one that is loud against paper rather than against
  /// charcoal.
  factory GeofenceRender.of({required Color alert, required bool inside}) {
    return GeofenceRender(
      fill: alert.withValues(
          alpha: inside ? fillAlphaInside : fillAlpha),
      ring: alert.withValues(alpha: inside ? ringAlphaInside : ringAlpha),
      ringWidth: inside ? ringWidthInside : ringWidthOutside,
      inside: inside,
    );
  }
}

/// The shape of a fence, drawn small.
///
/// The create sheet used to preview a circle with a `Container` and a border,
/// which was the same paint as the map by coincidence rather than by
/// construction. A polygon has no such shortcut, so the preview is one widget
/// that draws either shape from the same [GeofenceRender] the map uses: what the
/// reader sizes or draws here is what they get there.
class GeofenceShapePreview extends StatelessWidget {
  const GeofenceShapePreview({
    super.key,
    required this.polygon,
    required this.inside,
    required this.size,
  });

  /// The corners, or null for a circle.
  final List<FencePoint>? polygon;
  final bool inside;
  final double size;

  @override
  Widget build(BuildContext context) {
    final GeofenceRender paint = GeofenceRender.of(
      alert: Theme.of(context).colorScheme.error,
      inside: inside,
    );
    if (polygon == null || polygon!.length < 3) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: paint.fill,
          shape: BoxShape.circle,
          border: Border.all(color: paint.ring, width: paint.ringWidth),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PolygonPreviewPainter(
          polygon: polygon!,
          fill: paint.fill,
          ring: paint.ring,
          ringWidth: paint.ringWidth,
        ),
      ),
    );
  }
}

/// The polygon, fitted to the box with a margin so the boundary is not clipped.
class _PolygonPreviewPainter extends CustomPainter {
  _PolygonPreviewPainter({
    required this.polygon,
    required this.fill,
    required this.ring,
    required this.ringWidth,
  });

  final List<FencePoint> polygon;
  final Color fill;
  final Color ring;
  final double ringWidth;

  @override
  void paint(Canvas canvas, Size size) {
    double minLat = polygon.first.lat;
    double maxLat = polygon.first.lat;
    double minLon = polygon.first.lon;
    double maxLon = polygon.first.lon;
    for (final FencePoint p in polygon) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    final double spanLat = math.max(maxLat - minLat, 1e-9);
    final double spanLon = math.max(maxLon - minLon, 1e-9);
    // One scale for both axes, so the preview keeps the shape's proportions
    // rather than stretching a long thin fence into a square.
    final double inset = ringWidth + 2;
    final double usable = math.max(1, math.min(size.width, size.height) - inset * 2);
    final double scale = usable / math.max(spanLat, spanLon);
    final double dx = (size.width - spanLon * scale) / 2;
    final double dy = (size.height - spanLat * scale) / 2;

    final Path path = Path();
    for (int i = 0; i < polygon.length; i++) {
      final FencePoint p = polygon[i];
      final double x = dx + (p.lon - minLon) * scale;
      // Latitude grows north, the canvas grows down.
      final double y = dy + (maxLat - p.lat) * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..strokeJoin = StrokeJoin.round
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(covariant _PolygonPreviewPainter old) =>
      old.polygon != polygon ||
      old.fill != fill ||
      old.ring != ring ||
      old.ringWidth != ringWidth;
}
