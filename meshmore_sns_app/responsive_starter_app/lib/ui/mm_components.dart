// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/mm_skin.dart';
import 'mm_shape.dart';

/// The inner padding of a [MmPanel]. Its own token rather than a spacing step:
/// 14 sits between the ladder's 12 and 16, and every panel in the app uses it,
/// so rounding it to a step would move the whole layout by 2 px.
const double kPadPanel = 14;

/// A framed surface panel whose edge treatment (sharp / rounded /
/// chamfered) comes from the active skin. The NERV concept renders this
/// as a chamfered HUD panel; SEELE as a plain sharp slab.
class MmPanel extends StatelessWidget {
  const MmPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(kPadPanel),
    this.fill,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final OutlinedBorder border = mmShapeBorder(
      skin.shape,
      side: BorderSide(
          color: skin.color.line, width: skin.shape.borderWidth),
    );
    return Container(
      decoration:
          ShapeDecoration(color: fill ?? skin.color.surface, shape: border),
      padding: padding,
      child: child,
    );
  }
}

/// The label style shared by [MmSectionHeader] and
/// `MmCollapsibleSection`, so there is exactly one section-label idiom.
TextStyle mmSectionLabelStyle(MmSkin skin) => TextStyle(
      // R68: Studio's labels are words, so they use the UI face (null =
      // the theme default); the other skins keep their heading/mono face.
      fontFamily: skin.type.sansLabels
          ? null
          : (skin.type.headingFamily ?? skin.type.monoFamily),
      color: skin.color.fgMuted,
      fontSize: skin.type.sizeSm,
      letterSpacing: skin.type.headingTracking,
      fontWeight: FontWeight.w700,
    );

/// A section header — a tracked, optionally uppercase label. Loud
/// concepts (NERV) extend it with a diagonal **hazard-stripe** bar;
/// calm ones (SEELE) render just the label.
class MmSectionHeader extends StatelessWidget {
  const MmSectionHeader(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final Widget labelWidget = Text(
      skin.type.upperHeadings ? label.toUpperCase() : label,
      style: mmSectionLabelStyle(skin),
    );
    // The label is the one unbounded child: at 200 % text a heading like
    // "PERMISSIONS AND WHY" is wider than a 320 dp phone, and a bare Row
    // overflowed by 370 px instead of wrapping.
    return Row(
      children: <Widget>[
        Flexible(child: labelWidget),
        if (skin.ornament.warningStripes) ...<Widget>[
          const SizedBox(width: 10),
          Expanded(
            child: CustomPaint(
              painter: _HazardStripes(skin.color.accent, skin.color.line),
              child: const SizedBox(height: 9),
            ),
          ),
          const SizedBox(width: 8),
        ] else
          const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _HazardStripes extends CustomPainter {
  _HazardStripes(this.stripe, this.gap);
  final Color stripe;
  final Color gap;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = gap.withValues(alpha: .4));
    final Paint p = Paint()..color = stripe.withValues(alpha: .55);
    const double w = 6, step = 12;
    for (double x = -size.height; x < size.width; x += step) {
      final Path path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + size.height, 0)
        ..lineTo(x + size.height + w, 0)
        ..lineTo(x + w, size.height)
        ..close();
      canvas.save();
      canvas.clipRect(Offset.zero & size);
      canvas.drawPath(path, p);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_HazardStripes old) =>
      old.stripe != stripe || old.gap != gap;
}

/// A labelled telemetry readout — `LABEL value` in the skin's mono
/// face. The workhorse for HUD-style data lines.
class MmReadout extends StatelessWidget {
  const MmReadout({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final Color? valueColor;

  /// Render the value larger (a hero figure within a panel).
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        // Flexible, not fixed: at the accessibility floor a label in caps is
        // wider than a 320 dp screen on its own, and a fixed child in a Row
        // cannot give the width back (it overflowed by 96 px on NERV).
        Flexible(
          child: Text(
            skin.type.upperHeadings ? label.toUpperCase() : label,
            style: TextStyle(
              fontFamily: skin.type.wordsMono,
              color: skin.color.fgMuted,
              fontSize: skin.type.sizeBody,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: skin.type.monoFamily,
              color: valueColor ?? skin.color.fg,
              fontSize:
                  emphasize ? skin.type.size(18) : skin.type.sizeBodyLg,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              fontFeatures: skin.type.slashedZero
                  ? const <FontFeature>[FontFeature.slashedZero()]
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// A list row whose container reskins with the active skin: loud
/// concepts (NERV, chamfer/ornament) render each row as a framed
/// **panel card**; calm ones (SEELE) render a flat row with a hairline
/// rule — same content, different identity, no per-screen fork. Drop-in
/// for `ListTile` (leading / title / subtitle / trailing / onTap).
class MmListRow extends StatelessWidget {
  const MmListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.alignTop = false,
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// R102 — align the leading icon and the trailing column with the first
  /// line instead of the middle of the row. A node row is two or three lines
  /// tall; centring the icon and the age made both float halfway down the
  /// text block.
  final bool alignTop;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final Widget content = Row(
      crossAxisAlignment:
          alignTop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: <Widget>[
        if (leading != null)
          Padding(padding: const EdgeInsets.only(right: 12), child: leading!),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DefaultTextStyle.merge(
                style: TextStyle(color: skin.color.fg),
                child: title,
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: subtitle!,
                ),
            ],
          ),
        ),
        if (trailing != null)
          Padding(padding: const EdgeInsets.only(left: 8), child: trailing!),
      ],
    );

    final bool card =
        skin.shape.corner != MmCorner.sharp || skin.ornament.any;
    if (card) {
      return MmPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: InkWell(onTap: onTap, child: content),
      );
    }
    // Calm/flat: a plain tappable row with a bottom hairline.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: skin.color.line)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: content,
        ),
      ),
    );
  }
}

/// A small status pill (app-bar / header chip) — dot + tracked label,
/// inverting to the alert colour when [alert].
class MmStatusPill extends StatelessWidget {
  const MmStatusPill(this.label, {super.key, this.alert = false});

  final String label;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final Color fg = alert ? skin.color.alert : skin.color.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        shape: mmShapeBorder(
          MmShape(
              corner: skin.shape.corner == MmCorner.chamfer
                  ? MmCorner.chamfer
                  : MmCorner.rounded,
              cornerSize: math.min(skin.shape.cornerSize, 6),
              borderWidth: 1),
          side: BorderSide(color: fg.withValues(alpha: .5)),
        ),
      ),
      child: Text(
        skin.type.upperHeadings ? label.toUpperCase() : label,
        style: TextStyle(
          fontFamily: skin.type.wordsMono,
          color: fg,
          fontSize: skin.type.sizeMicro,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// R99 — a text-shaped action that still reads as a control. Material's
/// `TextButton` on this app's ground is indistinguishable from a label
/// (Connect, Retry, Configure, Details, Load from device, Set name), which is
/// how the owner ended up pressing text that did not look pressable. An
/// [MmAction] keeps the text-sized footprint but puts the label on
/// `surfaceAlt`, one tonal step above the page, inside a hairline border in
/// the skin's own corner shape — so it generalises to every preset without a
/// per-theme fork. Minimum height 44 dp, 12/8 padding, optional leading icon.
class MmAction extends StatelessWidget {
  const MmAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Compact vertical padding for a control that sits inside a dense row.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final bool on = onPressed != null;
    final Color fg = on ? skin.color.fg : skin.color.fgMuted;
    final OutlinedBorder border = mmShapeBorder(
      skin.shape,
      side: BorderSide(
          color: on ? skin.color.line : skin.color.line.withValues(alpha: .5),
          width: skin.shape.borderWidth),
    );
    return Semantics(
      button: true,
      enabled: on,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          customBorder: border,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: EdgeInsets.symmetric(
                horizontal: 12, vertical: dense ? 6 : 9),
            decoration: ShapeDecoration(
              color: on
                  ? skin.color.surfaceAlt
                  : skin.color.surfaceAlt.withValues(alpha: .4),
              shape: border,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(label,
                    style: TextStyle(
                        color: fg,
                        fontSize: skin.type.sizeBodyLg,
                        letterSpacing: .4,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One entry in [showMmPicker]: a group label or a choice.
class MmPickerItem<T> {
  const MmPickerItem.header(this.label)
      : value = null,
        icon = null,
        isHeader = true;
  const MmPickerItem.option(this.value, this.label, {this.icon})
      : isHeader = false;

  final T? value;
  final String label;
  final IconData? icon;
  final bool isHeader;
}

/// R104 — the one pick-one-of-N surface. `PopupMenuButton` is not scrollable,
/// does not announce its group labels to a screen reader, and its checkmarks
/// sit in a menu that the framework positions away from the control. This is
/// a labelled sheet with 48 dp rows and the current value ticked, used by the
/// grid's view, interval and range pickers.
Future<T?> showMmPicker<T>({
  required BuildContext context,
  required String title,
  required List<MmPickerItem<T>> items,
  required T? current,
}) {
  final MmSkin skin = context.skinRead;
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext c) => SafeArea(
      top: false,
      // A shrink-wrapped list, not a Column with a Flexible body: inside the
      // sheet the Column's `mainAxisSize.min` gave the flexible child a
      // zero-height viewport, so the rows were built but painted outside the
      // sheet and could not be tapped. This sizes to the content and scrolls
      // only when the content is taller than the screen.
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
                skin.space.step(7), skin.space.step(2), skin.space.step(7),
                skin.space.step(3)),
            child: Text(title,
                style: TextStyle(
                    color: skin.color.fgMuted,
                    fontSize: skin.type.sizeSm,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600)),
          ),
          for (final MmPickerItem<T> it in items)
            if (it.isHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Text(it.label,
                    style: TextStyle(
                        color: skin.color.fgMuted,
                        fontSize: skin.type.sizeSm,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600)),
              )
            else
              InkWell(
                onTap: () => Navigator.pop<T>(c, it.value),
                child: SizedBox(
                  height: 48,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: skin.space.step(7)),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 28,
                          child: it.value == current
                              ? Icon(Icons.check,
                                  size: 18, color: skin.color.accent)
                              : null,
                        ),
                        if (it.icon != null) ...<Widget>[
                          Icon(it.icon, size: 18, color: skin.color.fgMuted),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(it.label,
                              style: TextStyle(
                                  color: skin.color.fg,
                                  fontSize: skin.type.size(15),
                                  fontWeight: it.value == current
                                      ? FontWeight.w600
                                      : FontWeight.w400)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    ),
  );
}
