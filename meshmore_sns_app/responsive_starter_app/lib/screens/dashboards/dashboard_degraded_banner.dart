// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/widgets.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../../app/degraded_state.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../util/prefs.dart';
import '../../ui/degraded_banner.dart';

/// APP-N4 — the one banner, shown above every layout.
///
/// The banner used to be built inside the SEELE monolith, so a storage-full
/// warning appeared on one of the seven presets and on none of the other six.
/// The observation does not belong to a layout: it is the same three facts
/// whichever dashboard is on screen, so it is hoisted here and every layout
/// inherits it.
///
/// The link's own states are deliberately not rendered here. The slab says them
/// in the same words a few pixels below, and two statements of one fact read as
/// two problems.
class DashboardDegradedBanner extends StatelessWidget {
  const DashboardDegradedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    return ValueListenableBuilder<bool>(
      valueListenable: Prefs.writeFailed,
      builder: (BuildContext _, bool writesFailed, Widget? __) =>
          DegradedBanner(
        state: DegradedState.observe(
          radioPaired: mc.state != MeshcoreConnectionState.disconnected,
          radioAnswering: mc.state == MeshcoreConnectionState.ready,
          storageFull: writesFailed,
          hasLocation: true,
          mapReachable: true,
          clockUnset: false,
          // The battery is the radio's own reading, fetched by the stats tool.
          // Diagnostics shows it with its source (`RadioHealthBlock`); the
          // dashboard does not read stats just to draw a banner, so it passes
          // nothing rather than guessing.
          batteryMilliVolts: null,
        ).minus(const <DegradedMode>{
          DegradedMode.radioAbsent,
          DegradedMode.radioSilent,
        }),
      ),
    );
  }
}
