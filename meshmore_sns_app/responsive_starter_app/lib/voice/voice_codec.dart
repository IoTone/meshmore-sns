// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

/// A Codec 2 mode this build can encode and decode.
///
/// Two, because airtime is the cost and these are the two ends that matter:
/// 700C is the only mode that fits a 20-second note in a dozen datagrams, and
/// 1300 is the only mode upstream wires for soft-decision decoding. 1600 and
/// 3200 are deliberately not compiled in, so [NativeVoiceCodec] cannot open
/// them even by accident — a mode that does not exist cannot be fallen back to
/// when a stored setting is corrupt.
///
/// The numbers are Codec 2's own, not this app's: `codec2_bits_per_frame` and
/// `codec2_samples_per_frame` return exactly these for each mode.
enum VoiceMode {
  /// 28 bits per 40 ms frame. 700 bit/s, 87.5 bytes per second of audio.
  narrowband(8, '700C', bitsPerFrame: 28, bytesPerFrame: 4, samplesPerFrame: 320),

  /// 52 bits per 40 ms frame. 1300 bit/s, 162.5 bytes per second.
  standard(4, '1300', bitsPerFrame: 52, bytesPerFrame: 7, samplesPerFrame: 320);

  const VoiceMode(
    this.codec2Id,
    this.label, {
    required this.bitsPerFrame,
    required this.bytesPerFrame,
    required this.samplesPerFrame,
  });

  /// The `CODEC2_MODE_*` value the C library takes. Not the enum index: these
  /// are ABI and a wrong number is a codec for a different mode, silently.
  final int codec2Id;

  /// How the mode is named on the wire, in logs and in the licence notice.
  final String label;

  /// Bits a frame really carries. Less than `bytesPerFrame * 8` by design.
  final int bitsPerFrame;

  /// Bytes Codec 2 writes into per frame, padding included.
  final int bytesPerFrame;

  /// Samples of 8 kHz PCM a frame decodes to (40 ms).
  final int samplesPerFrame;

  /// Bytes an unpacked frame occupies, i.e. two per sample.
  int get pcmBytesPerFrame => samplesPerFrame * 2;

  /// The mode with this Codec 2 id, or null when this build does not carry it.
  static VoiceMode? fromCodec2Id(int id) {
    for (final VoiceMode m in VoiceMode.values) {
      if (m.codec2Id == id) return m;
    }
    return null;
  }

  /// Bytes for [seconds] of audio if frames are packed bit-contiguously.
  ///
  /// This is the number the composer states before the microphone opens: a
  /// 20-second note is exactly 500 frames of 40 ms, so it is 1,750 bytes at
  /// [narrowband] — twelve datagrams at 150 payload bytes each — and 3,250
  /// bytes at [standard], twenty-two datagrams.
  int packedBytesFor(Duration audio) {
    final int frames = (audio.inMilliseconds / 40).ceil();
    return (frames * bitsPerFrame + 7) ~/ 8;
  }
}

/// Why voice could not be encoded, decoded or recorded.
enum VoiceFailure {
  /// This build has no codec: the native library did not load, or it was not
  /// built for this ABI. The answer is "rebuild", not "resend".
  codecUnavailable,

  /// The mode is not compiled into this build. Separate from
  /// [codecUnavailable] because the library is fine and the mode is not.
  modeUnavailable,

  /// A frame stream did not match the mode it was opened as.
  badFrame,

  /// The microphone is refused, or the platform cannot record the PCM the
  /// codec needs.
  captureUnavailable,
}

/// A typed voice failure with the detail a log line needs.
final class VoiceException implements Exception {
  const VoiceException(this.failure, this.detail);

  final VoiceFailure failure;
  final String detail;

  @override
  String toString() => 'VoiceException(${failure.name}: $detail)';
}

/// One packed recording: the frames as they travel, and how they were made.
final class PackedVoice {
  const PackedVoice({
    required this.mode,
    required this.bytes,
    required this.frames,
    required this.samples,
  });

  final VoiceMode mode;

  /// The payload on the wire: frames packed bit-contiguously, no header.
  final Uint8List bytes;

  /// How many frames [bytes] carries.
  final int frames;

  /// How many samples of 8 kHz PCM those frames decode to.
  final int samples;

  Duration get duration =>
      Duration(microseconds: samples * 1000000 ~/ 8000);

  /// Datagrams this payload needs at [payloadBytes] per chunk, which is what
  /// the composer quotes before the send.
  int datagramsAt(int payloadBytes) =>
      payloadBytes <= 0 ? 0 : (bytes.length + payloadBytes - 1) ~/ payloadBytes;

  @override
  String toString() => 'PackedVoice(${mode.label}, $frames frames, '
      '${bytes.length} B, $duration)';
}

/// The seam between the app and the speech codec, for the same reason
/// `MediaCodec` exists: production has exactly one implementation, tests need
/// none, and a codec swap touches one file.
abstract interface class VoiceCodec {
  /// True when this build can encode and decode. A build without the native
  /// library must still run, so this is a condition rather than an assertion.
  bool get isAvailable;

  /// Encodes 16-bit mono PCM at 8 kHz into packed frames.
  ///
  /// [pcm] must be a whole number of frames; a partial frame is refused rather
  /// than padded, because padding silence onto the end changes the duration a
  /// receiver computes from the stream.
  PackedVoice encode(Uint8List pcm, {required VoiceMode mode});

  /// Decodes [packed] back to 16-bit mono PCM at 8 kHz.
  ///
  /// [ber] is the bit-error estimate in [0, 1] when the transport has one.
  /// Only [VoiceMode.standard] (1300) uses it — it soft-mutes above 0.15
  /// instead of inventing speech that was not there — and the other mode
  /// ignores it, so a caller with an estimate never needs two code paths.
  Uint8List decode(Uint8List packed, {required VoiceMode mode, double ber = 0});
}
