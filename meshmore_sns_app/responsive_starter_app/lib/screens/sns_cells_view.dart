// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;
import 'dart:ui' as ui;

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
import '../theme/theme_controller.dart';
import '../theme/viz_palette.dart';
import '../ui/mm_shape.dart';

/// How far the field can be panned past its own bounds, in pixels. The same
/// slack the tree uses, and for the same reason.
const double _panMargin = 800;

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

/// How long the heat field's wave takes to cross the screen.
///
/// Eight seconds: one crossing is slow enough to read as a sweep passing over the
/// field rather than as a flicker, and short enough that the field is never still
/// for long enough to look frozen.
const int kHeatWavePeriodMs = 8000;

/// Where the heat field's wave is, in pixels, for [nowMs].
///
/// Above the top edge by one band at the start and past the bottom by one at the
/// end, so the band enters and leaves instead of appearing in place. This is the
/// whole of the view's motion — the drawing only reads it — so it is a plain
/// function a test can pin, and it advances at frame resolution rather than once
/// a second, which is what made the field look frozen.
double heatWaveY(int nowMs, double height, double hexH) {
  final double phase = (nowMs % kHeatWavePeriodMs) / kHeatWavePeriodMs;
  return -hexH * 2 + (height + hexH * 4) * phase;
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

  /// The wall clock the painter reads, advanced every frame.
  int _nowMs = DateTime.now().millisecondsSinceEpoch;

  /// The last second a still field repainted on.
  int _lastStillSecond = 0;

  /// True when the reader (or the platform) asked for less motion. The wave then
  /// stops travelling and the clock drops back to the heat's own rate.
  bool _reduceMotion = false;

  void _onTick(Duration _) {
    if (!mounted) return;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_reduceMotion) {
      // One repaint a second is all a still field needs: the heat is a colour
      // that decays over minutes, and nothing else moves.
      if (nowMs ~/ 1000 == _lastStillSecond) return;
      _lastStillSecond = nowMs ~/ 1000;
      setState(() => _nowMs = nowMs);
      return;
    }
    // The heat itself is sampled once a second; the clock is not.
    //
    // This returned for every frame inside the same second, so everything the
    // painter moves — a toast rising and fading over 3.5 s, the wave crossing
    // the field — advanced in one-second steps. That is the "super low FPS"
    // the owner saw on the message bubbles.
    //
    // It advances every frame now, because the wave is always running. What
    // makes that affordable is not this clock: the field is recorded into a
    // picture once and blitted, and only the band the wave is in is built per
    // frame (see `_SnsCellsPainter`).
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
    _reduceMotion = context.watch<ThemeController>().reduceMotion;
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
            boundaryMargin: EdgeInsets.all(_panMargin),
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
                reduceMotion: _reduceMotion,
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
            padding: EdgeInsets.symmetric(
                horizontal: context.skin.space.rowGap,
                vertical: context.skin.space.step(3)),
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
    required this.reduceMotion,
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

  /// Motion is off: the wave holds still and a toast appears and goes without
  /// rising. The field is still drawn — the setting is about movement.
  final bool reduceMotion;
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

  /// The field as it was last recorded, with the key it was recorded for.
  ///
  /// The backdrop — the ground, the lattice, the heat fills and the counts —
  /// changes once a second at most, while the wave moves every frame. Building
  /// a thousand-hexagon path per frame to redraw an unchanged backdrop is what
  /// makes a moving overlay expensive, so the backdrop is recorded once and
  /// drawn as one picture, and only the wave's own band is built per frame.
  static ui.Picture? _fieldPicture;
  static String _fieldKey = '';

  /// What the recorded picture depends on, as one string.
  ///
  /// The heat maps are rebuilt once a second as new instances, so their identity
  /// is the part of the key that changes on a tick; everything else changes on a
  /// resize, a frame-scale change or a theme change.
  /// Everything the recorded backdrop is drawn from.
  ///
  /// Including `textScale` and `label`, because the field paints the quiet line
  /// and the cell counts with both: with no heat the maps are `const {}` and
  /// their identity never changes, so a recorded picture would survive an
  /// accessibility text-size change or a theme change forever and the labels
  /// would stay at the old size and colour.
  String _fieldSignature(Size size) => '${size.width}x${size.height}|'
      '$_hexW|$_hexH|$_gridOriginX|$_gridOriginY|'
      '${identityHashCode(heat)}|${identityHashCode(heatCounts)}|$quiet|'
      '$quietLabel|$bg|$accent|$hot|$cool|$label|$textScale|'
      '${type.sizeSm}|${type.sizeMicro}|${type.monoFamily}';

  /// Where everything is on this frame, computed once.
  ///
  /// The fit-to-content extent, the pixel scale, the cell size and the lattice
  /// origin are needed by the recorded backdrop *and* by the per-frame motion
  /// pass, so they are worked out once here rather than twice. It is a walk over
  /// the heat cells and the nodes, which is a few hundred comparisons: cheap
  /// enough to redo every frame, and far cheaper than rebuilding the field.
  void _computeGeometry(Size size) {
    final Offset centre = size.center(Offset.zero);
    final double mPerDegLon =
        _mPerDegLat * math.cos(selfLat * math.pi / 180).abs();

    // Fit-to-content range: cover the farthest active cell / node, clamped to a
    // sane window so a single distant peer does not zoom us out to nothing.
    double maxOffset = 600; // metres, minimum half-extent
    void considerLatLon(double lat, double lon) {
      final double dN = (lat - selfLat) * _mPerDegLat;
      final double dE = (lon - selfLon) * mPerDegLon;
      final double d = math.max(dN.abs(), dE.abs());
      if (d > maxOffset) maxOffset = d;
    }

    heat.forEach((String key, double _) {
      final ({int latBucket, int lonBucket})? b = CoverageStore.parseKey(key);
      if (b == null) return;
      final ({double lat, double lon}) c =
          CoverageStore.cellCentre(b.latBucket, b.lonBucket);
      considerLatLon(c.lat, c.lon);
    });
    for (final DiscoveredNode n in nodes) {
      considerLatLon(n.latitude!, n.longitude!);
    }
    final double half = snsHalfExtentMeters(maxOffset, maxHalfMeters);
    final double pxPerMeter = (math.min(size.width, size.height) * 0.46) / half;
    final double cellPx = CoverageStore.cellDeg * _mPerDegLat * pxPerMeter;

    // The cell size snaps to a multiple of 16 logical pixels, and a pointy-top
    // hexagon is `√3/2` as wide as it is tall: both pitches used the cell size,
    // so every hexagon sat in a square box — fifteen percent wider than the
    // lattice had room for, which made the field lean and row neighbours overlap.
    final int step = math.max(1, (16 / cellPx).ceil());
    final double hexH = cellPx * step;
    final double hexW = hexH * 0.8660254037844386;

    // The lattice origin: the south-west corner of the geographic cell that holds
    // us, projected to pixels, so a cell's address and its screen position agree.
    final double selfCellLon =
        (selfLon / CoverageStore.cellDeg).floor() * CoverageStore.cellDeg;
    final double selfCellLat =
        (selfLat / CoverageStore.cellDeg).floor() * CoverageStore.cellDeg;

    _centre = centre;
    _mPerDegLon = mPerDegLon;
    _pxPerMeter = pxPerMeter;
    _hexH = hexH;
    _hexW = hexW;
    _gridOriginX = centre.dx + (selfCellLon - selfLon) * mPerDegLon * pxPerMeter;
    _gridOriginY =
        centre.dy - (selfCellLat - selfLat) * _mPerDegLat * pxPerMeter;
  }

  late Offset _centre;
  late double _mPerDegLon;
  late double _pxPerMeter;
  late double _hexH;
  late double _hexW;
  late double _gridOriginX;
  late double _gridOriginY;

  /// A place on the screen, from the geometry the field was laid out with.
  Offset _project(double lat, double lon) => Offset(
        _centre.dx + (lon - selfLon) * _mPerDegLon * _pxPerMeter,
        _centre.dy - (lat - selfLat) * _mPerDegLat * _pxPerMeter,
      );

  @override
  void paint(Canvas canvas, Size size) {
    _computeGeometry(size);
    final String signature = _fieldSignature(size);
    if (signature != _fieldKey || _fieldPicture == null) {
      _fieldPicture?.dispose();
      _fieldPicture = _recordField(size);
      _fieldKey = signature;
    }
    canvas.drawPicture(_fieldPicture!);
    _paintNodesAndToasts(canvas, size);
  }

  /// The backdrop: ground, lattice, heat fills, counts, and the quiet line.
  ui.Picture _recordField(Size size) {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    _paintField(canvas, size);
    return recorder.endRecording();
  }

  /// The wave: a band of green light crossing the field top to bottom on a loop.
  ///
  /// Its position is a function of the clock alone, and it is one path over the
  /// rows it currently crosses rather than a second pass over the whole lattice.
  /// The heat fill says *where* the traffic is and the wave says the field is
  /// live, which is a different question from the one the colours answer.
  void _paintWave(Canvas canvas, Size size) {
    final double hexW = _hexW;
    final double hexH = _hexH;
    final double rowStride = hexH * 0.75;
    final int colStart = ((-_gridOriginX) / hexW).floor() - 2;
    final int rowStart = ((-_gridOriginY) / rowStride).floor() - 2;
    final int cols = (size.width / hexW).ceil() + 4;
    final int rows = (size.height / rowStride).ceil() + 4;
    // One fixed angle when motion is reduced: the band is part of how the field
    // looks, so it stays, but it does not travel.
    final double bandY = reduceMotion
        ? heatWaveY(kHeatWavePeriodMs ~/ 4, size.height, hexH)
        : heatWaveY(nowMs, size.height, hexH);
    // One cell tall on each side of the band's centre. A wider band read as fog
    // over the field rather than as a wave crossing it: the hexagons inside it
    // blurred into one bright smear.
    final double bandH = hexH * 1.1;
    final Path wave = Path();
    for (int row = rowStart; row < rowStart + rows; row++) {
      final double cy = _gridOriginY + row * rowStride + hexH / 2;
      if ((cy - bandY).abs() > bandH) continue;
      for (int col = colStart; col < colStart + cols; col++) {
        final double cx =
            _gridOriginX + (col + (row.isOdd ? 0.5 : 0)) * hexW + hexW / 2;
        _addHexagon(wave, Offset(cx, cy), hexW / 2, hexH / 2);
      }
    }
    if (wave.getBounds().isEmpty) return;
    // A vertical gradient rather than a per-cell alpha: the band has to fade at
    // both of its own edges, and one shader does that for every cell in it.
    canvas.drawPath(
      wave,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(size.width / 2, bandY - bandH),
          Offset(size.width / 2, bandY + bandH),
          <Color>[
            accent.withValues(alpha: 0.0),
            accent.withValues(alpha: 0.07),
            accent.withValues(alpha: 0.26),
            accent.withValues(alpha: 0.07),
            accent.withValues(alpha: 0.0),
          ],
          // A tight ramp: the band has an edge you can see move, rather than a
          // gradient that fades out over half the screen.
          <double>[0.0, 0.3, 0.5, 0.7, 1.0],
        ),
    );
  }

  void _paintField(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final Offset centre = _centre;
    final double mPerDegLon = _mPerDegLon;
    final double pxPerMeter = _pxPerMeter;

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

    final double gridOriginX = _gridOriginX;
    final double gridOriginY = _gridOriginY;

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
    final double hexH = _hexH;
    final double hexW = _hexW;
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
    // The lattice starts at the first cell left of and above the viewport, not
    // at the grid origin: the origin is our own cell, which can be far to the
    // right of the screen, and starting there drew the field in one corner.
    final double rowStride = hexH * 0.75;
    final int colStart = ((-gridOriginX) / hexW).floor() - 2;
    final int rowStart = ((-gridOriginY) / rowStride).floor() - 2;
    final int cols = (size.width / hexW).ceil() + 4;
    final int rows = (size.height / rowStride).ceil() + 4;
    // One path for the whole field and one stroke for it. A draw call per cell
    // was a thousand-odd draws a frame, which is what a wave or a rising toast
    // then had to share the frame with.
    final Path lattice = Path();
    for (int row = rowStart; row < rowStart + rows; row++) {
      final double cy = gridOriginY + row * rowStride + hexH / 2;
      for (int col = colStart; col < colStart + cols; col++) {
        final double cx =
            gridOriginX + (col + (row.isOdd ? 0.5 : 0)) * hexW + hexW / 2;
        _addHexagon(lattice, Offset(cx, cy), hexW / 2, hexH / 2);
      }
    }
    canvas.drawPath(lattice, latticeStroke);

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
  }

  /// The wave, the nodes, the self pin and the toasts: everything that moves.
  void _paintNodesAndToasts(Canvas canvas, Size size) {
    final Offset centre = _centre;
    _paintWave(canvas, size);

    // --- Nodes ---
    // One Paint per job, reused: this painter redraws on every frame of the
    // wave, and a Paint per node per frame is an allocation per node per frame.
    final Paint flashFill = Paint()..style = PaintingStyle.fill;
    final Paint flashRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final Paint dot = Paint();
    for (final DiscoveredNode n in nodes) {
      final Offset p = _project(n.latitude!, n.longitude!);
      final bool flashing = n.pubKeyHex == flashPubKey;
      if (flashing) {
        // Expanding ring pulse around the active node.
        canvas.drawCircle(
            p, 10, flashFill..color = flash.withValues(alpha: 0.35));
        canvas.drawCircle(p, 13, flashRing..color = flash);
      }
      canvas.drawCircle(p, 3.5, dot..color = flashing ? flash : node);
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
      final double opacity = reduceMotion
          ? 1.0
          : age < 0.15
              ? age / 0.15 // fade in
              : (1.0 - (age - 0.15) / 0.85).clamp(0.0, 1.0); // hold + out
      final bool located = t.lat != null && t.lon != null;
      if (located) {
        final Offset anchor = _project(t.lat!, t.lon!);
        final Offset pos =
            anchor.translate(0, reduceMotion ? -18 : -18 - age * 24);
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
  static Path _hexagon(Offset c, double hw, double hh) {
    final Path p = Path();
    _addHexagon(p, c, hw, hh);
    return p;
  }

  /// The same hexagon, added to [into] as one more subpath.
  ///
  /// The field is one path: a thousand `drawPath` calls a frame is what made a
  /// moving overlay expensive here, and a path with a thousand subpaths is one
  /// stroke.
  static void _addHexagon(Path into, Offset c, double hw, double hh) {
    into
      ..moveTo(c.dx, c.dy - hh)
      ..lineTo(c.dx + hw, c.dy - hh / 2)
      ..lineTo(c.dx + hw, c.dy + hh / 2)
      ..lineTo(c.dx, c.dy + hh)
      ..lineTo(c.dx - hw, c.dy + hh / 2)
      ..lineTo(c.dx - hw, c.dy - hh / 2)
      ..close();
  }



  /// line, and an occasional horizontal "tear" band that offsets a
  /// slice of the frame. Kept subtle — the heat data is the point,
  /// the glitch is flavour.



  /// Centred message count for a heat square.
  void _drawCount(Canvas canvas, Offset c, String text, bool onHot) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: (onHot ? kOnHotCell : kOnCoolCell).withValues(alpha: .85),
          fontSize: type.sizeMicro * textScale,
          fontWeight: FontWeight.w700,
          fontFamily: type.monoFamily,
          shadows: <Shadow>[
            Shadow(
                color: (onHot ? kOnCoolCell : kOnHotCell)
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
      old.reduceMotion != reduceMotion ||
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
