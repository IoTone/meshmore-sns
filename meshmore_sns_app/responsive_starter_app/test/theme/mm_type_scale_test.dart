// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/viz_palette.dart';
import 'package:meshmore_sns_app/ui/mm_components.dart';

/// W2 — the type and spacing scales, and the reason they exist: a screen names
/// a role instead of a number, so one change moves every screen and the ratchet
/// has something to point at.
void main() {
  test('the size roles are the sizes the app already sets', () {
    const MmType t = MmType();
    expect(t.sizeMicro, 10);
    expect(t.sizeSm, 11);
    expect(t.sizeBody, 12);
    expect(t.sizeBodyLg, 13);
    expect(t.sizeLg, 16);
    expect(t.sizeXl, 20);
    expect(t.sizeTitle, 24);
    expect(t.sizeHero, 34);
  });

  test('every preset keeps its sizes where they are today (scale 1.0)', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      final MmSkin s = mmSkinFor(p);
      expect(s.type.typeScale, 1.0, reason: '$p');
      expect(s.type.sizeSm, 11, reason: '$p');
      expect(s.type.sizeBody, 12, reason: '$p');
      expect(s.space.scale, 1.0, reason: '$p');
    }
  });

  test('a skin multiplier moves every size at once', () {
    const MmType big = MmType(typeScale: 1.25);
    expect(big.sizeBody, 15);
    expect(big.sizeMicro, 12.5);
    // An off-ladder size rides the same multiplier, which is the point of
    // keeping it behind `size()` rather than as a literal.
    expect(big.size(10.5), 13.125);
  });

  test('the spacing ladder is 1..9 = 2,4,6,8,12,16,20,24,32', () {
    const MmSpace s = MmSpace();
    final List<double> got = <double>[for (int i = 1; i <= 9; i++) s.step(i)];
    expect(got, <double>[2, 4, 6, 8, 12, 16, 20, 24, 32]);
    expect(s.pad(5), const EdgeInsets.all(12));
    expect(const MmSpace(scale: 2).step(3), 12);
    expect(() => s.step(0), throwsA(isA<AssertionError>()));
    expect(() => s.step(10), throwsA(isA<AssertionError>()));
  });

  test('the section label stays at 11 px in every preset it is used in', () {
    // The shared idiom is the neutrality proof for the widgets the whole app
    // renders: the role equals the literal it replaced.
    for (final MmThemePreset p in MmThemePreset.values) {
      expect(mmSectionLabelStyle(mmSkinFor(p)).fontSize, 11, reason: '$p');
    }
  });

  test('data encodings are declared once and stay distinct', () {
    // A temperature ramp and a heat cue encode a value, so they do not follow
    // the skin; what matters is that they exist in one place and remain
    // distinguishable from each other.
    final Set<Color> ramp = <Color>{
      kThermalCold,
      kThermalMild,
      kThermalHot,
    };
    expect(ramp, hasLength(3));
    expect(kCellHeatHot, isNot(kCellHeatCool));
    expect(kInferredPlaceMarker, isNot(kThermalHot));
    expect(kMarkerShadow.a, lessThan(1.0),
        reason: 'a shadow must be see-through');
  });
}
