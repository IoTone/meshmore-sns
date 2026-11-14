// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/mm_skin.dart';
import 'mm_shape.dart';

/// The inner padding of a [MmPanel]: [MmSpace.rowInset], the compact-panel
/// inset. It is deliberately a ladder step — it used to be 14, which sat
/// between the ladder's 12 and 16 and made every panel 2 px off the rhythm the
/// rest of the app is built on.
const double kPadPanel = 12;

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
          color: skin.color.edge, width: skin.shape.borderWidth),
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
    final String shown =
        skin.type.upperHeadings ? label.toUpperCase() : label;
    final Widget labelWidget = Text(shown, style: mmSectionLabelStyle(skin));
    // The label is the content and the ornament is not, so the label takes
    // every pixel the ornament and the controls leave. Two earlier shapes got
    // this wrong and both were measured:
    //
    // - As two `Flexible`s the row split the free space evenly, so the stripes
    //   *reserved* half of it and used 64 dp of their share: on a 320 dp phone
    //   at 2.0 text the heading got 96 dp and "LINK" — which needs 100 — broke
    //   into two lines while 32 dp sat unused beside it.
    // - With `Spacer()` in the non-striped branch the label and the spacer were
    //   both flexible, so every calm skin gave its heading half the row.
    //
    // The label is `Expanded` now and the stripes are a fixed 64 dp that only
    // appears while the heading and a control both still fit.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final TextPainter p = TextPainter(
          text: TextSpan(text: shown, style: mmSectionLabelStyle(skin)),
          textDirection: Directionality.of(context),
          maxLines: 1,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final double need = p.width;
        p.dispose();
        // Two ladder steps of stripes and their two 8 dp gaps, plus 48 dp for
        // whatever control sits in the trailing slot. Below that the ornament is
        // what goes, because the heading is the reason the row exists.
        final double stripeWidth = skin.space.step(9) * 2;
        final bool ornament = skin.ornament.warningStripes &&
            c.maxWidth >= need + stripeWidth + 16 + 48;
        return Row(
          children: <Widget>[
            Expanded(child: labelWidget),
            if (ornament) ...<Widget>[
              const SizedBox(width: 8),
              SizedBox(
                width: stripeWidth,
                child: CustomPaint(
                  painter: _HazardStripes(skin.color.accent, skin.color.line),
                  child: const SizedBox(height: 8),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (trailing != null) trailing!,
          ],
        );
      },
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
    final String shown =
        skin.type.upperHeadings ? label.toUpperCase() : label;
    final TextStyle labelStyle = TextStyle(
      fontFamily: skin.type.wordsMono,
      color: skin.color.fgMuted,
      fontSize: skin.type.sizeBody,
      letterSpacing: 1,
    );
    final Widget labelText = Text(
      shown,
      style: labelStyle,
      // A readout is a label and a figure on one line. Left free, the label
      // wrapped the moment it was a character too wide — measured on NERV at
      // 411 dp and 1.0 text, "NODES IN RANGE" broke into two lines beside a
      // value that stayed on one, and the row read as a ragged pair rather
      // than a reading.
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final Widget valueText = Text(
      value,
      textAlign: TextAlign.right,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: skin.type.monoFamily,
        color: valueColor ?? skin.color.fg,
        fontSize: emphasize ? skin.type.size(18) : skin.type.sizeBodyLg,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        fontFeatures: skin.type.slashedZero
            ? const <FontFeature>[FontFeature.slashedZero()]
            : null,
      ),
    );
    // When the two cannot share a line they stop sharing one: the label takes
    // its own line and the value follows it, right-aligned so the figures still
    // line up down the panel. Measured with the real painter rather than
    // guessed, so the switch happens exactly where the label would otherwise
    // have been truncated.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final TextPainter p = TextPainter(
          text: TextSpan(text: shown, style: labelStyle),
          textDirection: Directionality.of(context),
          maxLines: 1,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final bool fits = p.width + 8 + _valueMinWidth <= c.maxWidth;
        p.dispose();
        if (fits) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              // Flexible, not fixed: at the accessibility floor a label in caps
              // is wider than a 320 dp screen on its own, and a fixed child in
              // a Row cannot give the width back (it overflowed by 96 px on
              // NERV).
              Flexible(child: labelText),
              const SizedBox(width: 8),
              Expanded(child: valueText),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[labelText, valueText],
        );
      },
    );
  }

  /// The narrowest a value is given before the label gives up its line.
  static const double _valueMinWidth = 56;
}

/// A technical value made of fields, laid out where its separators are.
///
/// A position read out as `38.91996, -104.77315 · alt 2041 m · device` is four
/// facts. Left to wrap on its own it breaks wherever the width runs out — with
/// the tracking the skins apply, often mid-number — so "‑104.77" ends a line and
/// "315" starts the next, and a reader has to reassemble a coordinate.
///
/// This lays the fields out on one line when the whole value fits, and one
/// field per line when it does not. The measurement is the real text painter at
/// the real style, so it decides at the text floor rather than by a character
/// count, and the same call is a single line on a tablet.
class MmValueFields extends StatelessWidget {
  const MmValueFields({
    super.key,
    required this.fields,
    this.separator = ' · ',
    this.color,
    this.mono = true,
  });

  final List<String> fields;

  /// What sits between two fields when they share a line. The glyph is part of
  /// the value, so it is a parameter rather than an assumption.
  final String separator;

  final Color? color;

  /// Machine data is mono; a value that is prose can opt out.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final TextStyle style = TextStyle(
      fontFamily: mono ? skin.type.monoFamily : skin.type.wordsMono,
      color: color ?? skin.color.fg,
      fontSize: skin.type.sizeBodyLg,
      letterSpacing: 0.5,
      fontFeatures:
          skin.type.slashedZero ? const <FontFeature>[FontFeature.slashedZero()] : null,
    );
    final String joined = fields.join(separator);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final TextPainter painter = TextPainter(
          text: TextSpan(text: joined, style: style),
          textDirection: Directionality.of(context),
          maxLines: 1,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final bool fits = painter.width <= c.maxWidth;
        painter.dispose();
        if (fits) return Text(joined, style: style);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final String f in fields) Text(f, style: style),
          ],
        );
      },
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
          Padding(padding: const EdgeInsets.only(right: 8), child: leading!),
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
                  padding: const EdgeInsets.only(top: 2),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

/// A row that opens a picker, with the current value where a value belongs.
///
/// A `ListTile` whose current choice sits in the `subtitle` slot reads as a
/// two-line description: nothing in it says "this opens a choice". Putting the
/// value in the trailing slot beside a chevron says both things at once, and
/// matches every other navigable row in the app.
class MmPickerTile extends StatelessWidget {
  const MmPickerTile({
    super.key,
    required this.title,
    required this.value,
    required this.onTap,
    this.leading,
    this.enabled = true,
    this.hint,
  });

  final String title;

  /// The current choice, in the trailing slot.
  final String value;
  final VoidCallback? onTap;
  final Widget? leading;
  final bool enabled;

  /// Optional one-line explanation, kept in the subtitle slot because it is not
  /// a value.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final bool on = enabled && onTap != null;
    final Color valueColor = on ? skin.color.accent : skin.color.fgMuted;
    // Material's own disabled ink is `onSurface` at 38 %, which on a paper
    // ground is 1.8:1: the row's own sentence disappears and only the trailing
    // value survives. Both tiers are stated from the tokens instead, so a row
    // you cannot open still says what it is.
    final Color textColor = on ? skin.color.fg : skin.color.fgDisabled;
    final Color subColor = on ? skin.color.fgMuted : skin.color.fgDisabled;
    // The styles are named rather than left to the tile, so the measurement
    // below and the paint above cannot disagree: the trailing value used to be
    // capped at a flat 160 dp and ellipsised past it, which is the cap that
    // turned "Every 15 min" into "Every 15…" at 200 % text.
    final TextStyle titleStyle =
        (Theme.of(context).textTheme.titleMedium ?? const TextStyle())
            .merge(TextStyle(color: textColor));
    final TextStyle valueStyle = TextStyle(
        color: valueColor,
        fontSize: skin.type.sizeBody,
        fontWeight: FontWeight.w600);
    final Widget chevron = Icon(Icons.chevron_right, size: 18, color: valueColor);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        // What the tile has for text: its own 16 dp inset on each side, the
        // leading icon and the gap after it, and the chevron with its gap.
        final double room = c.maxWidth -
            32 -
            (leading == null ? 0 : 40) -
            (18 + 4);
        // One line while the pair fits on it; the value on its own line below
        // the title when it does not. Measured at the real style and the real
        // text scale, so the switch is where the value would otherwise have
        // been cut, not at a guess.
        final bool inline = mmPairFitsOneLine(
          context,
          a: title,
          aStyle: titleStyle,
          b: value,
          bStyle: valueStyle,
          gap: 16,
          width: room,
        );
        if (inline) {
          return ListTile(
            enabled: on,
            leading: leading,
            title: Text(title, style: titleStyle),
            subtitle: hint == null
                ? null
                : Text(hint!, style: TextStyle(color: subColor)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Text(value,
                      textAlign: TextAlign.end, style: valueStyle),
                ),
                const SizedBox(width: 4),
                chevron,
              ],
            ),
            onTap: on ? onTap : null,
          );
        }
        // Stacked: the value keeps the tile's leading column so it reads as the
        // row's own answer, and the chevron stays in the trailing slot.
        return ListTile(
          enabled: on,
          leading: leading,
          title: Text(title, style: titleStyle),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(value, style: valueStyle),
              if (hint != null)
                Text(hint!, style: TextStyle(color: subColor)),
            ],
          ),
          trailing: chevron,
          onTap: on ? onTap : null,
        );
      },
    );
  }
}

/// Whether two runs of text share one line inside [width] at the current text
/// scale, measured with the real painter.
///
/// The rule behind [MmReadout] and [MmPickerTile]: a pair decides its shape by
/// being measured, not by how many characters it happens to have. The painter
/// takes the same style objects the widgets paint with, so the switch lands
/// exactly where the second run would otherwise be cut.
bool mmPairFitsOneLine(
  BuildContext context, {
  required String a,
  required TextStyle aStyle,
  required String b,
  required TextStyle bStyle,
  required double gap,
  required double width,
}) {
  final TextDirection dir = Directionality.of(context);
  final TextScaler scaler = MediaQuery.textScalerOf(context);
  final TextPainter p = TextPainter(
    text: TextSpan(text: a, style: aStyle),
    textDirection: dir,
    maxLines: 1,
    textScaler: scaler,
  )..layout();
  final double aw = p.width;
  p.text = TextSpan(text: b, style: bStyle);
  p.layout();
  final double bw = p.width;
  p.dispose();
  return aw + gap + bw <= width;
}

/// The label ink for a chip, chosen together with its fill.
///
/// A chip's fill and its label are two colours that have to be decided as a
/// pair, and `ChipThemeData` can only state one of them per state: Flutter
/// merges a single `labelStyle` into every state of a chip, so a chip that
/// leaves its label colour to the theme paints `onSurfaceVariant` on the
/// selected fill. On a skin whose accent is pale that is a light label on a
/// light ground — measured on the device in the places sheet, whose three
/// ticked chips read as empty boxes with a checkmark floating in them.
///
/// So the pair lives here: the selected chip takes the ink that the fill was
/// defined against (`onPrimary`, the same token the accent pairs with
/// everywhere else), and the unselected chip takes the ordinary foreground.
TextStyle mmChipLabelStyle(
  BuildContext context, {
  required bool selected,
  bool enabled = true,
}) {
  final ColorScheme cs = Theme.of(context).colorScheme;
  if (!enabled) return TextStyle(color: cs.onSurfaceVariant);
  return TextStyle(
    color: selected ? cs.onPrimary : cs.onSurface,
    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
  );
}

/// A filter chip that states its label ink with its fill.
///
/// The wrapper exists so the pair cannot be split again: every chip in the app
/// is built through [MmFilterChip] or [MmChoiceChip], and neither accepts a
/// `labelStyle` that could disagree with the fill.
class MmFilterChip extends StatelessWidget {
  const MmFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final Widget label;
  final bool selected;

  /// Null disables the chip: an option that cannot be chosen here.
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: label,
      selected: selected,
      onSelected: onSelected,
      labelStyle: mmChipLabelStyle(context,
          selected: selected, enabled: onSelected != null),
      checkmarkColor: cs.onPrimary,
    );
  }
}

/// A one-of-N chip that states its label ink with its fill. See
/// [mmChipLabelStyle] for why the pair is not left to the theme.
class MmChoiceChip extends StatelessWidget {
  const MmChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.avatar,
    this.showCheckmark = true,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Widget? avatar;

  /// Whether a selected chip carries Material's checkmark.
  ///
  /// False where the fill and the label weight already say "selected" and the
  /// chip has something else to draw: a tick beside a channel name is a second
  /// mark for a fact the fill already states, and beside an unread count it made
  /// one chip carry three decorations.
  final bool showCheckmark;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: label,
        selected: selected,
        onSelected: onSelected,
        avatar: avatar,
        showCheckmark: showCheckmark && avatar == null,
        labelStyle: mmChipLabelStyle(context,
            selected: selected, enabled: onSelected != null),
      );
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
/// per-theme fork. Minimum height 48 dp (the app's tap floor, not 44:
/// the audit measured every screen against 48), 12/8 padding, optional icon.
class MmAction extends StatelessWidget {
  const MmAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.dense = false,
    this.compact = false,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Compact vertical padding for a control that sits inside a dense row.
  final bool dense;

  /// A third, quieter step for an inline offer inside a content row: the
  /// same 48 dp target and the same boundary, with the label at the small
  /// type role and less side padding. In a chat row a suggestion is an offer
  /// about the row above it, not a primary action, and two body-sized buttons
  /// under every message that names a place made the thread read as a form.
  final bool compact;

  /// The group's own write, in the same family as its neighbours.
  ///
  /// A screen used to say its main action with Material's `FilledButton` and
  /// everything else with [MmAction], which put a stadium next to a rectangle
  /// in one row: two shape languages, and on the light presets two corner
  /// treatments, for actions that differ only in how much they matter. The
  /// emphasis is the fill, so this variant fills with the accent and keeps
  /// every other metric of the family — the 48 dp floor, the 12/8 padding,
  /// the skin's own corner [MmShape], the wrapping label.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final bool on = onPressed != null;
    final Color fg = primary
        ? (on ? skin.color.onAccent : skin.color.fgDisabled)
        : (on ? skin.color.fg : skin.color.fgDisabled);
    // A control that is off keeps its outline. The border used to be the rule
    // at half strength, which on a paper ground composites to 1.4:1 and makes
    // the control dissolve into the page: "off" then reads as "not a control"
    // rather than "a control you cannot press yet". The disabled ink tier is
    // the right colour for the outline and the label both, and the fill stays
    // at full strength so the shape is a shape.
    final OutlinedBorder border = mmShapeBorder(
      skin.shape,
      side: BorderSide(
          color: primary
              ? (on ? skin.color.accent : skin.color.fgDisabled)
              : (on ? skin.color.line : skin.color.fgDisabled),
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
            constraints: const BoxConstraints(minHeight: 48),
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 12,
                vertical: dense || compact ? 6 : 8),
            decoration: ShapeDecoration(
              color: primary
                  ? (on
                      ? skin.color.accent
                      : skin.color.accent.withValues(alpha: .35))
                  : (on
                      ? skin.color.surfaceAlt
                      : skin.color.surfaceAlt.withValues(alpha: .7)),
              shape: border,
            ),
            // The label wraps rather than overflowing. At the 200 % text
            // floor a two-word label is wider than a 320 dp row, and a
            // control that clips its own name is not a control; the border
            // and the minimum height keep it looking pressable however many
            // lines it takes.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: compact ? 14 : 16, color: fg),
                  SizedBox(width: compact ? 4 : 6),
                ],
                Flexible(
                  child: Text(label,
                      softWrap: true,
                      style: TextStyle(
                          color: fg,
                          fontSize:
                              compact ? skin.type.sizeSm : skin.type.sizeBodyLg,
                          letterSpacing: .4,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where a group's actions sit: one row, one shape, one place.
///
/// The audit of 2026-11-14 found the same commit act hosted eight ways across
/// the screens — right-aligned under a field, right of a field inside a `Row`,
/// left-aligned, `Wrap(spaceBetween)` at the end of a section, a stretched
/// `Column`, a full-width body button, dialog `actions`, and one floating
/// action button. A user cannot learn a rule from eight examples, and the same
/// action looked like a different act depending on where it was reached from.
///
/// This is the host for anything that belongs to a group: start-aligned so the
/// eye finds it under the fields it commits, ladder spacing so the gaps agree
/// with the rest of the block, and a `Wrap` so it stacks instead of overflowing
/// at 320 dp with 200 % text — the case the `spaceBetween` rows existed for.
class MmActionRow extends StatelessWidget {
  const MmActionRow({
    super.key,
    required this.children,
    this.alignment = WrapAlignment.start,
  });

  final List<Widget> children;

  /// `spaceBetween` is for the one case where a row holds a destructive action
  /// at the far end from the constructive ones, and it is not the default.
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final MmSpace space = context.skin.space;
    return Wrap(
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: space.rowGap,
      runSpacing: space.rowGap,
      children: children,
    );
  }
}

/// One entry in [showMmPicker]: a group label or a choice.
class MmPickerItem<T> {
  const MmPickerItem.header(this.label)
      : value = null,
        icon = null,
        isHeader = true,
        onAction = null,
        detail = null;
  const MmPickerItem.option(this.value, this.label, {this.icon, this.detail})
      : isHeader = false,
        onAction = null;

  /// A row that does something instead of choosing a value: leave for another
  /// screen, or open a second list. The sheet closes first, so the action can
  /// push a route or another sheet without fighting the dismissal.
  const MmPickerItem.action(this.label, {this.icon, this.onAction})
      : value = null,
        isHeader = false,
        detail = null;

  final T? value;
  final String label;
  final IconData? icon;

  /// A second, quieter line under the label, for the fact a chooser needs to
  /// decide. The map's basemap picker is the reason: a source's name alone does
  /// not say who is credited for it, and drawing the credit as a second line of
  /// the *same* text made the list read as eight lines of equal weight.
  final String? detail;
  final bool isHeader;
  final VoidCallback? onAction;
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
                // A row is addressable by the value it carries, so a test can
                // choose a source whose name two entries share.
                key: it.value == null
                    ? null
                    : ValueKey<String>('mm-picker-${it.value}'),
                onTap: () {
                  Navigator.pop<T>(c, it.value);
                  it.onAction?.call();
                },
                // A row is at least a 48 dp target and grows with its
                // detail line rather than clipping it.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: skin.space.step(7), vertical: 6),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(it.label,
                                  style: TextStyle(
                                      color: skin.color.fg,
                                      fontSize: skin.type.size(15),
                                      fontWeight: it.value == current
                                          ? FontWeight.w600
                                          : FontWeight.w400)),
                              if (it.detail != null)
                                Text(it.detail!,
                                    style: TextStyle(
                                        color: skin.color.fgMuted,
                                        fontSize: skin.type.sizeSm)),
                            ],
                          ),
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

/// A bottom sheet body that stays above the keyboard.
///
/// `showModalBottomSheet(isScrollControlled: true)` positions the sheet against
/// the bottom of the *window* and does not react to `viewInsets`, so a sheet
/// that contains a filter field opens the keyboard over its own rows: the list
/// is narrowed to the two matches the user asked for and both of them are under
/// the keyboard, where no tap can reach them. Measured on the handset: the Ping
/// target sheet filtered to HELTEC-REP and HELTEC-BASE and neither could be
/// chosen, so the sheet looked broken while it was only covered.
///
/// The height is taken from the space the keyboard leaves, not from the whole
/// screen, so the constraint and the padding describe the same box.
class MmSheetBody extends StatelessWidget {
  const MmSheetBody({super.key, required this.child, this.heightFactor = .7});

  final Widget child;

  /// The share of the free height a sheet may take. A picker is a list, not a
  /// page: it should not cover the screen it came from.
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final double free = mq.size.height - mq.viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: free * heightFactor),
          child: child,
        ),
      ),
    );
  }
}
