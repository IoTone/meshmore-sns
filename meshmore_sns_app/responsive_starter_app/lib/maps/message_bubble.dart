// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../meshcore/discovered_node.dart';
import '../theme/mm_skin.dart';

/// One node that has just spoken, and how much of its bubble is left.
///
/// Named rather than a record so the map's marker loop reads as one thing and a
/// test can build one without inventing a tuple type.
class MessageBubbleMark {
  const MessageBubbleMark({required this.node, required this.remaining});

  final DiscoveredNode node;

  /// 1.0 at arrival, 0.0 when the one-minute window closes.
  final double remaining;
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
  });

  /// Messages from this sender inside the window.
  final int count;

  /// 1.0 at the moment it arrives, 0.0 when the window closes.
  final double remaining;

  final Color color;

  /// What a screen reader says instead of the bubble.
  final String label;

  /// The bubble's box, in logical pixels. Wide enough for two digits.
  static const double size = 54;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final double r = remaining.clamp(0.0, 1.0);
    // The glow grows as it fades, which is what makes it read as a ripple
    // rather than as a badge that changes opacity.
    final double glow = 0.35 + (1 - r) * 0.65;
    return Semantics(
      label: label,
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
    );
  }
}
