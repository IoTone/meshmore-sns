// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/widgets.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../../app/degraded_state.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../maps/maps_controller.dart';
import '../../theme/mm_skin.dart';
import '../../ui/degraded_banner.dart';
import '../../util/prefs.dart';

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
///
/// The banner also owns its own top inset. Its host used to reserve
/// `padScreen.top` for it unconditionally, which on a healthy screen was 41 px
/// of empty space above the dashboard's first row while the row below kept only
/// its own small margin: the "more space above than below" the owner reported
/// against the status band, whose own padding was equal on both sides all along.
class DashboardDegradedBanner extends StatelessWidget {
  const DashboardDegradedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    // The map's own reachability, so "map offline" can actually be said. A null
    // answer (no fetch yet) is not an outage.
    final bool mapReachable = context.select<MapsController?, bool>(
        (MapsController? m) => m?.lastFetchOk != false);
    final double inset = context.skin.space.padScreen.top;
    return ValueListenableBuilder<bool>(
      valueListenable: Prefs.writeFailed,
      builder: (BuildContext _, bool writesFailed, Widget? __) {
        DegradedState state = DegradedState.observe(
          radioPaired: mc.state != MeshcoreConnectionState.disconnected,
          radioAnswering: mc.state == MeshcoreConnectionState.ready,
          storageFull: writesFailed,
          // Location stays out of this banner on purpose: having no fix is a
          // choice as often as a fault, and the screens that need a fix say so
          // where the reader is. The other two were hardcoded "fine", so the
          // banner could never say "map offline" or "clock never set" — states
          // DegradedMode names and nothing observed.
          hasLocation: true,
          mapReachable: mapReachable,
          clockUnset: mc.radioClockUnset,
          // The battery is the radio's own reading, fetched by the stats tool.
          // Diagnostics shows it with its source (`RadioHealthBlock`); the
          // dashboard does not read stats just to draw a banner, so it passes
          // nothing rather than guessing.
          batteryMilliVolts: null,
        );
        state = state.minus(const <DegradedMode>{
          DegradedMode.radioAbsent,
          DegradedMode.radioSilent,
        });
        if (!state.isDegraded) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(top: inset),
          child: DegradedBanner(state: state),
        );
      },
    );
  }
}
