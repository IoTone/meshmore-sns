// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../screens/coverage_screen.dart';
import '../theme/mm_skin.dart';
import '../ui/radio_health_block.dart';
import 'dashboard_pins_controller.dart';
import 'mm_components.dart';

/// A content block that can be pinned to the dashboard.
///
/// Only blocks, never navigation entries. A block is a titled summary a screen
/// already shows in its own body, so moving it is a change of place, not a
/// second way to reach a screen: the SOS action, the Chat tab and the map's
/// Places button stay where they are, because they are the only route to what
/// they open and pinning them would either duplicate that route or strand it.
///
/// Pinning moves a block. The origin lays out without it, with no ghost row
/// and no reserved space, and the dashboard shows it as a card. Unpinning
/// puts it back on its own screen, which is the only way to read it again.
final class PinBlock {
  const PinBlock({
    required this.id,
    required this.title,
    required this.summary,
    required this.body,
  });

  final String id;

  /// Localised section title, matching the block's own header on its screen.
  final String Function(AppLocalizations l) title;

  /// One line for the collapsed card. Read from a controller, never fetched.
  final String Function(BuildContext context, AppLocalizations l) summary;

  /// The block itself, at the fidelity its screen shows it.
  final Widget Function(BuildContext context) body;
}

/// The closed set of pinnable blocks.
///
/// Every entry is a block that exists on a screen today. A block is added here
/// when it gains a header with the pin action, and removed when the block
/// itself is removed: a stored id that no longer resolves is dropped on load,
/// so a pin can never become an empty card.
abstract final class PinBlocks {
  static const String coverageSummary = 'pin.coverageSummary';
  static const String fieldExport = 'pin.fieldExport';
  static const String radioHealth = 'pin.radioHealth';

  static const List<String> order = <String>[
    coverageSummary,
    fieldExport,
    radioHealth,
  ];

  static const Set<String> all = <String>{
    coverageSummary,
    fieldExport,
    radioHealth,
  };

  /// The block for [id], or null when the id is not a pinnable block.
  static PinBlock? of(String id) {
    switch (id) {
      case coverageSummary:
        return PinBlock(
          id: id,
          title: (AppLocalizations l) => l.coverageCountsTitle,
          summary: coverageSummaryLine,
          body: (BuildContext context) => const CoverageSummaryBlock(),
        );
      case fieldExport:
        return PinBlock(
          id: id,
          title: (AppLocalizations l) => l.fieldExportSection,
          summary: (BuildContext context, AppLocalizations l) =>
              l.fieldExportSummaryLine,
          body: (BuildContext context) => const FieldExportBlock(),
        );
      case radioHealth:
        return PinBlock(
          id: id,
          title: (AppLocalizations l) => l.diagnosticsRadioHealth,
          summary: (BuildContext context, AppLocalizations l) =>
              l.radioHealthSummaryLine,
          body: (BuildContext context) => const RadioHealthBlock(),
        );
    }
    return null;
  }
}

/// Where a block lives on its own screen.
///
/// Renders the block when it is not pinned and nothing at all when it is: the
/// block moved, so the screen must not leave a row, a gap or a placeholder
/// behind. Two render sites for one block is the failure this prevents, so the
/// host is the only way a pinnable block reaches a screen.
class PinnableBlockHost extends StatelessWidget {
  const PinnableBlockHost({
    super.key,
    required this.pinId,
    required this.child,
  });

  final String pinId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final DashboardPinsController? pins =
        context.watch<DashboardPinsController?>();
    if (pins != null && pins.contains(pinId)) return const SizedBox.shrink();
    return child;
  }
}

/// The block's own header: its title, with the pin action in an overflow on
/// the same row, where a reader already looks for "what can I do with this".
///
/// A single-entry menu, because there is one thing to do. The block is never
/// rendered pinned: once it moves, this header moves with it, and the card's
/// own overflow takes over.
class PinnableBlockHeader extends StatelessWidget {
  const PinnableBlockHeader({
    super.key,
    required this.pinId,
    required this.title,
  });

  final String pinId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final DashboardPinsController? pins =
        context.watch<DashboardPinsController?>();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    return SizedBox(
      height: kMinInteractiveDimension,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mmSectionLabelStyle(skin),
            ),
          ),
          if (pins != null && !pins.contains(pinId))
            PopupMenuButton<String>(
              key: ValueKey<String>('pin-menu-$pinId'),
              tooltip: l.dashboardPinAdd,
              icon: const Icon(Icons.more_vert),
              onSelected: (_) => pins.pin(pinId),
              itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'pin',
                  child: Text(l.dashboardPinAdd),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
