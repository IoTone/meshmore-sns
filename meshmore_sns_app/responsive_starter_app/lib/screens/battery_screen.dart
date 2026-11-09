// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_scaffold.dart';
import '../ui/mm_confirm.dart';
import '../meshcore/battery_model.dart';
import '../meshcore/device_power_specs.dart';
import '../meshcore/meshcore_controller.dart';
import '../ui/mm_shape.dart';

/// Battery-life analysis for the connected device.
///
/// The companion protocol only reports pack voltage, so this screen
/// turns voltage-over-time into a runtime estimate: state-of-charge
/// from the device's OCV curve, observed drain via regression of the
/// persisted history, and a nameplate cross-check from the matched
/// device spec. Honest about uncertainty — every figure carries its
/// method + confidence.
class BatteryScreen extends StatelessWidget {
  const BatteryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final BatteryEstimate est = mc.batteryEstimate;
    final DevicePowerSpec spec = mc.resolvedPowerSpec;
    final List<BatterySample> history = mc.batteryHistory;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.batteryTitle),
        actions: <Widget>[
          if (history.isNotEmpty)
            IconButton(
              tooltip: l.batteryReset,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmReset(context, mc, l),
            ),
        ],
      ),
      body: MmScaffold(
        child: !est.hasData
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(context.skin.space.emptyState),
                child: Text(
                  l.batteryAwaiting,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          : ListView(
              padding: context.skin.space.padScreen,
              children: <Widget>[
                _GaugeRow(est: est, l: l, cs: cs),
                SizedBox(height: context.skin.space.sectionGap),
                _EstimateCard(est: est, l: l, cs: cs),
                SizedBox(height: context.skin.space.sectionGap),
                if (history.length >= 2) ...<Widget>[
                  _SectionLabel(l.batteryHistoryTitle, cs: cs),
                  SizedBox(height: context.skin.space.rowGap),
                  _HistorySparkline(
                      history: history, spec: spec, cs: cs, l: l),
                  SizedBox(height: context.skin.space.sectionGap),
                ],
                _SectionLabel(l.batterySpecTitle, cs: cs),
                SizedBox(height: context.skin.space.rowGap),
                _SpecCard(spec: spec, l: l, cs: cs),
              ],
            ),
      ),
    );
  }

  Future<void> _confirmReset(
      BuildContext context, MeshcoreController mc, AppLocalizations l) async {
    final bool ok = await mmConfirm(
      context,
      title: l.batteryReset,
      body: l.batteryResetConfirm,
      cancelLabel: l.actionCancel,
      confirmLabel: l.batteryReset,
      // The samples are gone once reset, and the estimate has to re-learn.
      destructive: true,
    );
    if (ok) await mc.resetBatteryHistory();
  }
}

/// SoC ring gauge + voltage / charging readout.
class _GaugeRow extends StatelessWidget {
  const _GaugeRow({required this.est, required this.l, required this.cs});
  final BatteryEstimate est;
  final AppLocalizations l;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final double soc = est.socPercent.clamp(0, 100);
    final Color ringColor = _socColor(soc, skin);
    return Row(
      children: <Widget>[
        SizedBox.square(
          // Four empty-state steps: the gauge is the one number the screen
          // exists for, and a fixed 132 was neither a step nor a role.
          dimension: skin.space.step(9) * 4,
          child: CustomPaint(
            painter: _GaugePainter(
              soc: soc,
              color: ringColor,
              // On paper an outline at 25 % is invisible, so the empty part of
              // the ring vanished and a 60 % battery looked full. The rule tier
              // is the colour a track is drawn in.
              track: skin.color.line,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${soc.round()}',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: skin.type.sizeHero,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  Text('%',
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: skin.type.sizeBodyLg)),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: skin.space.sectionGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SectionLabel(l.batteryVoltageLabel, cs: cs),
              SizedBox(height: skin.space.insideText),
              Text(
                '${est.volts.toStringAsFixed(2)} V',
                style: TextStyle(
                    color: cs.onSurface,
                    fontSize: skin.type.sizeXl,
                    fontFamily: skin.type.monoFamily),
              ),
              SizedBox(height: skin.space.rowInset),
              if (est.charging == true)
                Row(
                  children: <Widget>[
                    Icon(Icons.bolt, size: 16, color: cs.tertiary),
                    SizedBox(width: skin.space.labelToControl),
                    Text(l.batteryCharging,
                        style: TextStyle(
                            color: cs.tertiary,
                            fontWeight: FontWeight.w600)),
                  ],
                )
              else
                Text(
                  _methodLabel(est.method, l),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Time-to-empty + drain + confidence + the "why" line.
class _EstimateCard extends StatelessWidget {
  const _EstimateCard({required this.est, required this.l, required this.cs});
  final BatteryEstimate est;
  final AppLocalizations l;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(skin.space.screenEdge),
      decoration: BoxDecoration(
        // A panel on paper is defined by its rule, not by a tint: a fill at
        // 40 % and a border at 35 % both vanish there, which left the card's
        // content floating with no edge.
        color: skin.color.surface,
        borderRadius: mmRadius(context, kRadiusMd),
        border:
            Border.all(color: skin.color.edge, width: skin.shape.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionLabel(l.batteryTimeToEmpty, cs: cs),
          SizedBox(height: skin.space.labelToControl),
          if (est.charging == true)
            Text(l.batteryChargingNote,
                style:
                    TextStyle(color: cs.onSurface, fontSize: skin.type.sizeLg))
          else if (est.timeToEmpty != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  _fmtDuration(est.timeToEmpty!, l),
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: skin.type.sizeTitle,
                      fontWeight: FontWeight.w700),
                ),
                SizedBox(width: skin.space.rowGap),
                _ConfidenceBadge(confidence: est.confidence, l: l, cs: cs),
              ],
            )
          else
            Text(l.batteryEstimating,
                style: TextStyle(color: cs.onSurfaceVariant)),
          SizedBox(height: skin.space.rowInset),
          if (est.drainPctPerHour != null)
            _kv(context, l.batteryDrainRate,
                '${est.drainPctPerHour!.toStringAsFixed(1)} %/h', cs),
          if (est.method == BatteryMethod.observed &&
              est.observationSpan.inMinutes > 0)
            _kv(context, l.batteryBasis,
                l.batteryBasisObserved(_fmtDuration(est.observationSpan, l)),
                cs),
          if (est.method == BatteryMethod.rated)
            _kv(context, l.batteryBasis, l.batteryBasisRated, cs),
          // No second "gathering" caption here: with no estimate and no
          // method the headline branch above already says it (the card
          // used to print the same sentence twice).
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, ColorScheme cs) =>
      Padding(
        padding:
            EdgeInsets.symmetric(vertical: context.skin.space.insideText),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(k, style: TextStyle(color: cs.onSurfaceVariant)),
            Text(v,
                style: TextStyle(
                    color: cs.onSurface, fontFamily: 'JetBrains Mono')),
          ],
        ),
      );
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge(
      {required this.confidence, required this.l, required this.cs});
  final BatteryConfidence confidence;
  final AppLocalizations l;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    if (confidence == BatteryConfidence.none) return const SizedBox.shrink();
    final (String, Color) v = switch (confidence) {
      BatteryConfidence.high => (l.batteryConfHigh, cs.tertiary),
      BatteryConfidence.medium => (l.batteryConfMedium, cs.primary),
      BatteryConfidence.low => (l.batteryConfLow, cs.onSurfaceVariant),
      BatteryConfidence.none => ('', cs.onSurfaceVariant),
    };
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.skin.space.rowGap,
          vertical: context.skin.space.insideText),
      decoration: BoxDecoration(
        color: v.$2.withValues(alpha: .15),
        borderRadius: mmRadius(context, kRadiusSm),
        // Full strength: a badge's edge at 50 % is 1.6:1 on paper, which is
        // the difference between a badge and a floating word.
        border: Border.all(color: v.$2),
      ),
      child: Text(
        '${l.batteryConfidence}: ${v.$1}',
        style: TextStyle(
            color: v.$2,
            fontSize: context.skin.type.sizeSm,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Matched device spec card, or the generic-fallback note.
class _SpecCard extends StatelessWidget {
  const _SpecCard({required this.spec, required this.l, required this.cs});
  final DevicePowerSpec spec;
  final AppLocalizations l;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final String capacity = spec.capacityMah > 0
        ? l.batterySpecCapacity(spec.capacityMah)
        : l.batterySpecCapacityUnknown;
    final double? rx = spec.currentMa['rx'] ?? spec.currentMa['idle'];
    final MmSkin skin = context.skin;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(skin.space.screenEdge),
      decoration: BoxDecoration(
        color: skin.color.surface,
        borderRadius: mmRadius(context, kRadiusMd),
        border:
            Border.all(color: skin.color.line, width: skin.shape.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(spec.isGeneric ? Icons.help_outline : Icons.memory,
                  size: 18, color: cs.primary),
              SizedBox(width: skin.space.rowGap),
              Expanded(
                child: Text(spec.label,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontSize: skin.type.sizeLg,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          SizedBox(height: skin.space.rowGap),
          if (spec.isGeneric)
            Text(l.batterySpecGeneric,
                style: TextStyle(
                    color: cs.onSurfaceVariant, height: 1.4))
          else ...<Widget>[
            Text('$capacity  ·  ${spec.chemistry.toUpperCase()}  ·  '
                '${spec.fullVolts.toStringAsFixed(2)}–'
                '${spec.emptyVolts.toStringAsFixed(2)} V',
                style: TextStyle(
                    color: cs.onSurface, fontFamily: 'JetBrains Mono')),
            if (rx != null)
              Padding(
                padding: EdgeInsets.only(top: skin.space.labelToControl),
                child: Text(
                    l.batterySpecDraw(rx.round()),
                    style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontFamily: context.skin.type.wordsMono)),
              ),
            if (spec.notes != null)
              Padding(
                padding: EdgeInsets.only(top: skin.space.rowGap),
                child: Text(spec.notes!,
                    style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: skin.type.sizeBody,
                        height: 1.4)),
              ),
          ],
        ],
      ),
    );
  }
}

/// Voltage history mini-chart over the retained window.
class _HistorySparkline extends StatelessWidget {
  const _HistorySparkline(
      {required this.history,
      required this.spec,
      required this.cs,
      required this.l});
  final List<BatterySample> history;
  final DevicePowerSpec spec;
  final ColorScheme cs;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final int span = history.last.atUnix - history.first.atUnix;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          // The chart's height, expressed from the ladder so it moves with the
          // spacing scale rather than being a private 96.
          height: context.skin.space.step(8) * 4,
          width: double.infinity,
          child: CustomPaint(
            painter: _SparkPainter(
              history: history,
              line: cs.primary,
              fill: cs.primary.withValues(alpha: .12),
              // The chart's own grid: a hairline, which is visible on paper
              // where an outline at 20 % is not.
              grid: context.skin.color.hairline,
            ),
          ),
        ),
        SizedBox(height: context.skin.space.labelToControl),
        Text(
          l.batteryHistorySpan(_fmtDuration(Duration(seconds: span), l),
              history.length),
          style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: context.skin.type.sizeSm),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.cs});
  final String text;
  final ColorScheme cs;
  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    return Text(
      skin.type.upperHeadings ? text.toUpperCase() : text,
      style: TextStyle(
          color: cs.primary,
          fontSize: skin.type.sizeSm,
          letterSpacing: skin.type.headingTracking),
    );
  }
}

/// The gauge's colour, from the skin's own roles.
///
/// It used to be two literals — a red and an amber — tuned on a dark ground.
/// On paper the amber is 1.9:1, so the ring for a 30 % pack disappeared. The
/// roles carry both meanings on every ground: `alert` is danger, `warn` is
/// caution, and the skin's accent is the ordinary case.
Color _socColor(double soc, MmSkin skin) {
  if (soc <= 15) return skin.color.alert;
  if (soc <= 35) return skin.color.warn;
  return skin.color.accent;
}

String _methodLabel(BatteryMethod m, AppLocalizations l) => switch (m) {
      BatteryMethod.observed => l.batteryMethodObserved,
      BatteryMethod.rated => l.batteryMethodRated,
      BatteryMethod.charging => l.batteryCharging,
      BatteryMethod.none => l.batteryMethodNone,
    };

String _fmtDuration(Duration d, AppLocalizations l) {
  final int days = d.inDays;
  final int hours = d.inHours % 24;
  final int mins = d.inMinutes % 60;
  if (days > 0) return l.batteryDurDH(days, hours);
  if (d.inHours > 0) return l.batteryDurHM(d.inHours, mins);
  return l.batteryDurM(d.inMinutes);
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(
      {required this.soc, required this.color, required this.track});
  final double soc;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = math.min(size.width, size.height) / 2 - 8;
    const double startAngle = math.pi * 0.75; // bottom-left
    const double sweepTotal = math.pi * 1.5; // 270° arc
    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r), startAngle, sweepTotal,
        false, base);
    final Paint fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), startAngle,
        sweepTotal * (soc / 100).clamp(0, 1), false, fg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.soc != soc || old.color != color;
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(
      {required this.history,
      required this.line,
      required this.fill,
      required this.grid});
  final List<BatterySample> history;
  final Color line;
  final Color fill;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2) return;
    final int t0 = history.first.atUnix;
    final int t1 = history.last.atUnix;
    final int tSpan = math.max(1, t1 - t0);
    int minMv = history.first.millivolts;
    int maxMv = history.first.millivolts;
    for (final BatterySample s in history) {
      if (s.millivolts < minMv) minMv = s.millivolts;
      if (s.millivolts > maxMv) maxMv = s.millivolts;
    }
    // Pad the voltage range so a flat trace isn't a hairline at the edge.
    final double pad = math.max(20, (maxMv - minMv) * 0.15);
    final double lo = minMv - pad;
    final double hi = maxMv + pad;
    final double vSpan = math.max(1, hi - lo);

    double x(int t) => (t - t0) / tSpan * size.width;
    double y(int mv) => size.height - (mv - lo) / vSpan * size.height;

    // Baseline grid.
    final Paint g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (int i = 1; i < 3; i++) {
      final double yy = size.height * i / 3;
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), g);
    }

    final Path path = Path()
      ..moveTo(x(history.first.atUnix), y(history.first.millivolts));
    for (final BatterySample s in history.skip(1)) {
      path.lineTo(x(s.atUnix), y(s.millivolts));
    }
    final Path area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = line);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.history.length != history.length ||
      (history.isNotEmpty &&
          old.history.isNotEmpty &&
          old.history.last.atUnix != history.last.atUnix);
}
