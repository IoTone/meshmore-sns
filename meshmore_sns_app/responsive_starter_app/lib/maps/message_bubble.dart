// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../meshcore/discovered_node.dart';
import '../theme/mm_skin.dart';

/// One node that has just spoken, and how much of its bubble is left.
///
/// Named rather than a record so the map's marker loop reads as one thing and a
/// test can build one without inventing a tuple type.
class MessageBubbleMark {
  const MessageBubbleMark({
    required this.node,
    required this.remaining,
    this.arrivedAt,
  });

  final DiscoveredNode node;

  /// 1.0 at arrival, 0.0 when the one-minute window closes.
  final double remaining;

  /// When the message arrived, for the bubble's own lift and delay. Null in a
  /// harness that only cares about the fade.
  final DateTime? arrivedAt;
}

/// A bubble over a node that has just sent something.
///
/// The owner's ask: for a minute after a message arrives, show where it came
/// from. The map is a different page from the chat, so a message there is
/// invisible here — this is the one mark that says "traffic, from that radio,
/// just now".
///
/// It is a *bubble* rather than a ring at the node's own size because a node
/// glyph is 13 px and cannot swell much before it collides with its neighbours.
/// It fades on its own clock: the map rebuilds once a second while any bubble is
/// live, and the alpha is the bubble's remaining life, so a message that scrolled
/// into the past also stops drawing.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    this.count = 1,
    required this.remaining,
    required this.color,
    required this.label,
    this.arrivedAt,
    this.delay = Duration.zero,
  });

  /// When the message arrived, so the bubble can rise. Null draws it settled.
  final DateTime? arrivedAt;

  /// How late this bubble starts, for a burst that arrives together.
  final Duration delay;

  /// Messages from this sender inside the window.
  final int count;

  /// 1.0 at the moment it arrives, 0.0 when the window closes.
  final double remaining;

  final Color color;

  /// What a screen reader says instead of the bubble.
  final String label;

  /// A stable per-node offset, in logical pixels.
  ///
  /// Two nodes a few metres apart put their bubbles on the same spot, and a
  /// stack of numbers over one glyph reads as a glitch. The offset spreads them
  /// deterministically, so a bubble does not jump between frames.
  static Offset offsetFor(String key, {double spread = 26}) {
    int h = 0;
    for (final int c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    // A ring rather than a square, so no two bubbles share a corner.
    final double a = (h % 360) * 3.141592653589793 / 180;
    final double r = spread * (0.55 + (h >> 9 & 0xFF) / 255 * 0.45);
    return Offset(math.cos(a) * r, math.sin(a) * r * 0.62 - 6);
  }

  /// The bubble's box, in logical pixels. Wide enough for two digits.
  static const double size = 54;

  /// How long a bubble takes to rise into place.
  static const Duration rise = Duration(milliseconds: 420);

  /// How long after the first bubble a later one starts, so a burst of traffic
  /// arrives one at a time instead of all at once.
  static const Duration stagger = Duration(milliseconds: 140);

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final double r = remaining.clamp(0.0, 1.0);
    // Rise: the bubble lifts from the node and settles, then sits still for the
    // rest of its minute. `delay` lets a burst arrive one after another.
    double rise = 1;
    final DateTime? at = arrivedAt;
    if (at != null) {
      final int ms = DateTime.now().difference(at).inMilliseconds - delay.inMilliseconds;
      rise = (ms / MessageBubble.rise.inMilliseconds).clamp(0.0, 1.0);
    }
    final double eased = Curves.easeOutBack.transform(rise).clamp(0.0, 1.15);
    final double lift = (1 - rise) * skin.space.step(4);
    // The glow grows as it fades, which is what makes it read as a ripple
    // rather than as a badge that changes opacity.
    final double glow = 0.35 + (1 - r) * 0.65;
    return Semantics(
      label: label,
      child: Transform.translate(
        offset: Offset(0, lift),
        child: Transform.scale(
          scale: 0.7 + 0.3 * eased.clamp(0.0, 1.0),
          child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // The soft ring: transparent in the middle, coloured at the rim,
            // so the node's own glyph stays readable underneath it.
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  stops: <double>[glow - 0.18, glow],
                  colors: <Color>[
                    color.withValues(alpha: 0),
                    color.withValues(alpha: 0.42 * r),
                  ],
                ),
              ),
              child: const SizedBox.expand(),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: skin.space.step(1)),
              constraints: BoxConstraints(minWidth: skin.space.step(5)),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.92 * r),
                borderRadius: BorderRadius.circular(skin.shape.cornerSize),
                border: Border.all(color: skin.color.base, width: 1.5),
              ),
              child: Text(
                count > 9 ? '9+' : '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: skin.type.sizeMicro,
                  fontWeight: FontWeight.w700,
                  // The bubble sits on the map's own palette, not on a skin
                  // surface, so its ink is the surface colour: the one value
                  // guaranteed to be opposite the fill.
                  color: skin.color.base,
                ),
              ),
            ),
          ],
        ),
          ),
        ),
      ),
    );
  }
}
