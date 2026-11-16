// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../theme/mm_skin.dart';
import '../ui/mm_shape.dart';

/// The reactions a message carries, as chips under it.
///
/// Shared rather than private to the channel list: a direct message carries
/// reactions too, and the DM row drew none, so a reaction that arrived in a
/// thread was folded into the message and then never shown. One widget means
/// the two lists cannot disagree about what a reaction looks like.
class ReactionChips extends StatelessWidget {
  const ReactionChips(this.reactions, {super.key});

  final Map<String, List<String?>> reactions;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    return Padding(
      padding:
          EdgeInsets.only(left: skin.space.rowInset, top: skin.space.rowGap),
      child: Wrap(
        spacing: skin.space.rowGap,
        runSpacing: skin.space.insideText,
        children: <Widget>[
          for (final MapEntry<String, List<String?>> e in reactions.entries)
            Container(
              key: ValueKey<String>('reaction-${e.key}'),
              padding: EdgeInsets.symmetric(
                  horizontal: skin.space.labelToControl,
                  vertical: skin.space.insideText),
              decoration: ShapeDecoration(
                color: skin.color.surfaceAlt,
                shape: mmShapeBorder(skin.shape,
                    side: BorderSide(color: skin.color.line)),
              ),
              child: Text(
                e.value.length > 1 ? '${e.key} ${e.value.length}' : e.key,
                style: TextStyle(
                    color: skin.color.fg, fontSize: skin.type.sizeBody),
              ),
            ),
        ],
      ),
    );
  }
}
