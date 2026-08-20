// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';

/// Marks a transcript row as machine-written (R59).
///
/// Non-negotiable per the spec: someone reading the log later must be
/// able to tell what a machine wrote. The wire carries `[bot]` for the
/// person on the other end, who has no UI; this is the same fact said
/// properly on our side, so the row body can drop the raw marker.
class BotTag extends StatelessWidget {
  const BotTag({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color c = color ?? cs.tertiary;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: c, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        AppLocalizations.of(context).botFromBot.toUpperCase(),
        style: TextStyle(
          color: c,
          fontSize: 9,
          letterSpacing: 1,
          fontWeight: FontWeight.w800,
          fontFamily: 'JetBrains Mono',
        ),
      ),
    );
  }
}
