// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../theme/mm_skin.dart';
import '../ui/mm_shape.dart';

/// The type-in field both composers draw, shaped by the skin.
///
/// A channel and a direct message draw the same field, and both used Material's
/// bare `OutlineInputBorder()`: a 4 px corner in Material's own outline colour.
/// That made the composer the one control in the app that ignored the skin's
/// corner (including the 1 px floor) and its hairline, so it read as a guest
/// element beside `MmAction` and the alarm screen's own field. Radius, border
/// colour, border width and the focus colour now come from the skin, which is
/// the same rule the shared controls follow.
InputDecoration composerFieldDecoration(
  BuildContext context, {
  required String hint,
}) {
  final MmSkin skin = context.skin;
  final BorderRadius radius = mmRadius(context, kRadiusSm);
  OutlineInputBorder border(Color colour) => OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colour, width: skin.shape.borderWidth),
      );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle:
        TextStyle(color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
    // `line`, not `hairline`: a text field's resting outline is the thing
    // that identifies the control, so it takes the strongest separator the
    // skin has. Measured against `base`, `line` is 3.93:1 on Air and 4.09:1
    // on Daybreak (the 3:1 a control boundary needs) and 1.38-2.75:1 on the
    // dark skins, where the skins' separators are decorative weights rather
    // than control boundaries — a `controlBorder` token is the fix and
    // belongs to the theme, not here. `hairline` would have been 1.70:1 on
    // paper.
    border: border(skin.color.line),
    enabledBorder: border(skin.color.line),
    // Focus is the skin's accent, not Material's primary: in the terminal
    // skins the Material primary is not the colour the rest of the screen
    // uses for "this is the control you are in".
    focusedBorder: border(skin.color.accent),
  );
}
