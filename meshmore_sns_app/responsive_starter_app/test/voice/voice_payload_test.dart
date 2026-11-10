// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/voice/voice_codec.dart';
import 'package:meshmore_sns_app/voice/voice_payload.dart';

import '../support/fake_voice_codec.dart';

/// The one byte that makes a voice payload decodable.
///
/// `MediaKind.voice` says "speech" and nothing else, and the frame packer
/// carries no header, so without this byte a receiver has no width to decode at:
/// 700C is 28 bits a frame and 1300 is 52, and reading one as the other is not
/// a shorter note, it is noise. These cases pin the header, both round trips,
/// and every refusal a receiver can produce — because a payload from another
/// build is refused by name rather than decoded at the wrong width.

PackedVoice packed(VoiceMode mode, int frames) {
  final FakeVoiceCodec codec = FakeVoiceCodec(modes: <VoiceMode>{mode});
  return codec.encode(pcmOf(frames, (int f) => f + 1), mode: mode);
}

void main() {
  group('the header names the width', () {
    test('700C is 0x10 and 1300 is 0x11, version high nibble first', () {
      expect(VoicePayloadCodec.headerFor(VoiceMode.narrowband), 0x10);
      expect(VoicePayloadCodec.headerFor(VoiceMode.standard), 0x11);
      expect(VoicePayloadCodec.headerBytes, 1);
      expect(VoicePayloadCodec.version, 1);
    });

    test('the wire id is not the codec ABI id, and not the enum index', () {
      // 700C's CODEC2_MODE_* is 8 and 1300's is 4; neither is a nibble-wide
      // fact about the recording, and the enum order must not become one.
      expect(VoiceMode.narrowband.codec2Id, 8);
      expect(VoiceMode.standard.codec2Id, 4);
      expect(VoiceMode.narrowband.wireId, 0);
      expect(VoiceMode.standard.wireId, 1);
      expect(VoiceMode.fromWireId(1), VoiceMode.standard);
      expect(VoiceMode.fromWireId(9), isNull);
    });

    test('the payload is the header and then exactly the packed frames', () {
      final PackedVoice p = packed(VoiceMode.narrowband, 25);
      final Uint8List payload = VoicePayloadCodec.encode(p);
      expect(payload.length, 1 + p.bytes.length);
      expect(payload[0], 0x10);
      expect(payload.sublist(1), p.bytes);
    });
  });

  group('a payload reads back as the take it came from', () {
    test('a 20-second 700C note is 1,751 bytes and twelve datagrams', () {
      final PackedVoice p = packed(VoiceMode.narrowband, 500);
      // 500 frames × 28 bits = 14,000 bits = 1,750 bytes, plus the header.
      expect(p.bytes.length, 1750);
      final Uint8List payload = VoicePayloadCodec.encode(p);
      expect(payload.length, 1751);
      expect(p.datagramsAt(150), 12);
    });

    test('a 20-second 1300 note is 3,251 bytes and twenty-two datagrams', () {
      final PackedVoice p = packed(VoiceMode.standard, 500);
      // 500 × 52 = 26,000 bits = 3,250 bytes, plus the header.
      expect(p.bytes.length, 3250);
      expect(VoicePayloadCodec.encode(p).length, 3251);
      expect(p.datagramsAt(150), 22);
    });

    test('the frames decode at the width the header names', () {
      for (final VoiceMode mode in VoiceMode.values) {
        final FakeVoiceCodec codec = FakeVoiceCodec(modes: <VoiceMode>{mode});
        final Uint8List pcm = pcmOf(50, (int f) => 1000 + f);
        final PackedVoice sent = codec.encode(pcm, mode: mode);
        final PackedVoice received =
            VoicePayloadCodec.inspect(VoicePayloadCodec.encode(sent));
        expect(received.mode, mode);
        expect(received.frames, 50);
        expect(received.samples, 50 * 320);
        expect(received.duration, const Duration(seconds: 2));
        // The bytes a receiver holds decode to the PCM that was recorded: the
        // round trip is the whole point of putting the width on the wire.
        expect(codec.decode(received.bytes, mode: received.mode), pcm);
      }
    });
  });

  group('a payload this build cannot read is refused by name', () {
    test('no header at all', () {
      expect(
        () => VoicePayloadCodec.inspect(Uint8List(0)),
        throwsA(isA<VoiceException>().having((VoiceException e) => e.failure,
            'failure', VoiceFailure.badFrame)),
      );
    });

    test('a layout from a newer build', () {
      final Uint8List payload = Uint8List.fromList(<int>[0x20, 0x00]);
      expect(
        () => VoicePayloadCodec.inspect(payload),
        throwsA(isA<VoiceException>()
            .having((VoiceException e) => e.failure, 'failure',
                VoiceFailure.badFrame)
            .having((VoiceException e) => e.detail, 'detail',
                contains('version 2'))),
      );
    });

    test('a mode this build does not carry is not a corrupt payload', () {
      final Uint8List payload = Uint8List.fromList(<int>[0x12, 0x00]);
      expect(
        () => VoicePayloadCodec.inspect(payload),
        throwsA(isA<VoiceException>().having((VoiceException e) => e.failure,
            'failure', VoiceFailure.modeUnavailable)),
      );
    });

    test('a header with no frames behind it', () {
      expect(
        () => VoicePayloadCodec.inspect(Uint8List.fromList(<int>[0x10])),
        throwsA(isA<VoiceException>().having((VoiceException e) => e.failure,
            'failure', VoiceFailure.badFrame)),
      );
    });

    test('a payload cut inside a frame is refused, not decoded askew', () {
      final Uint8List payload =
          VoicePayloadCodec.encode(packed(VoiceMode.narrowband, 500));
      // 700C is exactly 8 bits per byte over 500 frames here, so one byte
      // short leaves 20 trailing bits: more than the packer's own padding.
      final Uint8List cut =
          Uint8List.fromList(payload.sublist(0, payload.length - 1));
      expect(
        () => VoicePayloadCodec.inspect(cut),
        throwsA(isA<VoiceException>()
            .having((VoiceException e) => e.failure, 'failure',
                VoiceFailure.badFrame)
            .having((VoiceException e) => e.detail, 'detail',
                contains('mid-frame'))),
      );
    });

    test('a take with no frames is refused at encode, not shipped', () {
      final PackedVoice empty = PackedVoice(
        mode: VoiceMode.narrowband,
        bytes: Uint8List(0),
        frames: 0,
        samples: 0,
      );
      expect(
        () => VoicePayloadCodec.encode(empty),
        throwsA(isA<VoiceException>().having((VoiceException e) => e.failure,
            'failure', VoiceFailure.badFrame)),
      );
    });
  });

  group('the recorded PCM is cut to whole frames', () {
    test('a tail shorter than a frame is dropped, not padded', () {
      // 320 samples × 2 bytes = 640 bytes a frame; 641 bytes is one frame and
      // one stray byte.
      final Uint8List pcm = pcmOf(3, (int f) => f);
      final Uint8List longer = Uint8List(pcm.length + 1)
        ..setAll(0, pcm)
        ..[pcm.length] = 0x7f;
      for (final VoiceMode mode in VoiceMode.values) {
        expect(voicePcmWholeFrames(longer, mode).length, pcm.length);
        expect(voicePcmWholeFrames(longer, mode), pcm);
        // Already whole: returned as it arrived, not copied for nothing.
        expect(identical(voicePcmWholeFrames(pcm, mode), pcm), isTrue);
      }
    });

    test('a take shorter than one frame becomes empty rather than a click', () {
      final Uint8List stub = Uint8List(639);
      for (final VoiceMode mode in VoiceMode.values) {
        expect(voicePcmWholeFrames(stub, mode), isEmpty);
      }
      expect(kVoiceMinFrames, 5);
    });
  });
}
