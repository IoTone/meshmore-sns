// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_errors.dart';
import '../theme/mm_skin.dart';
import 'mm_collapse_controller.dart';
import 'mm_components.dart';

/// R63 — a collapsible group: a dim section label with a chevron, content
/// that is **not built** while the group is closed, and (R77) one hairline
/// rule at the END that closes the group.
///
/// Reuses the app's one section-label idiom ([mmSectionLabelStyle], the
/// same style as `MmSectionHeader`) rather than inventing a second.
/// Colours and the rule width come from the active skin
/// (`MmTokens.hairline`, `MmShape.hairlineWidth`), so it follows every
/// preset.
///
/// Accessibility: the whole header row is one button at least
/// [kMinInteractiveDimension] (48dp) tall; its semantics carry
/// `expanded` so a screen reader announces open/closed. The chevron's
/// *shape* (down vs. right) is the visual state, not colour alone. No
/// animation, so reduce-motion needs no special case.
///
/// R65 — open/closed is persisted per [id] by [MmCollapseController]
/// (found through `provider`), so a folded group stays folded on the next
/// visit and after a restart. [initiallyExpanded] is only the default for
/// a group the user has never toggled. Without a provider above it (a
/// bare widget test) the state is held in the widget for the session.
class MmCollapsibleSection extends StatefulWidget {
  const MmCollapsibleSection({
    super.key,
    required this.id,
    required this.title,
    required this.children,
    this.initiallyExpanded = true,
    this.onChanged,
  });

  /// Stable, non-localised id (see [MmGroupIds]). Must be unique among
  /// the groups on screen at once.
  final String id;
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onChanged;

  @override
  State<MmCollapsibleSection> createState() => _MmCollapsibleSectionState();
}

class _MmCollapsibleSectionState extends State<MmCollapsibleSection> {
  /// Ids currently mounted, to catch a duplicate id while developing.
  static final Set<String> _live = <String>{};

  bool _registered = false;
  bool _warned = false;
  late bool _local = widget.initiallyExpanded;
  MmCollapseController? _store;

  bool get _open =>
      _store?.isOpen(widget.id, fallback: widget.initiallyExpanded) ?? _local;

  @override
  void initState() {
    super.initState();
    assert(() {
      _registered = _live.add(widget.id);
      if (!_registered) {
        // Two sections with one id share a fold state, and the second one to
        // mount gets the first one's choice. That is a small bug; a thrown
        // error here is a large one: it replaces part of the screen with
        // Flutter's red error box in debug and with an apology card in the
        // field (seen on the dashboard while two layouts were mounted for one
        // frame as the skin loaded). Record it, keep rendering, and let the
        // diagnostics record carry the fact.
        AppErrors.record(
            'duplicate MmCollapsibleSection id "${widget.id}" on screen',
            kDebugMode ? StackTrace.current : null,
            where: 'collapsible');
      }
      return true;
    }());
  }

  @override
  void dispose() {
    assert(!_registered || _live.remove(widget.id));
    super.dispose();
  }

  void _toggle() {
    final bool next = !_open;
    final MmCollapseController? s = _store;
    if (s != null) {
      s.setOpen(widget.id, next); // notifies; rebuilds this widget
    } else {
      // R66: no MmCollapseController above us, so this choice is lost
      // when the screen closes. Say so, once per widget instance and
      // only on a toggle (no static state to leak between tests).
      if (!_warned) {
        _warned = true;
        if (kDebugMode) {
          debugPrint('MmCollapsibleSection "${widget.id}": no '
              'MmCollapseController provided, collapse state is '
              'session-only (not persisted)');
        }
      }
      setState(() => _local = next);
    }
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    _store = context.watch<MmCollapseController?>();
    // One boundary, one line. A tinted header marks where a group starts, so
    // the group closes with a hairline; an untinted header on paper needs the
    // rule above it instead. Drawing both put two lines a few dp apart between
    // every pair of groups, which is the doubled border the owner saw.
    final Widget closeRule = Container(
      key: const ValueKey<String>('group-close-rule'),
      height: skin.shape.hairlineWidth,
      color: skin.color.hairline,
    );
    // A header that carries no tint needs an edge to start at. On the dark
    // grounds the tonal step does that job; on paper a band is a box, so the
    // rule above the label is what separates one group from the last.
    //
    // That rule is the *border* tier, not the hairline tier: on paper it is
    // the only thing marking the group, and a hairline is deliberately too
    // faint to be a border (`studio_light_test`: a hairline stays under 2.6:1).
    // A tinted group closes with a hairline instead, so no boundary carries two
    // lines, and no rule ever sits between a header and its own content (R77).
    final Widget bandRule = Container(
      key: const ValueKey<String>('group-open-rule'),
      height: skin.shape.hairlineWidth,
      color: skin.color.line,
    );
    final bool tinted = skin.shape.tintedHeaders;
    final Widget topRule = tinted ? const SizedBox.shrink() : bandRule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        topRule,
        Semantics(
          button: true,
          expanded: _open,
          label: widget.title,
          excludeSemantics: true,
          onTap: _toggle,
          child: Material(
            // R77: Studio tints the header one tonal step (raised) so the
            // header, not a divider, marks where a group starts.
            color: skin.shape.tintedHeaders
                ? skin.color.raised
                : Colors.transparent,
            child: InkWell(
              onTap: _toggle,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: kMinInteractiveDimension),
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: skin.space.step(6)),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        _open ? Icons.expand_more : Icons.chevron_right,
                        size: 18,
                        color: skin.color.fgMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          skin.type.upperHeadings
                              ? widget.title.toUpperCase()
                              : widget.title,
                          style: mmSectionLabelStyle(skin),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // R77: children first, then ONE rule that closes the group, so a
        // divider never sits between a header and its own content.
        if (_open) ...widget.children,
        // A tinted group already says where it starts, so it closes; an
        // untinted one opened with a rule, so it does not close.
        if (tinted) closeRule,
      ],
    );
  }
}
