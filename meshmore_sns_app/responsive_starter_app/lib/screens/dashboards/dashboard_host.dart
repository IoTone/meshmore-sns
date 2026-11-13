// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/widgets.dart';

import '../../theme/mm_skin.dart';
import '../../theme/mm_tokens.dart';
import '../dashboard_screen.dart';
import 'aghud_dashboard.dart';
import 'air_dashboard.dart';
import 'dashboard_degraded_banner.dart';
import 'daybreak_dashboard.dart';
import 'drpop_dashboard.dart';
import 'forest_dashboard.dart';
import 'hyperlocal_dashboard.dart';
import 'nerv_dashboard.dart';
import 'recon_dashboard.dart';
import 'studio_dashboard.dart';
import 'umber_dashboard.dart';

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
    // APP-N4's banner sits above the layout, not inside one: the facts it
    // reports are the same whichever preset is on screen, and it used to be
    // built inside the SEELE monolith only, so a storage-full warning was
    // invisible on six of the seven presets.
    return KeyedSubtree(
      key: dashboardKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // No vertical padding here. The banner carries its own inset and
          // draws nothing when nothing is degraded, so reserving
          // `padScreen.top` for it left 41 px of empty space above the first
          // row of every dashboard while the row below kept its own small
          // margin. That reads as "more space above the content than below
          // it", which is what the owner saw. The inset now belongs to the
          // banner and exists only when the banner does.
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.skin.space.padScreen.left,
            ),
            child: const DashboardDegradedBanner(),
          ),
          Expanded(child: _layout(context)),
        ],
      ),
    );
  }

  Widget _layout(BuildContext context) {
    return switch (context.skin.preset) {
      MmThemePreset.nerv => const NervDashboard(),
      MmThemePreset.hyperlocal => const HyperlocalDashboard(),
      MmThemePreset.agHud => const AgHudDashboard(),
      MmThemePreset.drPop => const DrPopDashboard(),
      MmThemePreset.recon => const ReconDashboard(),
      MmThemePreset.studio => const StudioDashboard(),
      // Air has a layout of its own: a white page cannot carry an instrument.
      MmThemePreset.air => const AirDashboard(),
      // Forest answers "how deep" rather than "how many": the depth bar is the
      // only element in the app that shows the mesh's shape.
      MmThemePreset.forest => const ForestDashboard(),
      // Umber is a workbench: four instruments in a square, no panels.
      MmThemePreset.umber => const UmberDashboard(),
      // Daybreak is the other white page, and it is a report rather than a spec
      // sheet: cards with a leading accent bar, not hairlines and a ledger.
      MmThemePreset.daybreak => const DaybreakDashboard(),
      // Every preset has a layout of its own now. The arm stays as the honest
      // default for a preset added later: a layout is a screen's own design, and
      // inheriting the SEELE monolith is better than a blank page until the new
      // skin earns one. `test/theme/theme_integration_test.dart` fails the moment
      // a preset is added without deciding which it is.
      _ => const DashboardScreen(),
    };
  }
}
