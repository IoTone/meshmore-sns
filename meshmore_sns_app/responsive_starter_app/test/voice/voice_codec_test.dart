// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/voice/native_voice_codec.dart';
import 'package:meshmore_sns_app/voice/voice_codec.dart';

import '../support/fake_voice_codec.dart';

/// The voice seam: what a caller can rely on, independent of whether the native
/// library is present.
///
/// Codec 2 cannot run in `flutter test` — there is no Android `libcodec2.so`
/// for the host ABI — so the fake carries the contract and the native path gets
/// one canary that skips when the library is absent. That split is deliberate:
/// a test that pretends to exercise native code is worse than one that says it
/// cannot.
void main() {
  group('a build without the codec says so instead of crashing', () {
    test('the fake reports availability and refuses every call', () {
      final FakeVoiceCodec codec = FakeVoiceCodec(available: false);
      expect(codec.isAvailable, isFalse);
      final Uint8List pcm = pcmOf(1, (int _) => 100);
      expect(
          () => codec.encode(pcm, mode: VoiceMode.narrowband),
          throwsA(isA<VoiceException>().having((VoiceException e) => e.failure,
              'failure', VoiceFailure.codecUnavailable)));
      expect(
          () => codec.decode(Uint8List(4), mode: VoiceMode.narrowband),
          throwsA(isA<VoiceException>().having((VoiceException e) => e.failure,
              'failure', VoiceFailure.codecUnavailable)));
    });

    test('the native codec answers rather than throwing on import or on '
        'construction', () {
      // On a host test there is no `libcodec2.so`, so this must come back false
      // and `encode` must refuse by name. On a device both would be true.
      final NativeVoiceCodec codec = NativeVoiceCodec();
      expect(codec.isAvailable, isFalse,
          reason: 'the host has no Android codec library');
      expect(
          () => codec.encode(Uint8List(640), mode: VoiceMode.narrowband),
          throwsA(isA<VoiceException>().having((VoiceException e) => e.failure,
              'failure', VoiceFailure.codecUnavailable)));
    });
  });

  group('a mode this build does not carry is a different refusal', () {
    test('700C-only build refuses 1300 by name', () {
      final FakeVoiceCodec codec =
          FakeVoiceCodec(modes: <VoiceMode>{VoiceMode.narrowband});
      expect(codec.isAvailable, isTrue);
      final Uint8List pcm = pcmOf(1, (int _) => 100);
      expect(codec.encode(pcm, mode: VoiceMode.narrowband).frames, 1);
      expect(
          () => codec.encode(pcm, mode: VoiceMode.standard),
          throwsA(isA<VoiceException>().having((VoiceException e) => e.failure,
              'failure', VoiceFailure.modeUnavailable)));
    });
  });

  group('a recording survives encode, pack and decode in order', () {
    test('every frame comes back where it started, at both widths', () {
      for (final VoiceMode mode in VoiceMode.values) {
        final FakeVoiceCodec codec =
            FakeVoiceCodec(modes: <VoiceMode>{mode});
        const int frames = 12;
        final Uint8List pcm =
            pcmOf(frames, (int f) => 1000 + f * 7, samplesPerFrame: mode.samplesPerFrame);
        final PackedVoice packed = codec.encode(pcm, mode: mode);
        expect(packed.frames, frames);
        expect(packed.samples, frames * mode.samplesPerFrame);
        expect(packed.bytes.length,
            (frames * mode.bitsPerFrame + 7) ~/ 8,
            reason: '${mode.label}: the payload is the packed size, no padding');
        expect(packed.duration, const Duration(milliseconds: 480),
            reason: '12 frames of 40 ms, computed from samples rather than '
                'from bytes');

        final Uint8List back = codec.decode(packed.bytes, mode: mode);
        expect(back.length, pcm.length);
        final ByteData a = ByteData.sublistView(pcm);
        final ByteData b = ByteData.sublistView(back);
        for (int f = 0; f < frames; f++) {
          expect(b.getInt16(f * mode.samplesPerFrame * 2, Endian.host),
              a.getInt16(f * mode.samplesPerFrame * 2, Endian.host),
              reason: '${mode.label}: frame $f must keep its position');
        }
      }
    });

    test('a partial frame is refused rather than padded', () {
      final FakeVoiceCodec codec =
          FakeVoiceCodec(modes: <VoiceMode>{VoiceMode.narrowband});
      // 320 samples is one frame; 100 samples is not.
      expect(
          () => codec.encode(Uint8List(200), mode: VoiceMode.narrowband),
          throwsA(isA<VoiceException>().having((VoiceException e) => e.failure,
              'failure', VoiceFailure.badFrame)),
          reason: 'padding silence onto the end would change the duration a '
              'receiver computes from the stream');
    });

    test('an empty recording is a payload of no frames, not an error', () {
      final FakeVoiceCodec codec =
          FakeVoiceCodec(modes: <VoiceMode>{VoiceMode.narrowband});
      final PackedVoice packed =
          codec.encode(Uint8List(0), mode: VoiceMode.narrowband);
      expect(packed.frames, 0);
      expect(packed.bytes, isEmpty);
      expect(packed.duration, Duration.zero);
      expect(codec.decode(packed.bytes, mode: VoiceMode.narrowband), isEmpty);
    });
  });

  group('the cost a surface quotes comes from the payload', () {
    test('a 20-second 700C note is twelve datagrams and about nine seconds', () {
      final FakeVoiceCodec codec =
          FakeVoiceCodec(modes: <VoiceMode>{VoiceMode.narrowband});
      final Uint8List pcm =
          pcmOf(500, (int f) => f, samplesPerFrame: VoiceMode.narrowband.samplesPerFrame);
      final PackedVoice packed = codec.encode(pcm, mode: VoiceMode.narrowband);
      expect(packed.frames, 500);
      expect(packed.bytes.length, 1750);
      expect(packed.datagramsAt(150), 12);
      expect(packed.duration, const Duration(seconds: 20));
    });
  });
}
