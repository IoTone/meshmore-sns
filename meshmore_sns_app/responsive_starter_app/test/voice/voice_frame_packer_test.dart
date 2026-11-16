// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/voice/voice_codec.dart';
import 'package:meshmore_sns_app/voice/voice_frame_packer.dart';

/// The packer is where the airtime is decided, so it gets the strictest tests
/// in the voice feature.
///
/// Codec 2 hands back whole bytes for a frame that carries fewer bits: 28 in a
/// 4-byte buffer for 700C and 52 in 7 for 1300. Four bits per frame are padding,
/// and on a link billed in datagrams that padding is 12 % of a 700C recording —
/// a whole datagram out of twelve on a 20-second note.
void main() {
  Uint8List frame(int bitsPerFrame, int bytesPerFrame, int seed) {
    final Random r = Random(seed);
    final Uint8List f = Uint8List(bytesPerFrame);
    for (int i = 0; i < bytesPerFrame; i++) {
      f[i] = r.nextInt(256);
    }
    // Clear the padding bits so a round trip is exact: the encoder never sets
    // them, and a test that leaves them set would be testing the packer's
    // tolerance rather than its correctness.
    final int spare = bytesPerFrame * 8 - bitsPerFrame;
    if (spare > 0) {
      f[bytesPerFrame - 1] &= 0xFF << spare & 0xFF;
    }
    return f;
  }

  group('bit-contiguous packing', () {
    test('25 frames of 700C occupy 88 bytes, not 100', () {
      // One second of audio: 25 frames of 40 ms. 25 × 28 bits = 700 bits.
      final List<Uint8List> frames = <Uint8List>[
        for (int i = 0; i < 25; i++)
          frame(VoiceMode.narrowband.bitsPerFrame,
              VoiceMode.narrowband.bytesPerFrame, i),
      ];
      final Uint8List packed = VoiceFramePacker.pack(frames,
          bitsPerFrame: VoiceMode.narrowband.bitsPerFrame,
          bytesPerFrame: VoiceMode.narrowband.bytesPerFrame);
      expect(packed.length, 88,
          reason: '25 × 28 bits is 700 bits, and 700 / 8 rounds up to 88');
      expect(packed.length, lessThan(25 * VoiceMode.narrowband.bytesPerFrame),
          reason: 'byte concatenation would be 100 bytes, 12 more');
      expect(
          VoiceFramePacker.frameCountOf(packed,
              bitsPerFrame: VoiceMode.narrowband.bitsPerFrame),
          25);
    });

    test('round-trips exactly at both mode widths', () {
      for (final VoiceMode mode in VoiceMode.values) {
        for (int n = 1; n <= 40; n++) {
          final List<Uint8List> frames = <Uint8List>[
            for (int i = 0; i < n; i++)
              frame(mode.bitsPerFrame, mode.bytesPerFrame, i * 31 + n),
          ];
          final Uint8List packed = VoiceFramePacker.pack(frames,
              bitsPerFrame: mode.bitsPerFrame,
              bytesPerFrame: mode.bytesPerFrame);
          expect(packed.length,
              VoiceFramePacker.packedBytes(n, mode.bitsPerFrame),
              reason: '${mode.label} with $n frames');
          final List<Uint8List> back = VoiceFramePacker.unpack(packed,
              bitsPerFrame: mode.bitsPerFrame,
              bytesPerFrame: mode.bytesPerFrame);
          expect(back.length, n, reason: '${mode.label} with $n frames');
          for (int i = 0; i < n; i++) {
            expect(back[i], frames[i],
                reason: '${mode.label} frame $i of $n must survive intact');
          }
        }
      }
    });

    test('the padding bits are not carried into the stream', () {
      // A frame whose padding bits are set must still pack to the same bytes as
      // one whose padding is clear: the codec never writes those bits, and a
      // packer that copied whole bytes would leak them onto the link.
      final Uint8List clean = frame(VoiceMode.narrowband.bitsPerFrame,
          VoiceMode.narrowband.bytesPerFrame, 7);
      final Uint8List dirty = Uint8List.fromList(clean);
      dirty[dirty.length - 1] |= 0x0F; // the four spare bits
      final Uint8List a = VoiceFramePacker.pack(<Uint8List>[clean],
          bitsPerFrame: VoiceMode.narrowband.bitsPerFrame,
          bytesPerFrame: VoiceMode.narrowband.bytesPerFrame);
      final Uint8List b = VoiceFramePacker.pack(<Uint8List>[dirty],
          bitsPerFrame: VoiceMode.narrowband.bitsPerFrame,
          bytesPerFrame: VoiceMode.narrowband.bytesPerFrame);
      expect(a, b);
    });

    test('a stream that ends mid-frame is refused, not misread', () {
      // 88 bytes is 25 whole 700C frames; 89 bytes leaves 4 spare bits, which
      // means the stream was cut short and everything after the cut is
      // misaligned.
      expect(
          () => VoiceFramePacker.unpack(Uint8List(89),
              bitsPerFrame: VoiceMode.narrowband.bitsPerFrame,
              bytesPerFrame: VoiceMode.narrowband.bytesPerFrame),
          throwsArgumentError,
          reason: '89 bytes is 712 bits: 25 frames plus 12 bits, which cannot '
              'be the packer\'s own byte padding');
      // 700 bits sits in 88 bytes with 4 spare bits of the last byte unused, so
      // 88 is a whole number of frames even though 88 × 8 is not 700.
      expect(
          VoiceFramePacker.unpack(Uint8List(88),
                  bitsPerFrame: VoiceMode.narrowband.bitsPerFrame,
                  bytesPerFrame: VoiceMode.narrowband.bytesPerFrame)
              .length,
          25);
    });

    test('an empty stream is no frames, and no frames is an empty stream', () {
      expect(
          VoiceFramePacker.pack(const <Uint8List>[],
              bitsPerFrame: 28, bytesPerFrame: 4),
          isEmpty);
      expect(
          VoiceFramePacker.unpack(Uint8List(0),
              bitsPerFrame: 28, bytesPerFrame: 4),
          isEmpty);
    });

    test('a frame of the wrong width is refused by name', () {
      expect(
          () => VoiceFramePacker.pack(<Uint8List>[Uint8List(5)],
              bitsPerFrame: 28, bytesPerFrame: 4),
          throwsArgumentError);
      expect(
          () => VoiceFramePacker.pack(const <Uint8List>[],
              bitsPerFrame: 0, bytesPerFrame: 4),
          throwsArgumentError);
      expect(
          () => VoiceFramePacker.pack(const <Uint8List>[],
              bitsPerFrame: 40, bytesPerFrame: 4),
          throwsArgumentError,
          reason: '4 bytes cannot hold 40 bits');
    });
  });

  group('what a note costs, stated before the microphone opens', () {
    test('a 20-second note is twelve datagrams at 700C and twenty-two at 1300',
        () {
      // 150 payload bytes per datagram: the chunk ceiling, less the media
      // header the transfer path already charges for.
      const int payloadBytes = 150;
      final VoiceMode narrow = VoiceMode.narrowband;
      final VoiceMode standard = VoiceMode.standard;

      final int narrowBytes = narrow.packedBytesFor(kVoiceMax20);
      final int standardBytes = standard.packedBytesFor(kVoiceMax20);
      expect(narrowBytes, 1750,
          reason: '20 s is exactly 500 frames of 40 ms, and 500 × 28 bits is '
              '14,000 bits, which is 1,750 whole bytes — no rounding at all');
      expect(standardBytes, 3250,
          reason: '500 × 52 bits is 26,000 bits, which is 3,250 whole bytes');
      expect((narrowBytes + payloadBytes - 1) ~/ payloadBytes, 12);
      expect((standardBytes + payloadBytes - 1) ~/ payloadBytes, 22);
    });

    test('the byte-concatenation cost is what the packer avoids', () {
      const int frames = 500; // 20 seconds of 40 ms frames
      final int padded = frames * VoiceMode.narrowband.bytesPerFrame; // 4 B
      final int packed = VoiceMode.narrowband.packedBytesFor(kVoiceMax20);
      expect(padded, 2000);
      expect(packed, 1750);
      expect(padded - packed, 250,
          reason: 'a quarter of a kilobyte, and a whole datagram out of twelve, '
              'spent on four padding bits per frame');
    });
  });
}

/// 20 seconds, named so the arithmetic above reads as the product rule rather
/// than a magic number.
const Duration kVoiceMax20 = Duration(seconds: 20);
