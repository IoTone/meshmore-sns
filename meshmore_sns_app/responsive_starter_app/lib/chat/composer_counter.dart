// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import 'composer_budget.dart';

/// APP-D1 — how much of the radio's text budget a composer has left.
///
/// The number is the same one the send refuses with, computed by
/// [ComposerBudget]. It stays silent while the text fits comfortably: a count
/// in the reading path before it matters is noise, and the limit is a byte
/// count the reader cannot act on until it is nearly reached.
///
/// Shown as remaining bytes rather than a ratio because the limit is in bytes,
/// not characters (a Japanese message has far fewer characters at the same
/// count). Text, not colour alone, and a live region so a screen reader
/// announces the change.
class ComposerCounter extends StatelessWidget {
  const ComposerCounter({
    super.key,
    required this.budget,
    required this.text,
    required this.label,
  });

  final ComposerBudget budget;
  final String text;
  final AppLocalizations label;

  @override
  Widget build(BuildContext context) {
    final ComposerState state = budget.stateFor(text);
    if (state == ComposerState.ok) return const SizedBox.shrink();
    final MmSkin skin = context.skin;
    final Color colour =
        state == ComposerState.near ? skin.color.accent : skin.color.alertInk;
    final int remaining = budget.remainingFor(text);
    final String shown = switch (state) {
      ComposerState.over => label.chatBudgetTooLong(budget.overBy(text)),
      ComposerState.near => budget.prefixKnown
          ? label.chatBudgetNear(remaining)
          : label.chatBudgetEstimateNear(remaining),
      ComposerState.ok => '',
    };
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(top: 2, right: skin.space.step(1)),
        child: Semantics(
          liveRegion: true,
          label: shown,
          child: Text(
            shown,
            textAlign: TextAlign.end,
            style: TextStyle(color: colour, fontSize: skin.type.sizeMicro),
          ),
        ),
      ),
    );
  }
}
