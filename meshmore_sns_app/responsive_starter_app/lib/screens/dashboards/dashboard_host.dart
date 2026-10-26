// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/widgets.dart';

import '../../gen/app_localizations.dart';
import '../../ui/mm_page_header.dart';

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
    // The view name lives here, once, above whichever skin is drawing the
    // dashboard. Each skin keeps its own badge inside its own layout, but
    // the tab name is no longer the skin's job — otherwise six skins meant
    // six independently maintained titles and the app bar had to carry it.
    return Column(
      children: <Widget>[
        MmPageHeader(title: AppLocalizations.of(context).tabDashboard),
        Expanded(
          child: switch (context.skin.preset) {
      MmThemePreset.nerv => const NervDashboard(),
      MmThemePreset.hyperlocal => const HyperlocalDashboard(),
      MmThemePreset.agHud => const AgHudDashboard(),
      MmThemePreset.drPop => const DrPopDashboard(),
      MmThemePreset.recon => const ReconDashboard(),
      MmThemePreset.studio => const StudioDashboard(),
            _ => const DashboardScreen(),
          },
        ),
      ],
    );
  }
}
