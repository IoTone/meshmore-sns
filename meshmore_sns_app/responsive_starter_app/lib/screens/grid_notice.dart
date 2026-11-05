// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../theme/mm_skin.dart';

/// One state notice for the Hyperlocal grid's views.
///
/// The tab used to answer "nothing to show" in five different shapes: a bare
/// centred sentence here, a sentence plus a boxed diagnostic there, a painted
/// line inside a canvas. A user reading two views learned two idioms for the
/// same fact. This is the one shape: an icon, one sentence, and the action
/// that fixes it when one exists.
///
/// The sentences stay per view because the facts differ (no fix, no nodes, no
/// telemetry); only the presentation is shared.
class GridNotice extends StatelessWidget {
  const GridNotice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.detail,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;

  /// One smaller line under the sentence, for a distinction the user needs
  /// (which of two causes this is) without turning the notice into a page.
  final String? detail;

  /// Present only when there is something the user can do about the state.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final MmSkin skin = context.skin;
    final String? label = actionLabel;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(skin.space.step(5)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 32, color: cs.onSurfaceVariant),
            SizedBox(height: skin.space.step(3)),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: skin.type.sizeBody,
              ),
            ),
            if (detail != null) ...<Widget>[
              SizedBox(height: skin.space.step(2)),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: .8),
                  fontSize: skin.type.sizeSm,
                ),
              ),
            ],
            if (label != null && onAction != null) ...<Widget>[
              SizedBox(height: skin.space.step(4)),
              FilledButton.tonal(onPressed: onAction, child: Text(label)),
            ],
          ],
        ),
      ),
    );
  }
}
