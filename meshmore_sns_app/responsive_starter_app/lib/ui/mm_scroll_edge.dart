// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/mm_skin.dart';

/// The bottom edge of a page's body: how far down the reader is, and whether
/// there is more below.
///
/// A long page ends at a fold that looks exactly like the end of the screen, so
/// the last row is a row the reader never scrolls to. A hairline along the
/// bottom edge answers that in two words: a track across the full width says
/// "there is more", and the filled part says "this is how much".
///
/// The line sits at the bottom of the body, and the Scaffold already places its
/// body above the device's navigation area, so the line is the top edge of that
/// area in both Android modes — above the gesture handle, and above the taller
/// three-button bar, with no inset arithmetic here and no literal that would
/// have to change when the phone's navigation mode does.
///
/// Three states, and each one is honest about what it knows:
/// * the body scrolls and has more than fits — the track and the fill;
/// * the body scrolls but everything fits — nothing, because a line about
///   nothing is worse than no line;
/// * the body holds no scrollable at all — [closing], a solid thick rule that
///   says the page ends here rather than the screen ending.
///
/// The rule is painted, not tapped: it takes no pointer, so a tap aimed at the
/// last row still reaches the row.
///
/// A page whose bottom edge is a control rather than content — a composer, a
/// docked action bar — can pass [closing] false and put its own edge there
/// instead; the scroll line is suppressed with it.
class MmScrollEdge extends StatefulWidget {
  const MmScrollEdge({
    super.key,
    required this.child,
    this.closing = true,
    this.progress = true,
    this.progressHeight = 2.0,
    this.closingHeight = 3.0,
  });

  /// The page. Its innermost scrollable is the one measured; a scrollable above
  /// this widget (the shell's page view) is not.
  final Widget child;

  /// Whether the scroll line reports position. False draws a plain hairline
  /// instead: a thread that appends at the bottom is not a page you read down, so
  /// a bar that grows as you scroll says the opposite of what the view does.
  final bool progress;

  /// Whether a body with no scrollable gets the solid closing rule. A canvas or
  /// a docked composer says no, because its own bottom edge is the control.
  final bool closing;

  /// Thickness of the scroll line, in logical px.
  final double progressHeight;

  /// Thickness of the closing rule, in logical px. Thicker than the scroll line
  /// so the two are told apart at a glance.
  final double closingHeight;

  @override
  State<MmScrollEdge> createState() => _MmScrollEdgeState();
}

class _MmScrollEdgeState extends State<MmScrollEdge> {
  /// A scrollable reported its metrics at least once.
  bool _sawScrollable = false;

  /// The reported metrics have had a frame to arrive. Until then nothing is
  /// drawn, so a scrollable page does not flash the closing rule on its first
  /// frame before its own metrics arrive.
  bool _settled = false;

  /// The innermost scrollable holds more than fits.
  bool _scrolls = false;

  /// How far down the reader is, 0 at the top and 1 at the end.
  double _fraction = 0;

  @override
  void initState() {
    super.initState();
    // Two frames, because the scrollable's metrics arrive in a microtask that
    // runs after the frame's own post-frame callbacks: one callback would fire
    // first and paint the closing rule for a frame on a page that scrolls.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _settled = true);
      });
    });
  }

  bool _onScroll(ScrollNotification n) {
    // Depth 0 is the innermost scrollable. A scrollable above this widget — the
    // shell's page view — arrives as a remote notification and would otherwise
    // drive the line with the wrong metrics.
    if (n.depth != 0) return false;
    _apply(n.metrics.maxScrollExtent, n.metrics.pixels);
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    if (n.depth != 0) return false;
    _apply(n.metrics.maxScrollExtent, n.metrics.pixels);
    return false;
  }

  void _apply(double maxScrollExtent, double pixels) {
    final bool scrolls = maxScrollExtent > 0;
    final double fraction =
        scrolls ? (pixels / maxScrollExtent).clamp(0.0, 1.0) : 0.0;
    if (_sawScrollable && _scrolls == scrolls && _fraction == fraction) return;
    void apply() {
      if (!mounted) return;
      setState(() {
        _sawScrollable = true;
        _scrolls = scrolls;
        _fraction = fraction;
      });
    }

    // A `ScrollMetricsNotification` is dispatched during layout, and a
    // `setState` there schedules a build inside the frame that is already
    // building: "Build scheduled during frame". It fires the first time a page's
    // content grows past the fold, which is why a longer paragraph could break
    // a screen that had been fine.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final Widget edge = !widget.progress
        ? _ClosingRule(
            key: const ValueKey<String>('mm-scroll-edge-neutral'),
            height: widget.progressHeight,
            color: skin.color.hairline,
          )
        : _sawScrollable
        ? (_scrolls
            ? _ProgressLine(
                key: const ValueKey<String>('mm-scroll-edge'),
                fraction: _fraction,
                height: widget.progressHeight,
                track: skin.color.hairline.withValues(alpha: .6),
                fill: skin.color.accent.withValues(alpha: .55),
              )
            : const SizedBox.shrink())
        : (_settled && widget.closing
            ? _ClosingRule(
                key: const ValueKey<String>('mm-scroll-edge-closing'),
                height: widget.closingHeight,
                color: skin.color.hairline,
              )
            : const SizedBox.shrink());
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: widget.child),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(child: edge),
            ),
          ],
        ),
      ),
    );
  }
}

/// The scroll line: a dim track across the width with an accent fill that grows
/// with the reader's position. The fill never disappears, so a reader at the top
/// still sees that the line is a position and not a divider.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    super.key,
    required this.fraction,
    required this.height,
    required this.track,
    required this.fill,
  });

  final double fraction;
  final double height;
  final Color track;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: track),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction.clamp(.02, 1),
            child: ColoredBox(color: fill),
          ),
        ],
      ),
    );
  }
}

/// The closing rule: a solid thick line, for a page that holds no scrollable and
/// therefore has nothing to say about position. Its only message is "the page
/// ends here".
class _ClosingRule extends StatelessWidget {
  const _ClosingRule({
    super.key,
    required this.height,
    required this.color,
  });

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: height, child: ColoredBox(color: color));
  }
}
