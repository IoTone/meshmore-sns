// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/demo_mode.dart';
import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import 'mm_shape.dart';

/// The app-bar marker for radio-free mode.
///
/// An empty fabric in demo mode and an empty fabric with a dead radio look
/// identical, so the mode is visible on every view rather than only in
/// Settings. It is a label, not a control: leaving the mode is a Settings
/// decision, because leaving it tries to reach the radio again.
class DemoChip extends StatelessWidget {
  const DemoChip({super.key});

  @override
  Widget build(BuildContext context) {
    final DemoMode demo = context.watch<DemoMode>();
    if (!demo.enabled) return const SizedBox.shrink();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    return Tooltip(
      message: l.demoTooltip,
      child: Semantics(
        label: l.demoTooltip,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: skin.color.line),
            borderRadius: mmRadius(context, kRadiusMd),
          ),
          child: Text(
            l.demoBanner,
            style: TextStyle(
              color: skin.color.fgMuted,
              fontSize: skin.type.sizeSm,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
