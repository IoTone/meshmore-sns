// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../theme/mm_skin.dart';
import '../../ui/dashboard_pins_controller.dart';
import '../../ui/mm_components.dart';
import '../../ui/mm_pin_card.dart';
import '../../ui/pin_blocks.dart';

/// The pinned blocks, in the order the user put them.
///
/// One section for every skin: the skin paints the cards, it does not
/// reimplement them, so a pinnable block exists in all seven presets.
///
/// The section renders nothing when nothing is pinned. That is deliberate: the
/// dashboard is useful before anyone pins anything, and an empty state asking
/// to be filled would be a second job for the home screen.
///
/// A pinned block is *moved*, not copied: its own screen lays out without it
/// (`PinnableBlockHost`), and this card is the only render site while it is
/// pinned. The card's overflow carries the way back.
class PinnedCardsSection extends StatefulWidget {
  const PinnedCardsSection({super.key, this.maxHeight});

  /// Bounds the strip for the two skins whose body does not scroll (the radar
  /// and the recon body own their viewport). Null means "as tall as the pins
  /// need".
  final double? maxHeight;

  @override
  State<PinnedCardsSection> createState() => _PinnedCardsSectionState();
}

class _PinnedCardsSectionState extends State<PinnedCardsSection> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final DashboardPinsController? pins =
        context.watch<DashboardPinsController?>();
    if (pins == null || pins.isEmpty) return const SizedBox.shrink();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;

    final List<Widget> cards = <Widget>[
      for (int i = 0; i < pins.pins.length; i++)
        _card(context, pins, pins.pins[i], index: i, l: l),
    ];

    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            skin.space.step(5),
            skin.space.step(3),
            skin.space.step(3),
            0,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l.dashboardPinsTitle,
                  style: mmSectionLabelStyle(skin),
                ),
              ),
              IconButton(
                tooltip: _editing ? l.dashboardPinsDone : l.dashboardPinsEdit,
                icon: Icon(_editing ? Icons.check : Icons.tune),
                iconSize: skin.type.sizeXl,
                onPressed: () => setState(() => _editing = !_editing),
              ),
            ],
          ),
        ),
        ...cards,
      ],
    );

    final double? max = widget.maxHeight;
    if (max == null) return body;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: max),
      child: SingleChildScrollView(child: body),
    );
  }

  Widget _card(
    BuildContext context,
    DashboardPinsController pins,
    String id, {
    required int index,
    required AppLocalizations l,
  }) {
    final PinBlock? block = PinBlocks.of(id);
    if (block == null) return const SizedBox.shrink();
    final MmSkin skin = context.skin;
    return Padding(
      key: ValueKey<String>('pin-row-$id'),
      padding: EdgeInsets.only(bottom: skin.space.step(2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MmPinCard(
            key: ValueKey<String>('pin-card-$id'),
            title: block.title(l),
            summary: block.summary(context, l),
            expanded: pins.isOpen(id),
            onToggle: () => pins.setOpen(id, !pins.isOpen(id)),
            menu: <PinCardMenuEntry>[
              PinCardMenuEntry(
                label: l.dashboardPinRemove,
                onSelected: () => pins.unpin(id),
              ),
            ],
            detail: block.body(context),
          ),
          if (_editing)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                IconButton(
                  key: ValueKey<String>('pin-up-$id'),
                  tooltip: l.dashboardPinsMoveUp,
                  icon: const Icon(Icons.arrow_upward),
                  iconSize: skin.type.sizeXl,
                  onPressed: index == 0 ? null : () => pins.move(id, index - 1),
                ),
                IconButton(
                  key: ValueKey<String>('pin-down-$id'),
                  tooltip: l.dashboardPinsMoveDown,
                  icon: const Icon(Icons.arrow_downward),
                  iconSize: skin.type.sizeXl,
                  onPressed: index == pins.pins.length - 1
                      ? null
                      : () => pins.move(id, index + 1),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
