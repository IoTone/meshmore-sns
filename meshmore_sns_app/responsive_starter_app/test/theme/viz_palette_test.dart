// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/viz_palette.dart';

void main() {
  test('viz roles map onto the skin colour tokens', () {
    final MmSkin skin = mmSkinFor(MmThemePreset.nerv);
    final VizPalette v = VizPalette.of(skin);
    expect(v.hot, skin.color.alert);
    expect(v.cool, skin.color.fg);
    expect(v.node, skin.color.fgMuted);
    expect(v.self, skin.color.accent);
    expect(v.inferred, skin.color.accent);
    // D11.5 — a grid line is a structure a reader has to see, so the viz
    // grid takes the control-boundary role rather than the divider tier.
    expect(v.grid, skin.color.edge);
  });

  test('the heat-map "hot" colour follows the theme (not a fixed hex)', () {
    final VizPalette nerv = VizPalette.of(mmSkinFor(MmThemePreset.nerv));
    final VizPalette recon = VizPalette.of(mmSkinFor(MmThemePreset.recon));
    expect(nerv.hot, isNot(recon.hot));
  });
}
