// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:meshmore_sns_app/voice/voice_codec.dart';
import 'package:meshmore_sns_app/voice/voice_frame_packer.dart';

/// A [VoiceCodec] with no native code, for tests.
///
/// It is a *lossless stand-in* rather than a model of Codec 2: the point of a
/// caller's test is that frames arrive, pack, travel and come back in the same
/// order and the same count, and a fake that lossily compressed would make
/// those assertions about the fake instead. Each frame is a deterministic
/// function of its first sample, so a decode can prove which frame it got.
///
/// [modes] is how a test says "this build carries 700C only": asking for
/// anything else is refused exactly as the native path refuses a mode that was
/// not compiled in.
final class FakeVoiceCodec implements VoiceCodec {
  FakeVoiceCodec({this.modes = const <VoiceMode>{}, this.available = true});

  /// The modes this "build" carries, empty meaning none.
  final Set<VoiceMode> modes;
  final bool available;

  int encodeCalls = 0;
  int decodeCalls = 0;

  @override
  bool get isAvailable => available;

  @override
  PackedVoice encode(Uint8List pcm, {required VoiceMode mode}) {
    encodeCalls++;
    if (!available) {
      throw const VoiceException(
          VoiceFailure.codecUnavailable, 'this build has no voice codec');
    }
    if (!modes.contains(mode)) {
      throw VoiceException(VoiceFailure.modeUnavailable,
          'mode ${mode.label} is not compiled into this build');
    }
    final int frameBytes = mode.samplesPerFrame * 2;
    if (pcm.length % frameBytes != 0) {
      throw VoiceException(
          VoiceFailure.badFrame,
          'PCM is ${pcm.length} bytes, not a whole number of '
              '$frameBytes-byte frames');
    }
    final int frames = pcm.length ~/ frameBytes;
    final List<Uint8List> encoded = <Uint8List>[];
    for (int f = 0; f < frames; f++) {
      final Uint8List frame = Uint8List(mode.bytesPerFrame);
      // Two bytes of payload, derived from the first sample of the frame, so a
      // decode can say which frame it was.
      final int first = ByteData.sublistView(
              pcm, f * frameBytes, f * frameBytes + 2)
          .getInt16(0, Endian.host);
      frame[0] = first & 0xFF;
      frame[1] = (first >> 8) & 0xFF;
      frame[mode.bytesPerFrame - 1] = f & 0xFF;
      encoded.add(frame);
    }
    return PackedVoice(
      mode: mode,
      bytes: VoiceFramePacker.pack(encoded,
          bitsPerFrame: mode.bitsPerFrame,
          bytesPerFrame: mode.bytesPerFrame),
      frames: frames,
      samples: frames * mode.samplesPerFrame,
    );
  }

  @override
  Uint8List decode(Uint8List packed, {required VoiceMode mode, double ber = 0}) {
    decodeCalls++;
    if (!available) {
      throw const VoiceException(
          VoiceFailure.codecUnavailable, 'this build has no voice codec');
    }
    if (!modes.contains(mode)) {
      throw VoiceException(VoiceFailure.modeUnavailable,
          'mode ${mode.label} is not compiled into this build');
    }
    final List<Uint8List> frames = VoiceFramePacker.unpack(packed,
        bitsPerFrame: mode.bitsPerFrame, bytesPerFrame: mode.bytesPerFrame);
    final Uint8List pcm = Uint8List(frames.length * mode.samplesPerFrame * 2);
    final ByteData out = ByteData.sublistView(pcm);
    for (int f = 0; f < frames.length; f++) {
      final Uint8List frame = frames[f];
      final int first = frame[0] | (frame[1] << 8);
      final int signed = first >= 0x8000 ? first - 0x10000 : first;
      out.setInt16(f * mode.samplesPerFrame * 2, signed, Endian.host);
    }
    return pcm;
  }
}

/// 16-bit mono PCM at 8 kHz, [frames] frames long, where each frame's first
/// sample is [firstOf]'s answer for that frame index.
///
/// Deterministic and distinguishable per frame, which is what lets a decode
/// assert order rather than merely length.
Uint8List pcmOf(int frames, int Function(int frame) firstOf,
    {int samplesPerFrame = 320}) {
  final Uint8List pcm = Uint8List(frames * samplesPerFrame * 2);
  final ByteData view = ByteData.sublistView(pcm);
  for (int f = 0; f < frames; f++) {
    view.setInt16(f * samplesPerFrame * 2, firstOf(f), Endian.host);
  }
  return pcm;
}
