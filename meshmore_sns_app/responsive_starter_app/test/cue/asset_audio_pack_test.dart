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
          AssetAudioPack.assetPathFor(MmThemePreset.seele, CueKind.messageIn),
          'audio/seele/messageIn.wav');
      expect(AssetAudioPack.assetPathFor(MmThemePreset.nerv, CueKind.dmIn),
          'audio/nerv/dmIn.wav');
      expect(AssetAudioPack.assetPathFor(MmThemePreset.drPop, CueKind.alert),
          'audio/drpop/alert.wav');
      expect(
          AssetAudioPack.assetPathFor(MmThemePreset.hyperlocal, CueKind.linkUp),
          'audio/hyperlocal/linkUp.wav');
    });

    test('every preset × CueKind combination resolves uniquely', () {
      final Set<String> seen = <String>{};
      for (final MmThemePreset p in MmThemePreset.values) {
        for (final CueKind k in CueKind.values) {
          final String s = AssetAudioPack.assetPathFor(p, k);
          // A preset that borrows an earlier preset's pack is an alias, and
          // the aliases are asserted by name below. Deriving the list from the
          // packs keeps a new preset from needing an edit here: the bug this
          // guards is two *different* packs colliding on one path.
          final MmThemePreset owner = MmThemePreset.values.firstWhere(
              (MmThemePreset q) => q.audioPackKey == p.audioPackKey);
          if (owner != p) continue;
          expect(seen.add(s), isTrue,
              reason: 'duplicate asset path for $p/$k: $s');
        }
      }
      // One pack per preset. This used to allow five aliases onto the
      // Hyperlocal pack because no audio existed for those themes; each has its
      // own synthesised pack now, so the path is unique per preset and a preset
      // that points somewhere else is a bug.
      final Set<String> keys = <String>{
        for (final MmThemePreset p in MmThemePreset.values) p.audioPackKey,
      };
      expect(keys.length, MmThemePreset.values.length,
          reason: 'two presets resolve to the same audio folder');
      expect(seen.length, MmThemePreset.values.length * CueKind.values.length,
          reason: 'one path per preset per cue');
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
