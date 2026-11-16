// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../meshcore/discovered_node.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../meshcore/own_location.dart';
import '../../maps/compass.dart';
import '../../maps/radar_scale.dart';
import '../../theme/mm_skin.dart';
import '../../theme/theme_controller.dart';
import '../../theme/viz_palette.dart';
import '../../ui/mm_audio_toggle.dart';
import '../../ui/mm_scaffold.dart';
import '../../util/geo.dart';
import '../node_detail_sheet.dart';
import 'dashboard_model.dart';
import 'my_pubkey_line.dart';

/// Concept C — **Hyperlocal Field** dashboard: discovery-first. The hero
/// is a **node radar** — self at the centre, peers plotted as blips by
/// distance (real GPS distance when both ends have a fix, otherwise by
/// proximity band) and bearing (real bearing when known, otherwise a
/// stable per-node angle). Calm, field-legible, lower chrome than NERV;
/// a slow sweep gives it life (off under reduce-motion). Tap a blip →
/// the node sheet; tap the centre → self. A compact status rail sits
/// underneath. Renders from the same controller as every other skin.
class HyperlocalDashboard extends StatefulWidget {

  const HyperlocalDashboard({super.key});

  @override
  State<HyperlocalDashboard> createState() => _HyperlocalDashboardState();
}

class _HyperlocalDashboardState extends State<HyperlocalDashboard>
    with SingleTickerProviderStateMixin {
  /// One revolution per refresh interval, matching the grid's default poll. The
  /// dial is a picture of how fresh the reading is, so the line that sweeps it
  /// keeps the same time as the thing it is measuring.
  static const Duration sweepPeriod = Duration(seconds: 15);

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: sweepPeriod,
  );

  /// Which way the phone points, so the dial's top is the phone's own facing.
  ///
  /// The app's one compass when there is one above us, so a heading does not
  /// restart on every tab switch; its own only when the screen is shown alone.
  late final CompassHeading _compass;
  late final bool _ownsCompass;

  @override
  void initState() {
    super.initState();
    final CompassHeading? shared = context.sharedCompass;
    _ownsCompass = shared == null;
    _compass = shared ?? CompassHeading();
    _compass.start();
  }

  @override
  void dispose() {
    if (_ownsCompass) _compass.dispose();
    _sweep.dispose();
    super.dispose();
  }

  Future<void> _showDetail(
      MeshcoreController mc, DiscoveredNode n, bool isSelf) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => NodeDetailSheet(
        node: n,
        isSelf: isSelf,
        distanceMeters: n.hasLocation
            ? mc.distanceMetersTo(n.latitude!, n.longitude!)
            : null,
        isFavourite: mc.favorites.contains(n.pubKeyHex),
        isKnown: mc.known.contains(n.pubKeyHex),
        onToggleFavourite: () => mc.toggleFavorite(n.pubKeyHex),
        recentDms: mc.dmHistoryFor(n.pubKeyHex),
        proximity: mc.proximityFor(n),
        tags: mc.tagsFor(n.pubKeyHex),
        tagSuggestions: mc.allTags,
        onAddTag: (String t) => mc.addTagTo(n.pubKeyHex, t),
        onRemoveTag: (String t) => mc.removeTagFrom(n.pubKeyHex, t),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final bool reduceMotion =
        context.select<ThemeController, bool>((ThemeController t) => t.reduceMotion);
    final DashboardModel m = DashboardModel.gather(mc, l);

    // Honour reduce-motion: stop the sweep (battery + accessibility);
    // otherwise keep it rotating.
    if (reduceMotion) {
      if (_sweep.isAnimating) _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }

    return MmScaffold(
      child: Column(
        children: <Widget>[
          _TopBar(model: m, skin: skin),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(skin.space.screenEdge, skin.space.labelToControl, skin.space.screenEdge, skin.space.rowGap),
              child: LayoutBuilder(
                builder: (BuildContext _, BoxConstraints c) {
                  final double side =
                      math.min(c.maxWidth, c.maxHeight);
                  final Offset center = Offset(side / 2, side / 2);
                  // Leave a gutter outside the outer ring for the name
                  // callouts (drawn beyond the rings, never over them).
                  final double maxR = side / 2 * 0.68;
                  final ({DiscoveredNode? self, List<_PositionedBlip> blips})
                      laid = _layout(mc, skin, center, maxR);
                  return Center(
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (TapUpDetails d) => _onTap(
                            d.localPosition, laid.blips, laid.self, center, mc),
                        child: Stack(
                          children: <Widget>[
                            Positioned.fill(
                              child: AnimatedBuilder(
                                animation: _sweep,
                                builder: (BuildContext _, Widget? __) =>
                                    CustomPaint(
                                  painter: _RadarPainter(
                                    center: center,
                                    maxR: maxR,
                                    rimMeters: rimMeters,
                                    blips: laid.blips,
                                    hasSelf: laid.self != null,
                                    sweep: reduceMotion ? null : _sweep.value,
                                    grid: VizPalette.of(skin).grid,
                                    accent: skin.color.accent,
                                    // The hand of the clock, opposite the skin:
                                    // burnt red on the forest dials, cyan on
                                    // NERV. Never one of the marks it sweeps.
                                    sweepColor: VizPalette.sweepFor(skin),
                                    self: skin.color.accent,
                                    fg: skin.color.fg,
                                    fgMuted: skin.color.fgMuted,
                                    monoFamily: skin.type.monoFamily,
                                    type: skin.type,
                                    textScale: MediaQuery.textScalerOf(context)
                                        .scale(1),
                                    headingDegrees: _compass.heading,
                                    northMarker: VizPalette.north,
                                  ),
                                ),
                              ),
                            ),
                            if (laid.blips.isEmpty)
                              Center(
                                child: Text(
                                  l.dashHyperEmpty,
                                  style: TextStyle(
                                      color: skin.color.fgMuted,
                                      fontFamily: skin.type.monoFamily,
                                      fontSize: skin.type.sizeBody),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (m.events.isNotEmpty)
            _ActivityTicker(model: m, skin: skin),
          _StatusRail(model: m, mc: mc, skin: skin, l: l),
        ],
      ),
    );
  }

  void _onTap(Offset p, List<_PositionedBlip> blips, DiscoveredNode? self,
      Offset center, MeshcoreController mc) {
    // Centre (self) takes priority within a generous radius.
    if (self != null && (p - center).distance <= 22) {
      _showDetail(mc, self, true);
      return;
    }
    _PositionedBlip? best;
    double bestD = 28; // max tap slop, logical px
    // The blips are drawn on the turned dial, so a tap has to be measured
    // against where the peer *appears*. Comparing against the laid-out
    // position meant a turn moved every dot away from its own hit area.
    final double? h = _compass.heading;
    final double turn = -(h ?? 0) * math.pi / 180;
    for (final _PositionedBlip b in blips) {
      Offset at = b.offset;
      if (h != null) {
        final Offset d = b.offset - center;
        at = center +
            Offset(d.dx * math.cos(turn) - d.dy * math.sin(turn),
                d.dx * math.sin(turn) + d.dy * math.cos(turn));
      }
      final double d = (p - at).distance;
      if (d < bestD) {
        bestD = d;
        best = b;
      }
    }
    if (best != null) _showDetail(mc, best.node, false);
  }

  /// Project nodes onto the radar. Self (if present in the fabric) is
  /// returned separately — it always sits at the centre.
  /// The rim distance this dial is drawn at, in metres, set by `_layout`.
  double rimMeters = 1000;

  ({DiscoveredNode? self, List<_PositionedBlip> blips}) _layout(
      MeshcoreController mc, MmSkin skin, Offset center, double maxR) {
    final String? selfPk = mc.ownPubKeyHex;
    DiscoveredNode? self;
    final List<DiscoveredNode> peers = <DiscoveredNode>[];
    for (final DiscoveredNode n in mc.nodes) {
      if (selfPk != null && n.pubKeyHex == selfPk) {
        self = n;
      } else {
        peers.add(n);
      }
    }

    final OwnLocation? own = mc.ownLocation;
    final Map<String, double?> dist = <String, double?>{};
    final Map<String, double?> bearing = <String, double?>{};
    double? maxMeters;
    for (final DiscoveredNode n in peers) {
      double? d;
      double? b;
      if (n.hasLocation) {
        d = mc.distanceMetersTo(n.latitude!, n.longitude!);
        if (own != null) {
          b = bearingRadians(
              own.latitude, own.longitude, n.latitude!, n.longitude!);
        }
      }
      dist[n.pubKeyHex] = (d != null && d.isFinite) ? d : null;
      bearing[n.pubKeyHex] = b;
      final double? dv = dist[n.pubKeyHex];
      if (dv != null) maxMeters = (maxMeters == null) ? dv : math.max(maxMeters, dv);
    }
    if (maxMeters != null && maxMeters < 1000) maxMeters = 1000;
    // The rim is three round steps, not whatever the furthest peer happens to be
    // at: the labels are a third, two thirds and the rim, so a step of 75 km
    // reads 75 / 150 / 225 where a raw maximum read 66 / 132 / 198.
    rimMeters = maxMeters == null
        ? 1000.0
        : radarRingStepMeters(maxMeters) * 3;

    final List<_PositionedBlip> blips = <_PositionedBlip>[];
    for (final DiscoveredNode n in peers) {
      final NodeProximity prox = mc.proximityFor(n);
      final double? d = dist[n.pubKeyHex];
      double frac;
      if (d != null) {
        frac = (d / rimMeters).clamp(0.08, 0.97);
      } else {
        // No distance, so the radius is a *band* rather than a value: each
        // node gets its own place inside the band its proximity implies.
        //
        // One value per band put every peer the radio has no position for on a
        // single circle — on the handset, 196 of them drew as a clean ring
        // around the rim, which reads as a rendering fault rather than as a
        // reading. The band says the same thing and looks like the scatter it
        // is, and "unknown" is spread across the whole dial because that is
        // exactly what is known about it.
        frac = radarPlaceholderFraction(
            prox, n.pubKeyHex, (String k, int seed) => _hashUnit(k, seed));
      }
      final double angle =
          bearing[n.pubKeyHex] ?? (_hashUnit(n.pubKeyHex, 7) * 2 * math.pi);
      final double r = frac * maxR;
      // angle: 0 = North (up), clockwise. The turn towards the phone's own
      // facing happens in the painter, not here: this layout is memoised and
      // recomputing it per frame cost more than the whole dial.
      // 
      final Offset pos = Offset(
        center.dx + r * math.sin(angle),
        center.dy - r * math.cos(angle),
      );
      final bool inRange =
          prox == NodeProximity.near || prox == NodeProximity.recent;
      final Color color = switch (prox) {
        NodeProximity.near || NodeProximity.recent => skin.color.ok,
        NodeProximity.mid => skin.color.accent,
        NodeProximity.far || NodeProximity.unknown => skin.color.fgMuted,
      };
      blips.add(_PositionedBlip(
        offset: pos,
        node: n,
        color: color,
        inRange: inRange,
      ));
    }
    return (self: self, blips: blips);
  }
}

/// Stable pseudo-random unit value in [0,1) from a pubkey + salt — keeps
/// a node's radar angle/jitter fixed across rebuilds (FNV-1a).
double _hashUnit(String key, int salt) {
  int h = 0x811c9dc5 ^ salt;
  for (final int c in key.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return (h % 100000) / 100000.0;
}

class _PositionedBlip {
  _PositionedBlip({
    required this.offset,
    required this.node,
    required this.color,
    required this.inRange,
  });
  final Offset offset;
  final DiscoveredNode node;
  final Color color;
  final bool inRange;
}

/// A name callout being laid out: [y] is mutated by the declutter pass.
class _LabelSlot {
  _LabelSlot({required this.blip, required this.at, required this.y, required this.tp});
  final _PositionedBlip blip;

  /// Where the blip appears on the turned dial, which is where its leader
  /// line must start.
  final Offset at;
  double y;
  final TextPainter tp;
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.center,
    required this.maxR,
    required this.rimMeters,
    required this.blips,
    required this.hasSelf,
    required this.sweep,
    required this.grid,
    required this.accent,
    required this.sweepColor,
    required this.self,
    required this.fg,
    required this.fgMuted,
    required this.monoFamily,
    required this.type,
    required this.textScale,
    required this.headingDegrees,
    required this.northMarker,
  });

  final Offset center;
  final double maxR;

  /// The distance at the rim, in metres: three round steps, so the ring labels
  /// are round too. See `radarRingStepMeters`.
  final double rimMeters;
  final List<_PositionedBlip> blips;
  final bool hasSelf;

  /// Sweep phase in [0,1), or null under reduce-motion (no sweep drawn).
  final double? sweep;
  final Color grid;
  final Color accent;

  /// The sweep's own colour: the hue opposite this skin's accent.
  final Color sweepColor;
  final Color self;
  final Color fg;
  final Color fgMuted;
  final String monoFamily;

  /// The skin's type roles. A painter has no [BuildContext], so the sizes come
  /// in rather than being reached for: the callouts used a literal 11.5 and the
  /// north letter a literal 10, which meant the radar's own text ignored both
  /// the in-app font size and the system one while everything around it grew.
  final MmType type;

  /// The user's text scale, multiplied into every size this painter draws.
  ///
  /// A `CustomPainter` has no `MediaQuery`, and `MmType` only carries the
  /// *skin's* scale, so before this the dial's names and its north letter were
  /// the one text in the app that ignored the font setting entirely: at 200 %
  /// every other label grew and the radar's stayed the same, which is the
  /// opposite of what a person who raised the setting needs.
  final double textScale;

  /// Which way the phone points, or null when nothing knows. The dial turns so
  /// its top is the phone's own facing and the red marker says where north is;
  /// with no heading it stays north-up, which is the only claim it can make.
  final double? headingDegrees;

  /// The red the north marker is drawn in: the skin's own alert colour, so the
  /// marker is red on every skin without a literal.
  final Color northMarker;

  /// A point in dial space: the blips are laid out by true bearing, and the
  /// dial's top is the phone's own facing.
  Offset _turn(Offset o) {
    final double? h = headingDegrees;
    if (h == null) return o;
    final double t = -h * math.pi / 180;
    final Offset d = o - center;
    return center +
        Offset(d.dx * math.cos(t) - d.dy * math.sin(t),
            d.dx * math.sin(t) + d.dy * math.cos(t));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Range rings.
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = grid.withValues(alpha: 0.45);
    for (final double f in <double>[1 / 3, 2 / 3, 1.0]) {
      canvas.drawCircle(center, maxR * f, ring);
    }
    // Cross-hairs.
    final Paint hair = Paint()
      ..strokeWidth = 1
      ..color = grid.withValues(alpha: 0.30);
    canvas.drawLine(Offset(center.dx, center.dy - maxR),
        Offset(center.dx, center.dy + maxR), hair);
    canvas.drawLine(Offset(center.dx - maxR, center.dy),
        Offset(center.dx + maxR, center.dy), hair);

    // Sweep — a leading line + a trailing gradient wedge.
    if (sweep != null) {
      final double a = sweep! * 2 * math.pi; // canvas angle (0 = +x)
      const double trail = math.pi / 3;
      final Rect rect = Rect.fromCircle(center: center, radius: maxR);
      final Paint wedge = Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: trail,
          colors: <Color>[
            sweepColor.withValues(alpha: 0.0),
            sweepColor.withValues(alpha: 0.22),
          ],
          transform: GradientRotation(a - trail),
        ).createShader(rect);
      canvas.drawArc(rect, a - trail, trail, true, wedge);
      final Paint lead = Paint()
        ..strokeWidth = 1.5
        ..color = sweepColor.withValues(alpha: 0.65);
      canvas.drawLine(
          center,
          Offset(center.dx + maxR * math.cos(a),
              center.dy + maxR * math.sin(a)),
          lead);
    }

    // North, as a red marker that moves with the dial — the arrow alone. It used
    // to carry an "N" beside it, painted upright on the same bearing: the letter
    // collided with the arrow at most headings and read as a label lying on the
    // rim instead of a direction.
    final double northAt = CompassHeading.northMarkerDegrees(headingDegrees);
    paintNorthMarker(canvas, center, maxR,
        markerDegrees: northAt, color: northMarker);

    // Blips (dots only — in-range names are drawn as decluttered
    // callouts in the gutter outside the rings, below).
    for (final _PositionedBlip b in blips) {
      final Offset at = _turn(b.offset);
      if (b.inRange) {
        canvas.drawCircle(at, 9,
            Paint()..color = b.color.withValues(alpha: 0.18));
      }
      canvas.drawCircle(at, b.inRange ? 4.5 : 3.5,
          Paint()..color = b.color);
    }

    // Self at the centre — a ringed accent pip.
    if (hasSelf) {
      canvas.drawCircle(center, 9,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = self.withValues(alpha: 0.8));
      canvas.drawCircle(center, 4, Paint()..color = self);
    }

    _drawCallouts(canvas, size);
  }

  /// In-range peer names, placed **outside** the outer ring with leader
  /// lines back to their blips. Split into left/right columns and pushed
  /// vertically apart so they never overlap each other or the radar.
  void _drawCallouts(Canvas canvas, Size size) {
    final double fontSize =
        radarLabelSizes(type, textScale: textScale).callout;
    final double minGap = 15;
    final double top = 10, bottom = size.height - 10;
    final double gutter = (size.width / 2 - maxR - 8).clamp(34, 96);

    final List<_LabelSlot> left = <_LabelSlot>[];
    final List<_LabelSlot> right = <_LabelSlot>[];
    for (final _PositionedBlip b in blips) {
      if (!b.inRange) continue;
      // Measured, not estimated: `layout(maxWidth:)` with a single line and an
      // ellipsis puts the cut exactly where the gutter ends, at whatever size
      // the skin is currently drawing. The old `_fit` guessed from an average
      // character width, which is wrong for every glyph that is not average and
      // wrong by the whole scale factor once the text grew.
      final TextPainter tp = _textPainter(
        b.node.name.isEmpty ? b.node.shortId : b.node.name,
        fontSize,
        maxWidth: gutter,
      );
      // The column is decided by where the blip *appears*, not where it sits
      // in the unrotated layout, or a label would cross the dial after a turn.
      final Offset at = _turn(b.offset);
      final bool isRight = at.dx >= center.dx;
      (isRight ? right : left).add(_LabelSlot(blip: b, at: at, y: at.dy, tp: tp));
    }
    _declutter(left, top, bottom, minGap);
    _declutter(right, top, bottom, minGap);

    final Paint leader = Paint()
      ..strokeWidth = 1
      ..color = fgMuted.withValues(alpha: 0.5);
    for (final _LabelSlot s in right) {
      final double lx = center.dx + maxR + 6;
      canvas.drawLine(s.at, Offset(lx, s.y), leader);
      s.tp.paint(canvas, Offset(lx + 3, s.y - s.tp.height / 2));
    }
    for (final _LabelSlot s in left) {
      final double lx = center.dx - maxR - 6;
      canvas.drawLine(s.at, Offset(lx, s.y), leader);
      s.tp.paint(canvas, Offset(lx - 3 - s.tp.width, s.y - s.tp.height / 2));
    }
  }

  /// Push a column of label slots apart so adjacent rows clear [minGap],
  /// keeping the whole column within [top]..[bottom].
  void _declutter(List<_LabelSlot> slots, double top, double bottom,
      double minGap) {
    if (slots.isEmpty) return;
    slots.sort((_LabelSlot a, _LabelSlot b) => a.y.compareTo(b.y));
    for (int i = 1; i < slots.length; i++) {
      if (slots[i].y < slots[i - 1].y + minGap) {
        slots[i].y = slots[i - 1].y + minGap;
      }
    }
    if (slots.last.y > bottom) {
      slots.last.y = bottom;
      for (int i = slots.length - 2; i >= 0; i--) {
        if (slots[i].y > slots[i + 1].y - minGap) {
          slots[i].y = slots[i + 1].y - minGap;
        }
      }
    }
    for (final _LabelSlot s in slots) {
      if (s.y < top) s.y = top;
    }
  }

  /// One line, ellipsised at [maxWidth] by the real text engine.
  ///
  /// The layout is bounded rather than estimated, so the cut lands on the
  /// gutter's edge at the size the skin is drawing right now — the case the
  /// character-count estimate got wrong as soon as the text scale changed.
  TextPainter _textPainter(String text, double size, {double? maxWidth}) =>
      radarCalloutPainter(
        text: text,
        size: size,
        maxWidth: maxWidth,
        monoFamily: monoFamily,
        color: fg,
      );

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.sweep != sweep ||
      old.blips != blips ||
      old.maxR != maxR ||
      old.center != center ||
      // The dial turns with the phone. Without this a heading change was only
      // picked up because the sweep animation forced a repaint every frame, so
      // with reduce-motion on — where `sweep` is null and never changes — the
      // whole radar froze at whatever heading it was built with.
      old.headingDegrees != headingDegrees ||
      // The sweep's colour is derived from the skin, so a theme change has to
      // repaint it. The grid's painter got this comparison and this one did not,
      // which is the R166 regression again: under reduce-motion the sweep is
      // static, so nothing else would have forced the repaint either.
      old.sweepColor != sweepColor ||
      old.northMarker != northMarker;
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.model, required this.skin});
  final DashboardModel model;
  final MmSkin skin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(skin.space.screenEdge, skin.space.rowInset, skin.space.rowGap, skin.space.labelToControl),
      child: Row(
        children: <Widget>[
          // Title + channel take the remaining space and ellipsize, so
          // the fixed trailing controls never get squeezed into overflow.
          // The channel is the one fact this bar carries; the skin name was
          // a second title for a screen the strip already names.
          Expanded(
            child: Text('◦ ${model.channelLabel}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: skin.color.accent,
                    fontFamily: skin.type.monoFamily,
                    fontSize: context.skin.type.sizeBody)),
          ),
          SizedBox(width: skin.space.rowGap),
          Container(
            padding:
                EdgeInsets.symmetric(horizontal: skin.space.rowGap, vertical: skin.space.insideText),
            decoration: BoxDecoration(
              color: (model.alert
                      ? skin.color.alert
                      : (model.linked ? skin.color.link : skin.color.ok))
                  .withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(model.statusLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: model.alert
                        ? skin.color.alert
                        : (model.linked ? skin.color.link : skin.color.ok),
                    fontFamily: skin.type.monoFamily,
                    fontSize: skin.type.sizeMicro,
                    letterSpacing: 1)),
          ),
          const MmAudioToggle(),
          IconButton(
            tooltip: 'BLE',
            icon: Icon(Icons.bluetooth,
                size: 20,
                color: model.alert ? skin.color.alert : skin.color.accent),
            onPressed: () => context.push('/settings/connection'),
          ),
        ],
      ),
    );
  }
}

/// A one-line "most recent activity" ticker above the status rail — fills
/// the quiet-field space below the radar with the latest mesh event.
class _ActivityTicker extends StatelessWidget {
  const _ActivityTicker({required this.model, required this.skin});
  final DashboardModel model;
  final MmSkin skin;

  @override
  Widget build(BuildContext context) {
    final ({String time, String text}) e = model.events.first;
    return Padding(
      padding: EdgeInsets.fromLTRB(skin.space.screenEdge, skin.space.insideText, skin.space.screenEdge, skin.space.labelToControl),
      child: Row(
        children: <Widget>[
          Icon(Icons.bolt, size: 13, color: skin.color.accent),
          SizedBox(width: skin.space.labelToControl),
          Text(e.time,
              style: TextStyle(
                  color: skin.color.fgMuted,
                  fontFamily: skin.type.monoFamily,
                  fontSize: skin.type.sizeSm)),
          SizedBox(width: skin.space.rowGap),
          Expanded(
            child: Text(e.text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: skin.color.fg,
                    fontFamily: skin.type.monoFamily,
                    fontSize: skin.type.sizeSm)),
          ),
        ],
      ),
    );
  }
}

class _StatusRail extends StatelessWidget {
  const _StatusRail(
      {required this.model,
      required this.mc,
      required this.skin,
      required this.l});
  final DashboardModel model;
  final MeshcoreController mc;
  final MmSkin skin;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    double? bestSnr;
    for (final DiscoveredNode n in mc.nodes) {
      final double? s = n.snrDb;
      if (s != null) bestSnr = (bestSnr == null) ? s : math.max(bestSnr, s);
    }
    final List<({String k, String v})> cells = <({String k, String v})>[
      (k: l.dashPeers, v: '${model.peersInRange}'),
      (k: model.channelLabel, v: '·'),
      if (model.contactsLabel != null)
        (k: l.dashContacts, v: model.contactsLabel!),
      if (model.batteryLine != null) (k: 'BATT', v: model.batteryLine!),
      if (bestSnr != null) (k: 'SNR', v: '${bestSnr.toStringAsFixed(0)}dB'),
    ];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(skin.space.screenEdge, skin.space.rowGap, skin.space.screenEdge, skin.space.sectionGap),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: skin.color.line, width: 1)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 6,
        children: <Widget>[
          // A table, not a sentence. These were `'label value'` in one
          // RichText with a single space between them, so every figure sat one
          // space after its own label and the column of values was ragged. A
          // table with an intrinsic label column and a flexible value column
          // puts every value on the panel's right edge, which is the rule the
          // other dashboards follow, and it needs no width of its own.
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
            },
            children: <TableRow>[
              for (final ({String k, String v}) c in cells)
                TableRow(children: <Widget>[
                  Padding(
                    padding: EdgeInsets.only(right: skin.space.rowGap),
                    child: Text(
                      c.k,
                      style: TextStyle(
                          fontFamily: skin.type.wordsMono,
                          color: skin.color.fgMuted,
                          fontSize: skin.type.sizeMicro,
                          letterSpacing: 1),
                    ),
                  ),
                  Text(
                    c.v,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontFamily: skin.type.monoFamily,
                        color: skin.color.fg,
                        fontSize: skin.type.sizeBody),
                  ),
                ]),
            ],
          ),
          // Own pubkey — needed by anyone who wants to add you as a
          // contact before their DMs can route.
          MyPubkeyLine(
            pubKeyHex: model.pubKeyHex,
            style: TextStyle(
                fontFamily: skin.type.monoFamily,
                fontSize: skin.type.sizeBody,
                color: skin.color.fg),
            shownChars: 12,
          ),
        ],
      ),
    );
  }
}

/// Where a peer sits on the dial when the app has no distance for it.
///
/// The radius is a *band* per proximity, and each node takes its own place
/// inside the band. One value per band put every peer the radio had no position
/// for on a single circle — on the handset 196 of them drew as a clean ring
/// around the rim, which reads as a rendering fault rather than as a reading.
/// `unknown` is spread across the whole dial because that is exactly what is
/// known about it, and every other band stays inside itself so the proximity
/// still means something.
@visibleForTesting
double radarPlaceholderFraction(
  NodeProximity prox,
  String pubKey,
  double Function(String key, int seed) hashUnit,
) {
  final (double start, double width) band = switch (prox) {
    NodeProximity.near => (0.16, 0.22),
    NodeProximity.recent => (0.32, 0.24),
    NodeProximity.mid => (0.52, 0.24),
    NodeProximity.far => (0.74, 0.22),
    NodeProximity.unknown => (0.22, 0.72),
  };
  return (band.$1 + hashUnit(pubKey, 1) * band.$2).clamp(0.08, 0.97);
}

/// One callout line, ellipsised at [maxWidth].
///
/// A top-level function rather than a method so the two properties that matter
/// can be asserted without a canvas: the size it draws at is the size it was
/// given, and a name too long for the gutter is cut by the text engine at the
/// gutter's edge rather than by a character-count guess. The guess is what the
/// radar used until 2026-11-11, and it was wrong by the whole scale factor as
/// soon as the text grew.
@visibleForTesting
TextPainter radarCalloutPainter({
  required String text,
  required double size,
  required String monoFamily,
  required Color color,
  double? maxWidth,
}) =>
    TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: color,
            fontSize: size,
            fontFamily: monoFamily,
            fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '\u2026',
    )..layout(maxWidth: maxWidth ?? double.infinity);

/// The two sizes the dial draws its own text at, taken from the skin.
///
/// A function rather than two fields so the rule is assertable: the radar's
/// labels come from the same scale as everything else and never from a literal,
/// which is what they did until 2026-11-11 (11.5 for a name, 10 for the north
/// letter), leaving the dial as the one surface that ignored the font setting.
/// [textScale] is the user's own text size, which a painter cannot read for
/// itself. It multiplies both sizes, so the dial's names grow with the setting
/// like every other label in the app: they were the one surface that did not.
@visibleForTesting
({double callout, double north}) radarLabelSizes(MmType type,
        {double textScale = 1}) =>
    (callout: type.sizeSm * textScale, north: type.sizeMicro * textScale);
