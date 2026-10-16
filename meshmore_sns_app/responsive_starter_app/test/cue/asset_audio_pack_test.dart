// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/cue/asset_audio_pack.dart';
import 'package:meshmore_sns_app/cue/cue_service.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

void main() {
  group('AssetAudioPack.assetPathFor', () {
    test('uses the preset audioPackKey + CueKind.name', () {
      expect(
          AssetAudioPack.assetPathFor(
              MmThemePreset.seele, CueKind.messageIn),
          'audio/seele/messageIn.wav');
      expect(
          AssetAudioPack.assetPathFor(
              MmThemePreset.nerv, CueKind.dmIn),
          'audio/nerv/dmIn.wav');
      expect(
          AssetAudioPack.assetPathFor(
              MmThemePreset.drPop, CueKind.alert),
          'audio/drpop/alert.wav');
      expect(
          AssetAudioPack.assetPathFor(
              MmThemePreset.hyperlocal, CueKind.linkUp),
          'audio/hyperlocal/linkUp.wav');
    });

    test('every preset × CueKind combination resolves uniquely', () {
      final Set<String> seen = <String>{};
      for (final MmThemePreset p in MmThemePreset.values) {
        for (final CueKind k in CueKind.values) {
          final String s = AssetAudioPack.assetPathFor(p, k);
          if (p == MmThemePreset.studio) continue; // aliased, see below
          expect(seen.add(s), isTrue,
              reason: 'duplicate asset path for $p/$k: $s');
        }
      }
      // R63 — Studio deliberately ALIASES the Hyperlocal pack (no studio
      // audio exists), so uniqueness is per distinct audioPackKey, not
      // per preset. Any other duplicate is still a bug.
      final Set<String> keys = <String>{
        for (final MmThemePreset p in MmThemePreset.values) p.audioPackKey,
      };
      expect(keys.length, MmThemePreset.values.length - 1,
          reason: 'exactly one alias (studio -> hyperlocal)');
      expect(MmThemePreset.studio.audioPackKey,
          MmThemePreset.hyperlocal.audioPackKey);
      expect(seen.length, 6 * CueKind.values.length,
          reason: '6 distinct packs × 7 cues = 42 unique paths');
    });
  });

  test('every preset has a non-empty audioPackKey slug', () {
    for (final MmThemePreset p in MmThemePreset.values) {
      expect(p.audioPackKey, isNotEmpty);
      // Slug should be lowercase, no spaces (filesystem-safe).
      expect(p.audioPackKey, equals(p.audioPackKey.toLowerCase()));
      expect(p.audioPackKey.contains(' '), isFalse);
    }
  });
}
