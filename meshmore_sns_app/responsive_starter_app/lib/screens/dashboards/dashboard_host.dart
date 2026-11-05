// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/widgets.dart';

import '../../theme/mm_skin.dart';
import '../../theme/mm_tokens.dart';
import '../dashboard_screen.dart';
import 'aghud_dashboard.dart';
import 'drpop_dashboard.dart';
import 'hyperlocal_dashboard.dart';
import 'nerv_dashboard.dart';
import 'recon_dashboard.dart';
import 'pinned_cards_section.dart';
import 'studio_dashboard.dart';

/// R8 dashboard host — selects the **per-skin dashboard layout**. Most
/// skins use the SEELE monolith ([DashboardScreen]); NERV gets its own
/// telemetry-grid re-imagining. This is the per-screen override
/// mechanism: a skin opts into a distinct layout, others inherit the
/// default — so reskinning a screen is additive, never all-or-nothing.
class DashboardHost extends StatelessWidget {
  const DashboardHost({super.key});

  @override
  Widget build(BuildContext context) {
    // No page header here. The strip already says which view is showing and
    // the dashboard's own content says what it is, so a second title row was
    // 56 dp of nothing above the first thing worth reading. Every other view
    // keeps its header, which carries that view's filters and actions.
    //
    // The key names the view, not one skin's layout: a test that asserts "the
    // dashboard is showing" must not depend on which preset is selected, and
    // since the default preset is STUDIO the SEELE layout's own key is no
    // longer the one on screen.
    //
    // One pinned section, drawn by every skin: the skin paints the cards, it
    // does not reimplement them. The two skins whose body owns its viewport
    // (the radar and the recon body) get a bounded strip that scrolls inside
    // itself, so a pin can never squeeze the view they exist for.
    const Widget pins = PinnedCardsSection();
    const Widget boundedPins = PinnedCardsSection(maxHeight: 232);
    return KeyedSubtree(
      key: dashboardKey,
      child: switch (context.skin.preset) {
        MmThemePreset.nerv => const NervDashboard(pinned: pins),
        MmThemePreset.hyperlocal =>
          const HyperlocalDashboard(pinned: boundedPins),
        MmThemePreset.agHud => const AgHudDashboard(pinned: pins),
        MmThemePreset.drPop => const DrPopDashboard(pinned: pins),
        MmThemePreset.recon => const ReconDashboard(pinned: boundedPins),
        MmThemePreset.studio => const StudioDashboard(pinned: pins),
        _ => const DashboardScreen(pinned: pins),
      },
    );
  }
}
