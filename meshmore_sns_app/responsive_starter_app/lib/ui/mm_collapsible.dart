// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../theme/mm_skin.dart';
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
/// State is held in the widget (session only): groups reopen to
/// [initiallyExpanded] on the next visit. Persisting it is a product
/// decision (see the R63 spec entry).
class MmCollapsibleSection extends StatefulWidget {
  const MmCollapsibleSection({
    super.key,
    required this.title,
    required this.children,
    this.initiallyExpanded = true,
    this.onChanged,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onChanged;

  @override
  State<MmCollapsibleSection> createState() => _MmCollapsibleSectionState();
}

class _MmCollapsibleSectionState extends State<MmCollapsibleSection> {
  late bool _open = widget.initiallyExpanded;

  void _toggle() {
    setState(() => _open = !_open);
    widget.onChanged?.call(_open);
  }

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
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
