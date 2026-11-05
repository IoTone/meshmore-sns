// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../theme/mm_skin.dart';
import 'mm_components.dart';

/// The collapsed height of a pinned block's card.
///
/// Fixed rather than intrinsic so a list of pins is predictable: ten cards
/// cannot push the content below them off the screen, and the two skins that
/// do not scroll can still bound the strip. A summary that does not fit is
/// ellipsised, never allowed to grow the card.
const double kPinCardCollapsedHeight = 64;

/// One entry in a card's overflow menu.
final class PinCardMenuEntry {
  const PinCardMenuEntry({required this.label, required this.onSelected});
  final String label;
  final VoidCallback onSelected;
}

/// One pinned block: a fixed-height row that expands in place.
///
/// Deliberately the same fold idiom as [MmCollapsibleSection] rather than a
/// second one: no animation (so reduce-motion needs no case and tests do not
/// need to settle), the whole header is one button at least 48 dp tall, and
/// the semantics carry `expanded` so a screen reader announces open or
/// closed. The difference is the height: a group is as tall as its content,
/// a card is [kPinCardCollapsedHeight] when closed because a dashboard is a
/// summary surface.
///
/// A card is the block's only render site while it is pinned: [detail] is the
/// block itself, built only while expanded.
///
/// Expansion state is owned by the caller (the pins controller), not by this
/// widget, so a rebuilt dashboard cannot disagree with itself about what is
/// open.
class MmPinCard extends StatelessWidget {
  const MmPinCard({
    super.key,
    required this.title,
    required this.summary,
    required this.detail,
    required this.expanded,
    required this.onToggle,
    this.leading,
    this.trailing,
    this.menu = const <PinCardMenuEntry>[],
  });

  /// Section label, one or two words. Localised by the caller.
  final String title;

  /// One line that must fit at 320 dp and 200 % text.
  final String summary;

  /// Built only while [expanded]. This is the block itself.
  final Widget detail;

  final bool expanded;
  final VoidCallback onToggle;

  /// A status icon or pill, sized for the collapsed row.
  final Widget? leading;

  /// A value or count shown at the end of the collapsed row.
  final String? trailing;

  /// The card's three-dot overflow. While pinned the only action is to remove
  /// it from the dashboard, which puts the block back on its own screen.
  final List<PinCardMenuEntry> menu;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          button: true,
          expanded: expanded,
          label: '$title. $summary',
          child: InkWell(
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: kPinCardCollapsedHeight,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: skin.space.step(5),
                  vertical: skin.space.step(3),
                ),
                child: Row(
                  children: <Widget>[
                    if (leading != null) ...<Widget>[
                      leading!,
                      SizedBox(width: skin.space.step(4)),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mmSectionLabelStyle(skin),
                          ),
                          SizedBox(height: skin.space.step(1)),
                          Text(
                            summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: skin.color.fg,
                              fontSize: skin.type.sizeBody,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (trailing != null) ...<Widget>[
                      SizedBox(width: skin.space.step(3)),
                      Text(
                        trailing!,
                        style: TextStyle(
                          color: skin.color.fgMuted,
                          fontSize: skin.type.sizeBodyLg,
                        ),
                      ),
                    ],
                    if (menu.isNotEmpty)
                      PopupMenuButton<int>(
                        key: const ValueKey<String>('pin-card-menu'),
                        tooltip: title,
                        icon: const Icon(Icons.more_vert),
                        onSelected: (int i) => menu[i].onSelected(),
                        itemBuilder: (BuildContext _) => <PopupMenuEntry<int>>[
                          for (int i = 0; i < menu.length; i++)
                            PopupMenuItem<int>(
                              value: i,
                              child: Text(menu[i].label),
                            ),
                        ],
                      ),
                    SizedBox(width: skin.space.step(2)),
                    // Shape, not colour, is the state: a right chevron when
                    // closed, a down chevron when open.
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: skin.type.sizeXl,
                      color: skin.color.fgMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: EdgeInsets.fromLTRB(
              skin.space.step(5),
              0,
              skin.space.step(5),
              skin.space.step(4),
            ),
            child: detail,
          ),
        Container(
          height: skin.shape.hairlineWidth,
          color: skin.color.hairline,
        ),
      ],
    );
  }
}
