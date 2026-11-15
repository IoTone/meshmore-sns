// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import 'grid_notice.dart';
import '../meshcore/coverage_store.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/message_heat.dart';
import '../meshcore/own_location.dart';
import '../sns/sns_frame.dart';
import '../theme/mm_skin.dart';
import '../theme/viz_palette.dart';
import '../ui/mm_shape.dart';

/// R51 — sns-cells: a social-activity heat map. Built on the same
/// geographic-cell idea as the hyperlocal grid, but instead of
/// plotting *presence* it plots *chatter*: each observed message
/// turns up the heat in its cell (bright red = busy), and cells
/// cool over a one-hour horizon back to faint white.
///
/// When a message arrives it flashes as a toast near its source
/// node and fades. The whole thing is a "social pulse" line — who's
/// talking, where, right now.
class SnsCellsView extends StatefulWidget {
  const SnsCellsView({
    super.key,
    this.filteredNodes,
    this.frozen = false,
    this.interactive = true,
  });

  final List<DiscoveredNode>? filteredNodes;
  final bool frozen;

  /// R109 — false in the grid's swipe mode: the viewer is the drag, so it is
  /// switched off rather than the body being absorbed. Cell taps still work.
  final bool interactive;

  @override
  State<SnsCellsView> createState() => _SnsCellsViewState();
}

class _Toast {
  _Toast({
    required this.text,
    required this.lat,
    required this.lon,
    required this.createdMs,
    required this.isChannel,
    required this.pubKeyHex,
  });
  final String text;
  final double? lat;
  final double? lon;
  final int createdMs;
  final bool isChannel;
  final String? pubKeyHex;
}

class _SnsCellsViewState extends State<SnsCellsView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  static const int _toastLifeMs = 3500;

  final List<_Toast> _toasts = <_Toast>[];
  final TransformationController _transform = TransformationController();
  int _lastPingSeq = 0;
  String? _flashPubKey; // node to highlight (most recent located DM)
  int _flashUntilMs = 0;

  /// Base scale stop. Default metro (tight local view); cycle out to
  /// region / whole-mesh to see distant nodes (Seattle, Vancouver BC).
  SnsFrame _frame = SnsFrame.metro;

  void _cycleFrame() {
    setState(() => _frame = _frame.next);
    _resetView(); // re-centre on the new base scale
  }

  String _frameLabel(AppLocalizations l, SnsFrame f) => switch (f) {
        SnsFrame.metro => l.snsFrameMetro,
        SnsFrame.region => l.snsFrameRegion,
        SnsFrame.mesh => l.snsFrameMesh,
      };

  @override
  void initState() {
    super.initState();
    // The clock runs at frame rate, the *data* at one hertz.
    //
    // This view used to repaint once a second, on the reasoning that the heat
    // decays over fifteen minutes and a second is invisible. It is not: the
    // painter also draws a CRT sweep on a 3.2 s loop and fades a toast over
    // 3.5 s, and both of those were being advanced in one-second steps, which
    // the owner reported as "the wave is like one FPS". The expensive part was
    // never the clock, it was re-walking every heat cell twice per rebuild, so
    // the heat maps are cached and recomputed once a second while the painter
    // gets a fresh `nowMs` every frame.
    _ticker = Ticker(_onTick)..start();
  }

  /// The heat maps, recomputed at most once a second.
  Map<String, double> _heat = const <String, double>{};
  Map<String, int> _heatCounts = const <String, int>{};
  int _heatSecond = -1;

  void _refreshHeat(MeshcoreController mc, int second) {
    if (second == _heatSecond) return;
    _heatSecond = second;
    _heat = mc.messageHeatScores();
    _heatCounts = mc.messageHeatCounts();
  }

  void _resetView() => _transform.value = Matrix4.identity();

  /// The wall clock the painter reads, advanced once a second.
  int _nowMs = DateTime.now().millisecondsSinceEpoch;
  int _lastPaintSecond = 0;

  void _onTick(Duration _) {
    if (!mounted) return;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final int second = nowMs ~/ 1000;
    // One repaint a second: the heat is a slow colour and the field is static
    // between samples. The frame clock existed for a CRT sweep that no longer
    // exists, and it was most of why this view felt slow.
    if (second == _lastPaintSecond) return;
    _lastPaintSecond = second;
    setState(() => _nowMs = nowMs);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _transform.dispose();
    super.dispose();
  }

  /// Every ping this view has not drawn yet, oldest first.
  ///
  /// Reading `lastHeatPing` alone toasted one message however many arrived while
  /// another grid view was showing — the radar disposes this one, so a burst was
  /// one toast when the heat map was next opened.
  void _ingestPings(MeshcoreController mc) {
    for (final HeatPing p in mc.recentHeatPings) {
      if (p.seq > _lastPingSeq) _ingestPing(p);
    }
  }

  void _ingestPing(HeatPing p) {
    if (p.seq <= _lastPingSeq) return;
    _lastPingSeq = p.seq;
    final int now = _nowMs;
    final bool located = p.latitude != null && p.longitude != null;
    _toasts.add(_Toast(
      text: p.text,
      lat: p.latitude,
      lon: p.longitude,
      createdMs: now,
      isChannel: p.isChannel,
      pubKeyHex: p.pubKeyHex,
    ));
    if (p.pubKeyHex != null) {
      _flashPubKey = p.pubKeyHex;
      _flashUntilMs = now + _toastLifeMs;
    }
    // Auto-scroll to the sender: a located ping snaps the view back
    // to the fit-to-content frame, which always includes the sender
    // (the painter fits self + every active cell + node). Done in a
    // post-frame callback so we don't mutate the transform mid-build.
    if (located && !_transform.value.isIdentity()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resetView();
      });
    }
    // Bound the toast list — keep the newest handful.
    while (_toasts.length > 6) {
      _toasts.removeAt(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);

    if (!widget.frozen) _ingestPings(mc);

    final OwnLocation? own = mc.ownLocation;
    final double? selfLat = own?.latitude;
    final double? selfLon = own?.longitude;

    if (selfLat == null || selfLon == null) {
      return GridNotice(
        message: l.gridNeedsFix,
        icon: Icons.location_searching,
      );
    }

    // R55 — painter colours follow the active skin (was hardcoded hex).
    final VizPalette viz = VizPalette.of(context.skin);
    _refreshHeat(mc, DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final Map<String, double> heat = _heat;
    final Map<String, int> heatCounts = _heatCounts;
    // Nothing has been overheard in this window. The painter would draw an
    // empty grid under the legend, which reads as a broken view rather than as
    // a quiet channel — the same defect the other views fixed with a notice.
    // A quiet channel is a state of *this* view, not a reason to remove it.
    // Replacing the dial with a notice meant the Clear control wiped the whole
    // screen — the owner's "it should not completely take away the entire UX".
    // The notice is drawn over the dial instead, and the lattice stays.
    final bool quiet = heat.isEmpty && _toasts.isEmpty;
    final List<DiscoveredNode> source =
        widget.filteredNodes ?? mc.nodes;
    final List<DiscoveredNode> nodes = <DiscoveredNode>[
      for (final DiscoveredNode n in source)
        if (n.hasLocation) n,
    ];

    final int now = DateTime.now().millisecondsSinceEpoch;
    _toasts.removeWhere((_Toast t) => now - t.createdMs > _toastLifeMs);
    if (_flashUntilMs < now) _flashPubKey = null;

    final int hotCells =
        heat.values.where((double v) => v >= 0.8).length;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _transform,
            panEnabled: widget.interactive,
            scaleEnabled: widget.interactive,
            minScale: 0.4,
            maxScale: 6.0,
            boundaryMargin: const EdgeInsets.all(800),
            child: CustomPaint(
              painter: _SnsCellsPainter(
                type: context.skin.type,
                textScale: MediaQuery.textScalerOf(context).scale(1),
                selfLat: selfLat,
                selfLon: selfLon,
                maxHalfMeters: _frame.maxHalfMeters,
                heat: heat,
                heatCounts: heatCounts,
                quiet: quiet,
                quietLabel: l.heatEmpty,
                nodes: nodes,
                toasts: _toasts,
                flashPubKey: _flashPubKey,
                nowMs: now,
                toastLifeMs: _toastLifeMs,
                accent: viz.accent,
                hot: viz.hot,
                cool: viz.cool,
                node: viz.node,
                flash: cs.tertiary,
                self: viz.self,
                label: cs.onSurface,
                toastBg: cs.surface,
                toastBorder: cs.outline,
                bg: cs.surface,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        // Scale stop — cycle metro → region → mesh so distant nodes
        // (Seattle, Vancouver BC) can be framed instead of edge-pinned.
        Positioned(
          left: 12,
          top: 12,
          child: ActionChip(
            avatar: const Icon(Icons.zoom_out_map, size: 16),
            label: Text(_frameLabel(l, _frame)),
            visualDensity: VisualDensity.compact,
            onPressed: _cycleFrame,
          ),
        ),
        // Recenter — fades in when zoomed/panned away from the base
        // fit-to-content view.
        Positioned(
          right: 12,
          top: 12,
          child: AnimatedBuilder(
            animation: _transform,
            builder: (BuildContext _, Widget? __) {
              final bool atIdentity = _transform.value.isIdentity();
              return AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: atIdentity ? 0.0 : 1.0,
                child: IgnorePointer(
                  ignoring: atIdentity,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(
                        Icons.center_focus_strong, size: 16),
                    label: Text(l.meshTreeRecenter),
                    onPressed: _resetView,
                  ),
                ),
              );
            },
          ),
        ),
        // Status chip — active cells + hot count.
        Positioned(
          left: 12,
          bottom: 12,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              // Solid: the status chip sits on the cells canvas, where a 85 %
              // wash let the cell fills read through its own digits.
              color: cs.surface,
              borderRadius: mmRadius(context, 6),
              border: Border.all(color: cs.outline),
            ),
            child: Text(
              l.snsCellsStatus(heat.length, hotCells),
              style: TextStyle(
                color: cs.onSurface,
                fontSize: context.skin.type.sizeMicro,
                fontFamily: context.skin.type.monoFamily,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
        // Clear-heat control — wipes the accumulated heat + toasts.
        // Useful when moving to a new area or to reset the pulse.
        Positioned(
          right: 12,
          bottom: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FilledButton.tonalIcon(
                icon: const Icon(Icons.clear_all, size: 16),
                label: Text(l.snsCellsClear),
                onPressed: () {
                  mc.clearMessageHeat();
                  setState(() {
                    _toasts.clear();
                    _flashPubKey = null;
                    _lastPingSeq = mc.lastHeatPing?.seq ?? 0;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

}

class _SnsCellsPainter extends CustomPainter {
  _SnsCellsPainter({
    required this.type,
    required this.textScale,
    required this.selfLat,
    required this.selfLon,
    required this.maxHalfMeters,
    required this.heat,
    required this.heatCounts,
    required this.quiet,
    required this.quietLabel,
    required this.nodes,
    required this.toasts,
    required this.flashPubKey,
    required this.nowMs,
    required this.toastLifeMs,
    required this.accent,
    required this.hot,
    required this.cool,
    required this.node,
    required this.flash,
    required this.self,
    required this.label,
    required this.toastBg,
    required this.toastBorder,
    required this.bg,
  });

  /// The skin's type roles, passed in because a painter has no [BuildContext].
  final MmType type;

  /// The user's text scale, multiplied into every label this painter draws.
  /// A `MmType` carries the skin's scale only, so a painted label otherwise
  /// ignores the font setting while the widgets around it honour it.
  final double textScale;

  final double selfLat;
  final double selfLon;

  /// Cap on the view's half-extent (metres) — the active [SnsFrame].
  final double maxHalfMeters;
  final Map<String, double> heat;
  final Map<String, int> heatCounts;

  /// No heat and no toasts: the lattice is still drawn, with a line saying so.
  final bool quiet;

  /// That line's text, passed in because a painter has no localisations.
  final String quietLabel;
  final List<DiscoveredNode> nodes;
  final List<_Toast> toasts;
  final String? flashPubKey;
  final int nowMs;
  final int toastLifeMs;
  final Color accent;
  final Color hot;
  final Color cool;
  final Color node;
  final Color flash;
  final Color self;
  final Color label;
  final Color toastBg;
  final Color toastBorder;
  final Color bg;

  static const double _mPerDegLat = 111320.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final Offset centre = size.center(Offset.zero);
    final double mPerDegLon =
        _mPerDegLat * math.cos(selfLat * math.pi / 180).abs();

    // Fit-to-content range: cover the farthest active cell / node,
    // clamped to a sane window so a single distant peer doesn't zoom
    // us out to nothing.
    double maxOffset = 600; // metres, minimum half-extent
    void considerLatLon(double lat, double lon) {
      final double dN = (lat - selfLat) * _mPerDegLat;
      final double dE = (lon - selfLon) * mPerDegLon;
      final double d = math.max(dN.abs(), dE.abs());
      if (d > maxOffset) maxOffset = d;
    }

    heat.forEach((String key, double _) {
      final ({int latBucket, int lonBucket})? b =
          CoverageStore.parseKey(key);
      if (b == null) return;
      final ({double lat, double lon}) c =
          CoverageStore.cellCentre(b.latBucket, b.lonBucket);
      considerLatLon(c.lat, c.lon);
    });
    for (final DiscoveredNode n in nodes) {
      considerLatLon(n.latitude!, n.longitude!);
    }
    final double half = snsHalfExtentMeters(maxOffset, maxHalfMeters);
    final double pxPerMeter =
        (math.min(size.width, size.height) * 0.46) / half;

    Offset project(double lat, double lon) {
      final double dN = (lat - selfLat) * _mPerDegLat;
      final double dE = (lon - selfLon) * mPerDegLon;
      return Offset(
          centre.dx + dE * pxPerMeter, centre.dy - dN * pxPerMeter);
    }

    final double cellPx =
        CoverageStore.cellDeg * _mPerDegLat * pxPerMeter;

    // A quiet channel says so here, over its own dial, instead of replacing it.
    if (quiet) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: quietLabel,
          style: TextStyle(
            color: label,
            fontSize: type.sizeSm * textScale,
            fontFamily: type.monoFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: size.width * 0.8);
      tp.paint(canvas,
          Offset(centre.dx - tp.width / 2, centre.dy - tp.height / 2));
    }

    // The lattice origin: the south-west corner of the geographic cell that
    // holds us, projected to pixels, so a cell's address and its screen
    // position agree.
    final double selfCellLon =
        (selfLon / CoverageStore.cellDeg).floor() * CoverageStore.cellDeg;
    final double gridOriginX =
        centre.dx + (selfCellLon - selfLon) * mPerDegLon * pxPerMeter;
    final double selfCellLat =
        (selfLat / CoverageStore.cellDeg).floor() * CoverageStore.cellDeg;
    final double gridOriginY =
        centre.dy - (selfCellLat - selfLat) * _mPerDegLat * pxPerMeter;

    // --- Heat field ---
    //
    // Hexagons on a real hex lattice, colour only. What was here drew a square
    // reference grid plus a per-cell hexagon inscribed in a square, ran a
    // blurred stroke around every cell, and animated a CRT sweep, a lens
    // distortion and a chromatic split on top. On a phone that is hundreds of
    // blurred paths per frame, which the owner measured as one frame every
    // three seconds, and the inscribed hexagons overlapped their neighbours
    // because a hexagon does not fit inside a square that sits beside another.
    //
    // This is the map's density field instead: odd-r offset rows, spacing
    // 0.75 of the cell height, one flat fill per occupied cell and nothing
    // else. No lattice, no blur, no motion beyond the colour the heat itself
    // supplies.
    final int step = math.max(1, (16 / cellPx).ceil());
    final double hexW = cellPx * step;
    final double hexH = cellPx * step;
    final Map<(int, int), double> gridHeat = <(int, int), double>{};
    final Map<(int, int), int> gridCount = <(int, int), int>{};
    // A heat key is a sender identity. Its cell comes from the sender's own
    // recorded position, which the painter already has in `nodes`.
    final Map<String, (int, int)> cellOf = <String, (int, int)>{
      for (final DiscoveredNode n in nodes)
        n.pubKeyHex: (
          ((n.latitude! * _mPerDegLat - selfLat * _mPerDegLat) *
                      pxPerMeter -
                  (gridOriginY - centre.dy)) ~/
              (hexH * 0.75),
          ((n.longitude! - selfLon) * mPerDegLon * pxPerMeter -
                  (gridOriginX - centre.dx)) ~/
              hexW,
        ),
    };
    for (final MapEntry<String, double> e in heat.entries) {
      final (int, int)? cell = cellOf[e.key];
      if (cell == null) continue;
      final double v = gridHeat[cell] ?? 0;
      if (e.value > v) gridHeat[cell] = e.value;
      gridCount[cell] = (gridCount[cell] ?? 0) + 1;
    }

    // Heat with no cell to sit in: a sender we cannot place still happened.
    final List<({Offset centre, double hotness, int count})> looseHeat =
        <({Offset centre, double hotness, int count})>[
      for (final MapEntry<String, double> e in heat.entries)
        if (!cellOf.containsKey(e.key))
          (centre: centre, hotness: e.value.clamp(0.0, 1.0), count: 1),
    ];

    // The lattice, always on and cheap: one hairline hexagon per cell, no blur,
    // no glow, no motion. Without it the view is a scatter of dots on black
    // when no message has arrived, which reads as broken rather than as quiet.
    final Paint latticeStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = accent.withValues(alpha: 0.18);
    final int cols = (size.width / hexW).ceil() + 2;
    final int rows = (size.height / (hexH * 0.75)).ceil() + 2;
    for (int row = -1; row < rows; row++) {
      for (int col = -1; col < cols; col++) {
        final double cx =
            gridOriginX + (col + (row.isOdd ? 0.5 : 0)) * hexW + hexW / 2;
        final double cy = gridOriginY + row * hexH * 0.75 + hexH / 2;
        if (cx < -hexW || cx > size.width + hexW) continue;
        if (cy < -hexH || cy > size.height + hexH) continue;
        canvas.drawPath(_hexagon(Offset(cx, cy), hexW / 2, hexH / 2), latticeStroke);
      }
    }

    for (final MapEntry<(int, int), double> e in gridHeat.entries) {
      final (int col, int row) = e.key;
      // Odd-r offset: every other row shifts half a cell, which is what makes
      // hexagons interlock instead of leaving a seam.
      final double cx = gridOriginX +
          (col + (row.isOdd ? 0.5 : 0)) * hexW +
          hexW / 2;
      final double cy = gridOriginY + row * hexH * 0.75 + hexH / 2;
      final Path hex = _hexagon(Offset(cx, cy), hexW / 2, hexH / 2);
      final double hotness = e.value.clamp(0.0, 1.0);
      final Color fill = Color.lerp(cool, hot, hotness)!
          .withValues(alpha: (0.40 + 0.50 * hotness).clamp(0.0, 0.92));
      canvas.drawPath(hex, Paint()..color = fill);
      final int count = gridCount[e.key] ?? 0;
      if (count > 0 && hexW >= 16) {
        _drawCount(canvas, Offset(cx, cy), '$count', hotness > 0.55);
      }
    }
    // A message from a sender we cannot place: no cell, so a small hexagon at
    // the centre rather than a square at an invented address.
    for (final ({Offset centre, double hotness, int count}) h in looseHeat) {
      final Path hex = _hexagon(h.centre, 7, 8);
      canvas.drawPath(
        hex,
        Paint()
          ..color = Color.lerp(cool, hot, h.hotness)!
              .withValues(alpha: 0.7),
      );
    }

    // --- Nodes ---
    for (final DiscoveredNode n in nodes) {
      final Offset p = project(n.latitude!, n.longitude!);
      final bool flashing = n.pubKeyHex == flashPubKey;
      if (flashing) {
        // Expanding ring pulse around the active node.
        canvas.drawCircle(
            p,
            10,
            Paint()
              ..color = flash.withValues(alpha: 0.35)
              ..style = PaintingStyle.fill);
        canvas.drawCircle(
            p,
            13,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = flash);
      }
      canvas.drawCircle(p, 3.5,
          Paint()..color = flashing ? flash : node);
    }


    // --- Self pin (crosshair) ---
    final Paint selfPaint = Paint()
      ..color = self
      ..strokeWidth = 1.6;
    canvas.drawLine(centre.translate(-9, 0), centre.translate(9, 0),
        selfPaint);
    canvas.drawLine(centre.translate(0, -9), centre.translate(0, 9),
        selfPaint);
    canvas.drawCircle(centre, 4, Paint()..color = self);

    // Motion was removed on purpose: the heat is a colour, and a colour does
    // not need a CRT sweep to read.

    // --- Toasts (drawn on top of scanlines so text stays crisp) ---
    // Located messages (DMs from a positioned sender) toast *over
    // the sender*, rising as they age. Unlocated / anonymous channel
    // messages can't be placed — instead of piling on our crosshair
    // (which read as "from me"), they stack as banners down from the
    // top so the chatter is visible without lying about its origin.
    int bannerSlot = 0;
    for (final _Toast t in toasts) {
      final double age = (nowMs - t.createdMs) / toastLifeMs;
      if (age >= 1.0) continue;
      final double opacity = age < 0.15
          ? age / 0.15 // fade in
          : (1.0 - (age - 0.15) / 0.85).clamp(0.0, 1.0); // hold + out
      final bool located = t.lat != null && t.lon != null;
      if (located) {
        final Offset anchor = project(t.lat!, t.lon!);
        final Offset pos = anchor.translate(0, -18 - age * 24);
        _drawToast(canvas, pos, t.text, opacity, t.isChannel);
      } else {
        // Top-banner stack — newest highest. Slide in from the right
        // edge slightly as it appears.
        final double y = 16 + bannerSlot * 26.0;
        final Offset pos = Offset(size.width / 2, y);
        _drawToast(canvas, pos, t.text, opacity, t.isChannel);
        bannerSlot++;
      }
    }
  }

  /// A pointy-top hexagon of half-width [hw] and half-height [hh].
  static Path _hexagon(Offset c, double hw, double hh) => Path()
    ..moveTo(c.dx, c.dy - hh)
    ..lineTo(c.dx + hw, c.dy - hh / 2)
    ..lineTo(c.dx + hw, c.dy + hh / 2)
    ..lineTo(c.dx, c.dy + hh)
    ..lineTo(c.dx - hw, c.dy + hh / 2)
    ..lineTo(c.dx - hw, c.dy - hh / 2)
    ..close();

  /// line, and an occasional horizontal "tear" band that offsets a
  /// slice of the frame. Kept subtle — the heat data is the point,
  /// the glitch is flavour.



  /// Centred message count for a heat square.
  void _drawCount(Canvas canvas, Offset c, String text, bool onHot) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: (onHot ? Colors.white : Colors.black).withValues(alpha: .85),
          fontSize: type.sizeMicro * textScale,
          fontWeight: FontWeight.w700,
          fontFamily: type.monoFamily,
          shadows: <Shadow>[
            Shadow(
                color: (onHot ? Colors.black : Colors.white)
                    .withValues(alpha: .5),
                blurRadius: 2),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
  }


  void _drawToast(Canvas canvas, Offset anchor, String text,
      double opacity, bool isChannel) {
    final String trimmed =
        text.length > 40 ? '${text.substring(0, 40)}…' : text;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: trimmed,
        style: TextStyle(
          color: label.withValues(alpha: opacity),
          fontSize: type.sizeSm * textScale,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 200);
    final Rect box = Rect.fromCenter(
      center: anchor,
      width: tp.width + 16,
      height: tp.height + 10,
    );
    final RRect rr = RRect.fromRectAndRadius(box, const Radius.circular(6));
    canvas.drawRRect(
        rr, Paint()..color = toastBg.withValues(alpha: opacity * 0.92));
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = (isChannel ? accent : flash)
              .withValues(alpha: opacity * 0.8));
    tp.paint(canvas, Offset(box.left + 8, box.top + 5));
  }

  @override
  /// Repaint only when something the picture is made of changed.
  ///
  /// This returned `true` unconditionally. `nowMs` is the one input that moves
  /// on its own, and it only moves while a toast is alive, so comparing it is
  /// what keeps the lattice still when nothing is happening — which is most of
  /// the time this view is open.
  bool shouldRepaint(covariant _SnsCellsPainter old) =>
      old.type != type ||
      old.textScale != textScale ||
      old.selfLat != selfLat ||
      old.selfLon != selfLon ||
      old.maxHalfMeters != maxHalfMeters ||
      old.heat != heat ||
      old.heatCounts != heatCounts ||
      old.quiet != quiet ||
      old.quietLabel != quietLabel ||
      old.nodes != nodes ||
      old.toasts != toasts ||
      old.flashPubKey != flashPubKey ||
      old.nowMs != nowMs ||
      old.toastLifeMs != toastLifeMs ||
      old.accent != accent ||
      old.hot != hot ||
      old.cool != cool ||
      old.node != node ||
      old.flash != flash ||
      old.self != self ||
      old.label != label ||
      old.toastBg != toastBg ||
      old.toastBorder != toastBorder ||
      old.bg != bg;
}
