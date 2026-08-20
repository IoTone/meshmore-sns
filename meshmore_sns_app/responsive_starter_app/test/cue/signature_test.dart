// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/cue/asset_audio_pack.dart';
import 'package:meshmore_sns_app/cue/cue_service.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

void main() {
  group('R58 signature slots', () {
    test('there are five, and they are signatures', () {
      expect(kSignatureSlots.length, 5);
      for (final CueKind s in kSignatureSlots) {
        expect(isSignature(s), isTrue, reason: '$s');
      }
    });

    test('ordinary event cues are not signatures', () {
      for (final CueKind k in <CueKind>[
        CueKind.dmIn,
        CueKind.messageIn,
        CueKind.alert,
        CueKind.scanStart,
      ]) {
        expect(isSignature(k), isFalse, reason: '$k');
      }
    });

    // The whole point of the slot ceiling. If a future change makes two
    // slots feel the same under any pack -- or makes one feel like an
    // ordinary channel message or an unsigned DM -- the signature stops
    // identifying anyone, and it fails here rather than in a pocket.
    test('no pack renders two slots to the same rhythm', () {
      for (final MmThemePreset p in MmThemePreset.values) {
        expect(signatureCollisions(p), isEmpty, reason: 'preset $p');
      }
      expect(signatureCollisions(null), isEmpty, reason: 'default profile');
    });

    test('each slot has a distinct rhythm within a pack', () {
      for (final MmThemePreset p in MmThemePreset.values) {
        final Set<String> seen = <String>{};
        for (final CueKind s in kSignatureSlots) {
          final String k = hapticPatternFor(p, s).join(',');
          expect(seen.add(k), isTrue, reason: '$p/$s collides: $k');
        }
      }
    });

    // A burst of inbound DMs must not queue into one continuous buzz.
    test('no signature rhythm exceeds three pulses', () {
      for (final MmThemePreset p in MmThemePreset.values) {
        for (final CueKind s in kSignatureSlots) {
          expect(hapticPatternFor(p, s).length, lessThanOrEqualTo(3),
              reason: '$p/$s');
        }
      }
    });

    test('every pack renders every slot non-empty', () {
      for (final MmThemePreset p in MmThemePreset.values) {
        for (final CueKind s in kSignatureSlots) {
          expect(hapticPatternFor(p, s), isNotEmpty, reason: '$p/$s');
        }
      }
    });

    // Identity survives a theme switch; expression changes with it.
    test('the same slot feels different across packs', () {
      final Set<String> renderings = <String>{
        for (final MmThemePreset p in MmThemePreset.values)
          hapticPatternFor(p, CueKind.sig1).join(','),
      };
      expect(renderings.length, greaterThan(1),
          reason: 'sig1 should not feel identical in every pack');
    });

    test('each slot resolves to its own asset in every pack', () {
      final Set<String> seen = <String>{};
      for (final MmThemePreset p in MmThemePreset.values) {
        for (final CueKind s in kSignatureSlots) {
          expect(seen.add(AssetAudioPack.assetPathFor(p, s)), isTrue);
        }
      }
      expect(seen.length, MmThemePreset.values.length * 5);
      expect(
        AssetAudioPack.assetPathFor(MmThemePreset.seele, CueKind.sig3),
        'audio/seele/sig3.wav',
      );
    });
  });
}
