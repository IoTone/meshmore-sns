// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'voice_codec.dart';
import 'voice_frame_packer.dart';

/// The payload one recorded note travels as: a one-byte header and packed
/// frames.
///
/// `MediaKind.voice` says "these bytes are speech" and nothing else. The media
/// chunk header has no field left for a mode, and [VoiceFramePacker] carries no
/// header by design — the frame width comes from the mode and the frame count
/// from the length. That leaves a receiver with no way to know the width, and
/// it matters: a 1300 stream decoded as 700C is not a shorter recording, it is
/// noise from the first frame, and the two differ by 24 bits per frame.
///
/// So the payload carries exactly one byte before the frames:
///
/// ```
/// bit  7..4  version (1)
/// bit  3..0  VoiceMode.wireId (0 = 700C, 1 = 1300)
/// ```
///
/// One byte is what a 700C second can afford: it makes a 20-second note 1,751
/// bytes instead of 1,750, which is still twelve datagrams at 150 payload
/// bytes. Nothing else is stated — a sample rate of 8 kHz and mono are the
/// codec's own, and the frame count is the length divided by the width.
abstract final class VoicePayloadCodec {
  /// Bytes before the first frame. One, and it is the version as well as the
  /// mode, because a header that grows later has to be recognisable.
  static const int headerBytes = 1;

  /// The header's high nibble. A payload from a future layout is refused by
  /// name rather than decoded with this build's rules.
  static const int version = 1;

  /// The header for [mode], which is the whole of what a caller needs to
  /// recognise a payload before decoding it.
  static int headerFor(VoiceMode mode) => (version << 4) | (mode.wireId & 0x0F);

  /// The mode a payload names, or null when this build cannot read it.
  static VoiceMode? modeOf(Uint8List payload) {
    if (payload.length < headerBytes) return null;
    final int header = payload[0];
    if (header >> 4 != version) return null;
    return VoiceMode.fromWireId(header & 0x0F);
  }

  /// The bytes that go on the wire: the header, then the packed frames.
  ///
  /// An empty recording is refused rather than encoded as a header alone: a
  /// note with no frames has no duration, and a receiver would compute a
  /// zero-second message that still cost a datagram.
  static Uint8List encode(PackedVoice voice) {
    if (voice.bytes.isEmpty || voice.frames <= 0) {
      throw const VoiceException(
          VoiceFailure.badFrame, 'a note with no frames is not a note');
    }
    final Uint8List out = Uint8List(headerBytes + voice.bytes.length);
    out[0] = headerFor(voice.mode);
    out.setRange(headerBytes, out.length, voice.bytes);
    return out;
  }

  /// What the payload claims, without unpacking a single frame.
  ///
  /// An arriving note is inspected before it is offered to the user: a payload
  /// whose header this build cannot read, or whose last frame was cut, is
  /// refused at arrival rather than shown as a row that fails when pressed.
  /// Reading the width and the length is arithmetic on one byte and the total;
  /// only [decode] touches the frames.
  ///
  /// Three refusals, each a different fact: no header at all, a layout this
  /// build does not know, and a mode this build does not carry. The fourth —
  /// a stream cut inside a frame — is [VoiceFramePacker.trailingBits], which is
  /// 0–7 for anything [encode] produced.
  static PackedVoice inspect(Uint8List payload) {
    if (payload.length < headerBytes) {
      throw const VoiceException(
          VoiceFailure.badFrame, 'the payload carries no voice header');
    }
    final int header = payload[0];
    if (header >> 4 != version) {
      throw VoiceException(VoiceFailure.badFrame,
          'voice payload version ${header >> 4} is not $version');
    }
    final VoiceMode? mode = VoiceMode.fromWireId(header & 0x0F);
    if (mode == null) {
      throw VoiceException(VoiceFailure.modeUnavailable,
          'wire mode ${header & 0x0F} is not compiled into this build');
    }
    // Copied rather than viewed: the payload a caller hands in may be a view
    // over a live buffer (a reassembled transfer, a datagram), and a stored
    // note must not change under the thing that played it.
    final Uint8List frames = Uint8List.fromList(payload.sublist(headerBytes));
    if (frames.isEmpty) {
      throw const VoiceException(
          VoiceFailure.badFrame, 'the payload carries no frames');
    }
    final int frameCount =
        VoiceFramePacker.frameCountOf(frames, bitsPerFrame: mode.bitsPerFrame);
    if (frameCount == 0) {
      throw const VoiceException(
          VoiceFailure.badFrame, 'the payload carries no whole frame');
    }
    // The last byte is padded to a boundary, so 0–7 trailing bits are the
    // packer's own. Eight or more means the payload was cut inside a frame,
    // and decoding from there would be four bits of misalignment per frame.
    final int trailing =
        VoiceFramePacker.trailingBits(frames, bitsPerFrame: mode.bitsPerFrame);
    if (trailing >= 8) {
      throw VoiceException(VoiceFailure.badFrame,
          'the payload ends mid-frame: $trailing trailing bits');
    }
    return PackedVoice(
      mode: mode,
      bytes: frames,
      frames: frameCount,
      samples: frameCount * mode.samplesPerFrame,
    );
  }
}
