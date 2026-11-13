// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:ui' show Color;

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
