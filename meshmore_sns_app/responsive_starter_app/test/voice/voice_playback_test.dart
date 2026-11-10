// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/voice/voice_capture.dart';
import 'package:meshmore_sns_app/voice/voice_playback.dart';

/// Playback is where the codec's output leaves the app.
///
/// Codec 2 decodes to raw PCM and every platform player wants a container, so
/// the whole of the difference is a 44-byte RIFF header. It is pinned here byte
/// by byte, because a wrong field is a file that plays at the wrong speed, or
/// not at all, and the failure looks like "voice is broken" rather than "one
/// number in a header".

Uint8List _pcm(int samples) {
  final Uint8List pcm = Uint8List(samples * 2);
  for (int i = 0; i < samples; i++) {
    pcm[i * 2] = i & 0xFF;
    pcm[i * 2 + 1] = (i >> 8) & 0xFF;
  }
  return pcm;
}

int _u32(Uint8List b, int at) =>
    ByteData.sublistView(b).getUint32(at, Endian.little);
int _u16(Uint8List b, int at) =>
    ByteData.sublistView(b).getUint16(at, Endian.little);
String _ascii(Uint8List b, int at, int n) =>
    String.fromCharCodes(b.sublist(at, at + n));

void main() {
  group('the WAV header says what the codec produced', () {
    test('8 kHz, mono, 16-bit PCM, with the exact lengths', () {
      final Uint8List pcm = _pcm(160); // 0.02 s
      final Uint8List wav = wavFromPcm(pcm);
      expect(wav.length, 44 + pcm.length);
      expect(_ascii(wav, 0, 4), 'RIFF');
      expect(_u32(wav, 4), 36 + pcm.length);
      expect(_ascii(wav, 8, 4), 'WAVE');
      expect(_ascii(wav, 12, 4), 'fmt ');
      expect(_u32(wav, 16), 16);
      expect(_u16(wav, 20), 1, reason: 'uncompressed PCM');
      expect(_u16(wav, 22), kVoiceChannels);
      expect(_u32(wav, 24), kVoiceSampleRate);
      expect(_u32(wav, 28), kVoiceSampleRate * 2, reason: 'byte rate');
      expect(_u16(wav, 32), 2, reason: 'block align: mono 16-bit');
      expect(_u16(wav, 34), 16, reason: 'bits per sample');
      expect(_ascii(wav, 36, 4), 'data');
      expect(_u32(wav, 40), pcm.length);
      expect(wav.sublist(44), pcm, reason: 'the samples are untouched');
    });

    test('a 20-second take is 320,044 bytes and still one header', () {
      final Uint8List wav = wavFromPcm(Uint8List(kVoiceSampleRate * 2 * 20));
      expect(wav.length, 44 + 320000);
      expect(_u32(wav, 40), 320000);
      expect(_u32(wav, 4), 36 + 320000);
    });

    test('a half sample is refused rather than played as noise', () {
      expect(() => wavFromPcm(Uint8List(3)), throwsArgumentError);
      expect(() => wavFromPcm(Uint8List(2), sampleRate: 0), throwsArgumentError);
      expect(() => wavFromPcm(Uint8List(2), channels: 0), throwsArgumentError);
    });
  });

  group('the seam a surface drives', () {
    test('the fake records what it was asked to play, once, in order', () async {
      final SilentVoicePlayback playback = SilentVoicePlayback();
      final Uint8List first = _pcm(4);
      final Uint8List second = _pcm(8);
      await playback.play(first);
      await playback.play(second);
      expect(playback.played.length, 2);
      expect(playback.played.first, first);
      expect(playback.played.last, second);
      // A copy, so a caller reusing its buffer cannot change what was played.
      expect(identical(playback.played.first, first), isFalse);
      await playback.stop();
      expect(playback.stops, 1);
      await playback.dispose();
    });

    test('a build with no player refuses by name instead of throwing raw',
        () async {
      final SilentVoicePlayback playback = SilentVoicePlayback(available: false);
      expect(playback.isAvailable, isFalse);
      await expectLater(
        playback.play(_pcm(2)),
        throwsA(isA<VoicePlaybackException>().having(
            (VoicePlaybackException e) => e.failure,
            'failure',
            VoicePlaybackFailure.unavailable)),
      );
      await playback.dispose();
    });

    test('the completion stream is what a row listens to for "not playing"',
        () async {
      final SilentVoicePlayback playback = SilentVoicePlayback();
      int completions = 0;
      final StreamSubscription<void> sub =
          playback.onComplete.listen((_) => completions++);
      await playback.play(_pcm(2));
      playback.finish();
      await Future<void>.delayed(Duration.zero);
      expect(completions, 1);
      await sub.cancel();
      await playback.dispose();
    });
  });
}
