// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../theme/theme_controller.dart';

/// Quick mute/unmute for alert sounds, surfaced on the dashboard (R12
/// follow-on). Audible cues are ON by default; this is the one-tap way
/// to silence them without digging into Settings. Bound to
/// `ThemeController.audioMaster`; reflects *actual* audibility (the
/// "visual + haptic only" accessibility switch also silences audio, so
/// the icon honours it and re-enabling clears it).
class MmAudioToggle extends StatelessWidget {
  const MmAudioToggle({super.key, this.size = 20, this.dense = false, this.color});

  final double size;

  /// Compact *visual* (zero padding, [size] glyph, no extra density
  /// shrink) for dense headers like the NERV LINK panel. R69: the hit box
  /// is still 48x48 ([kMinInteractiveDimension]); the glyph is unchanged,
  /// only the empty space around it is tappable and the header is taller.
  final bool dense;

  /// Overrides the "audible" tint (defaults to the colour scheme primary);
  /// the muted state always uses `onSurfaceVariant`.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeController theme;
    try {
      theme = context.watch<ThemeController>();
    } on ProviderNotFoundException {
      // No ThemeController above us (isolated widget test) — nothing to
      // toggle, so render nothing rather than crash. Matches MmScaffold.
      return const SizedBox.shrink();
    }
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);
    final bool audible = theme.audioMaster && !theme.visualHapticOnly;
    return IconButton(
      tooltip: audible ? l.dashboardAudioMute : l.dashboardAudioUnmute,
      padding: dense ? EdgeInsets.zero : null,
      // The same 48 dp box in both modes. Left to its own defaults this
      // `IconButton` is smaller than the buttons beside it, so its glyph sits
      // above their centres — the owner's "the speaker is too high next to the
      // block". A control's tap target is not a style choice either.
      constraints: const BoxConstraints(
          minWidth: kMinInteractiveDimension,
          minHeight: kMinInteractiveDimension),
      icon: Icon(
        audible ? Icons.volume_up : Icons.volume_off,
        size: size,
        color: audible ? (color ?? cs.primary) : cs.onSurfaceVariant,
      ),
      onPressed: () {
        if (audible) {
          theme.setAudioMaster(false);
        } else {
          // Unmuting also lifts "visual + haptic only" — otherwise that
          // switch would keep audio silent and the toggle would no-op.
          if (theme.visualHapticOnly) theme.setVisualHapticOnly(false);
          theme.setAudioMaster(true);
        }
      },
    );
  }
}
