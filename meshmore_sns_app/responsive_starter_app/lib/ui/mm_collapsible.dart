// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/mm_skin.dart';
import 'mm_collapse_controller.dart';
import 'mm_components.dart';

/// R63 — a collapsible group: a dim section label with a chevron, a
/// hairline rule under it, and content that is **not built** while the
/// group is closed.
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
        throw FlutterError(
            'duplicate MmCollapsibleSection id "${widget.id}" on screen');
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
      setState(() => _local = next);
    }
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    _store = context.watch<MmCollapseController?>();
    final Widget rule = Container(
      height: skin.shape.hairlineWidth,
      color: skin.color.hairline,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          button: true,
          expanded: _open,
          label: widget.title,
          excludeSemantics: true,
          onTap: _toggle,
          child: InkWell(
            onTap: _toggle,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(minHeight: kMinInteractiveDimension),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
        rule,
        if (_open) ...widget.children,
      ],
    );
  }
}
