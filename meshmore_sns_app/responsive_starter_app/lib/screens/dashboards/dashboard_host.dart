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
    return KeyedSubtree(
      key: dashboardKey,
      child: switch (context.skin.preset) {
        MmThemePreset.nerv => const NervDashboard(),
        MmThemePreset.hyperlocal => const HyperlocalDashboard(),
        MmThemePreset.agHud => const AgHudDashboard(),
        MmThemePreset.drPop => const DrPopDashboard(),
        MmThemePreset.recon => const ReconDashboard(),
        // Studio Light is the same tool on paper, so it keeps the same
        // layout: a preset changes the ground, never which dashboard the user
        // is looking at. The two Studio presets used to split here, so
        // switching from Studio Dark to Studio Light replaced the whole
        // dashboard with the SEELE monolith (a colour-inverting slab and an
        // 88 sp numeral) instead of repainting the one on screen.
        MmThemePreset.studio || MmThemePreset.studioLight =>
          const StudioDashboard(),
        _ => const DashboardScreen(),
      },
    );
  }
}
