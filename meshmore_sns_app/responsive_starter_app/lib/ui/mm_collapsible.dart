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
/// that is **not built** while the group is closed, and (R116) exactly one
/// rule marking where the group starts.
///
/// Reuses the app's one section-label idiom ([mmSectionLabelStyle], the
/// same style as `MmSectionHeader`) rather than inventing a second.
/// Colours and the rule width come from the active skin
/// (`MmTokens.line`, `MmShape.hairlineWidth`), so it follows every
/// preset.
///
/// The header is never filled. A tinted strip is a band of colour between
/// two rules, which reads as a box, and on paper it made every section one
/// more rectangle on a page that was already a stack of them. One rule in
/// the border tier above the label is the mark on every ground, so a
/// boundary is drawn once and always the same way.
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
  /// How many sections currently hold each id, to catch a duplicate while
  /// developing.
  ///
  /// A count rather than a set, because a set cannot tell a duplicate from a
  /// replacement: when a layout swaps under the same id (the dashboard does
  /// this as a preset loads), the incoming section mounts before the outgoing
  /// one disposes, and a set reports that as two sections sharing a fold.
  static final Map<String, int> _live = <String, int>{};

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
      _live[widget.id] = (_live[widget.id] ?? 0) + 1;
      _registered = true;
      if (_live[widget.id]! > 1) {
        // Deferred to the end of the frame: by then the outgoing section has
        // disposed, so only a real duplicate is still counted above one.
        //
        // Two sections with one id share a fold state, and the second one to
        // mount gets the first one's choice. That is a small bug; a thrown
        // error here is a large one: it replaces part of the screen with
        // Flutter's red error box in debug and with an apology card in the
        // field. Record it, keep rendering, and let the diagnostics record
        // carry the fact.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if ((_live[widget.id] ?? 0) <= 1) return;
          AppErrors.record(
              'duplicate MmCollapsibleSection id "${widget.id}" on screen',
              kDebugMode ? StackTrace.current : null,
              where: 'collapsible');
        });
      }
      return true;
    }());
  }

  @override
  void dispose() {
    assert(() {
      if (_registered) {
        final int left = (_live[widget.id] ?? 1) - 1;
        if (left <= 0) {
          _live.remove(widget.id);
        } else {
          _live[widget.id] = left;
        }
      }
      return true;
    }());
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
    // One boundary, one line, on every ground and in every preset.
    //
    // A group starts at a rule in the *border* tier and it starts there only:
    // the header is not filled, and the group does not also close with a rule
    // of its own. The earlier shape gave the dark skins a tinted header and
    // closed it with a hairline, which meant a boundary between two groups was
    // drawn twice wherever the previous rule and the fill's own edge nearly
    // met, and a folded group read as a box bounded above and below. The rule
    // above the label is the whole mark: it survives all eight presets, it
    // never doubles with a fill, and no rule ever sits between a header and its
    // own content (R77, R116).
    //
    // The *border* tier, not the hairline tier: this rule is the only thing
    // marking the group, and a hairline is deliberately too faint to carry a
    // border (`studio_light_test`: a hairline stays under 2.6:1).
    final Widget topRule = Container(
      key: const ValueKey<String>('group-open-rule'),
      height: skin.shape.hairlineWidth,
      color: skin.color.line,
    );
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
            // A header is a label and a rule, never a band: a filled strip is
            // one more rectangle on the page, and on paper it read as a box.
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggle,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: kMinInteractiveDimension),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: skin.space.step(6)),
                  child: Row(
                    children: <Widget>[
                      // The label comes first and the disclosure mark last, so
                      // a group's title starts on the same left edge as the
                      // text under it. With the chevron leading, every header
                      // sat 26 dp to the right of its own body, which reads as
                      // two columns that do not line up.
                      Expanded(
                        child: Text(
                          skin.type.upperHeadings
                              ? widget.title.toUpperCase()
                              : widget.title,
                          style: mmSectionLabelStyle(skin),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _open ? Icons.expand_more : Icons.chevron_right,
                        size: 18,
                        color: skin.color.fgMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // The group's content follows its header; the next group opens with
        // its own rule, so this group draws nothing at its end.
        if (_open) ...widget.children,
      ],
    );
  }
}
