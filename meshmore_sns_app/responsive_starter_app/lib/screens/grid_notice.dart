// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../theme/mm_skin.dart';
import '../ui/mm_shape.dart';

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
    // Scrollable, because a notice must not clip itself. It can sit over a
    // canvas shorter than its own text — the tree's, at 200 % text on a 320 dp
    // phone, overflowed by 8 px before this.
    //
    // **A notice drawn over a canvas needs its own ground.** The sentence is
    // painted on top of whatever the view drew, and on the tree that was the
    // self node's ring and the route strokes: measured on the device, the
    // glyphs ran through "the tree is built from each contact's outPath" and
    // the line could not be read a word at a time. The panel is the skin's own
    // surface and edge tokens, not a translucent wash of them, so the canvas
    // shows through nowhere and the notice reads the same on all seven skins.
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(skin.space.step(5)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: EdgeInsets.symmetric(
            horizontal: skin.space.step(5),
            vertical: skin.space.step(4),
          ),
          decoration: BoxDecoration(
            color: skin.color.surface,
            borderRadius: mmRadius(context, kRadiusSm),
            border: Border.all(
                color: skin.color.line, width: skin.shape.borderWidth),
          ),
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
                // The quieter tier is the token for it rather than the same
                // colour at 80 %: a wash of a foreground is a third ink nobody
                // chose, and on the paper ground it falls under 3:1.
                style: TextStyle(
                  color: skin.color.fgMuted,
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
      ),
    );
  }
}
