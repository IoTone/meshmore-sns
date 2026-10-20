// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

/// R67 — an edge-swipe affordance for a surface that owns horizontal
/// drags (a pan/zoom map), so the shell's `PageView` is locked while it
/// shows.
///
/// Two narrow bands sit on top of [child], one on each screen edge. A
/// horizontal drag that **starts inside a band** and moves *inward*
/// (left band → right, right band → left) is reported through
/// [onSwipe] as `-1` (previous view) or `+1` (next view). Everything
/// outside the bands is [child]'s, untouched.
///
/// Why bands in a `Stack` rather than a gesture-arena race: each band is
/// a [HitTestBehavior.opaque] sibling stacked above [child], so a touch
/// that lands in it is *hit-tested to the band and never reaches the
/// child at all*. There is no recognizer competition to win or lose.
/// The cost is that inside a band the child gets no touches of any kind
/// (taps and vertical pans too), so keep the band narrow and use
/// [leftInsets] / [rightInsets] to leave a gap where the child has
/// controls at the edge.
///
/// Overlay controls that must stay tappable over the band go in a
/// *later* `Stack` sibling of this widget: later siblings are hit-tested
/// first.
///
/// A swipe commits when the inward travel is at least
/// [minTravel] **or** the inward fling velocity is at least
/// [minVelocity]; a short, slow edge touch does nothing.
///
/// **System Back gesture (R70).** On Android with gesture navigation
/// the OS takes the outer edge zone for Back, so the bands are offset
/// inward by `MediaQuery.systemGestureInsets`; a swipe must begin just
/// inside the OS zone. A swipe from the very edge is the OS's, not ours.
///
/// Assumption: left-to-right layout. The app ships EN and JA only, both
/// LTR; "left band = previous" is not mirrored for RTL.
class MmEdgeSwipe extends StatefulWidget {
  const MmEdgeSwipe({
    super.key,
    required this.child,
    required this.onSwipe,
    this.bandWidth = kMmEdgeBandWidth,
    this.minTravel = kMmEdgeMinTravel,
    this.minVelocity = kMmEdgeMinVelocity,
    this.leftInsets = EdgeInsets.zero,
    this.rightInsets = EdgeInsets.zero,
  });

  final Widget child;

  /// `-1` = previous view, `+1` = next view.
  final ValueChanged<int> onSwipe;

  final double bandWidth;
  final double minTravel;
  final double minVelocity;

  /// Shrinks a band (e.g. `EdgeInsets.only(top: 128)` to leave room for
  /// a control column at that edge).
  final EdgeInsets leftInsets;
  final EdgeInsets rightInsets;

  /// 24 dp: the usual edge-swipe zone. A fling zone is not a tap
  /// target, so the 48 dp minimum does not apply; at 48 dp it would
  /// take 96 dp of a ~400 dp map. Android gesture navigation claims the
  /// outermost ~20-30 dp for system Back, so the band is only as wide as
  /// it can be without being all inside that zone.
  static const double kMmEdgeBandWidth = 24;

  /// 56 dp of inward travel commits a swipe.
  static const double kMmEdgeMinTravel = 56;

  /// 500 dp/s inward fling commits a swipe (Flutter's own page fling
  /// floor is ~365 dp/s; this is a little firmer because the band is
  /// small and easy to graze).
  static const double kMmEdgeMinVelocity = 500;

  @override
  State<MmEdgeSwipe> createState() => _MmEdgeSwipeState();
}

class _MmEdgeSwipeState extends State<MmEdgeSwipe> {
  double _travel = 0;

  /// [side] is -1 for the left band, +1 for the right band. Inward is
  /// +x on the left band and -x on the right band, so `inward = dx * -side`.
  Widget _band(int side, EdgeInsets insets, double gestureInset) {
    final double sign = -side.toDouble();
    return Positioned(
      left: side < 0 ? gestureInset : null,
      right: side > 0 ? gestureInset : null,
      top: insets.top,
      bottom: insets.bottom,
      width: widget.bandWidth,
      child: GestureDetector(
        key: ValueKey<String>(side < 0 ? 'mm-edge-left' : 'mm-edge-right'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _travel = 0,
        onHorizontalDragUpdate: (DragUpdateDetails d) =>
            _travel += (d.primaryDelta ?? 0) * sign,
        onHorizontalDragEnd: (DragEndDetails d) {
          final double v = (d.primaryVelocity ?? 0) * sign;
          if (_travel >= widget.minTravel || v >= widget.minVelocity) {
            // Left band, inward drag => previous page; right => next.
            widget.onSwipe(side);
          }
          _travel = 0;
        },
        onHorizontalDragCancel: () => _travel = 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // R70 — under Android gesture navigation the OS claims the outer
    // ~20-30 dp of each edge for system Back and never delivers those
    // touches to the app (a swipe from x = 3 dp is *Back*, which the
    // shell turns into "go to Dashboard"). Start each band just inside
    // that zone; 0 where there is no system gesture zone.
    final EdgeInsets sys =
        MediaQuery.maybeOf(context)?.systemGestureInsets ?? EdgeInsets.zero;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        _band(-1, widget.leftInsets, sys.left),
        _band(1, widget.rightInsets, sys.right),
      ],
    );
  }
}
