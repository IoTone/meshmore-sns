// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import 'dashboard_pins_controller.dart';

/// "Pin to dashboard" for the screen that owns a summary.
///
/// The control lives with the feature rather than on the dashboard on
/// purpose: the dashboard stays a read surface, and the answer to "how do I
/// add one" is where the user already is. The same button unpins, so a
/// mistaken pin is two taps from undone and needs no edit mode to discover.
///
/// Renders nothing when no [DashboardPinsController] is above it, which is
/// the case in most widget tests and in a build without a dashboard.
class DashboardPinAction extends StatelessWidget {
  const DashboardPinAction({super.key, required this.pinId});

  /// One of [MmPinIds].
  final String pinId;

  @override
  Widget build(BuildContext context) {
    final DashboardPinsController? pins =
        context.watch<DashboardPinsController?>();
    if (pins == null) return const SizedBox.shrink();
    final AppLocalizations l = AppLocalizations.of(context);
    final bool pinned = pins.contains(pinId);
    return IconButton(
      key: ValueKey<String>('pin-action-$pinId'),
      tooltip: pinned ? l.dashboardPinRemove : l.dashboardPinAdd,
      icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
      iconSize: context.skin.type.sizeXl,
      onPressed: () => pins.toggle(pinId),
    );
  }
}
