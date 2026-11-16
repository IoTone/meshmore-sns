// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'voice_capture.dart';

/// Why a note did not play.
enum VoicePlaybackFailure {
  /// The platform player could not be reached at all: a harness, or a build
  /// where the plugin is absent. Named separately from a refusal because the
  /// answer is "this build cannot play", not "try again".
  unavailable,

  /// The player was reached and refused the source. A device that cannot play
  /// an 8 kHz WAV is unusual but not impossible, and it is worth a sentence.
  refused,
}

/// A playback failure with the detail a log line needs.
final class VoicePlaybackException implements Exception {
  const VoicePlaybackException(this.failure, this.detail);

  final VoicePlaybackFailure failure;
  final String detail;

  @override
  String toString() => 'VoicePlaybackException(${failure.name}: $detail)';
}

/// The WAV container a platform player can take.
///
/// Codec 2 decodes to raw PCM and every platform player wants a container, so
/// the conversion happens in one function with a pinned header rather than in
/// a surface: the app already ships `audioplayers` for its cue assets, its
/// `BytesSource` takes a byte array, and a 44-byte RIFF header is the whole of
/// the difference between the codec's output and something Android's
/// `MediaPlayer` will open.
///
/// The format is the codec's own and is not configurable: 16-bit mono at 8 kHz
/// is what Codec 2 produces, and resampling here would either change the pitch
/// or add a second native dependency for no gain.
Uint8List wavFromPcm(
  Uint8List pcm, {
  int sampleRate = kVoiceSampleRate,
  int channels = kVoiceChannels,
}) {
  if (sampleRate <= 0) {
    throw ArgumentError.value(sampleRate, 'sampleRate', 'must be > 0');
  }
  if (channels <= 0) {
    throw ArgumentError.value(channels, 'channels', 'must be > 0');
  }
  final int blockAlign = channels * 2;
  if (pcm.length % blockAlign != 0) {
    throw ArgumentError.value(pcm.length, 'pcm',
        'is not a whole number of $blockAlign-byte sample frames');
  }
  const int headerBytes = 44;
  final Uint8List out = Uint8List(headerBytes + pcm.length);
  final ByteData view = ByteData.sublistView(out);
  void ascii(int at, String s) {
    for (int i = 0; i < s.length; i++) {
      out[at + i] = s.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  // Everything after this field: the 36 header bytes that follow plus the data.
  view.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  view.setUint16(20, 1, Endian.little); // PCM, uncompressed
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * blockAlign, Endian.little); // byte rate
  view.setUint16(32, blockAlign, Endian.little);
  view.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  view.setUint32(40, pcm.length, Endian.little);
  out.setRange(headerBytes, out.length, pcm);
  return out;
}

/// Plays one note. A seam for the same reason [VoiceCodec] is one: production
/// has a single implementation, a widget test needs none, and the sentence for
/// "this build cannot play" lives with the failure rather than in three
/// surfaces.
abstract interface class VoicePlayback {
  /// True when this build has a player. A build without one still decodes and
  /// still sends; only the play control is refused.
  bool get isAvailable;

  /// Plays 16-bit mono PCM at 8 kHz from the first sample. A second call stops
  /// whatever was playing, because two notes at once is never what the user
  /// asked for.
  Future<void> play(Uint8List pcm);

  Future<void> stop();

  /// Fires when a note plays to its end or is stopped by the player itself.
  Stream<void> get onComplete;

  Future<void> dispose();
}

/// [VoicePlayback] over the `audioplayers` package the app already ships.
final class AudioplayersVoicePlayback implements VoicePlayback {
  AudioplayersVoicePlayback({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  bool get isAvailable => true;

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> play(Uint8List pcm) async {
    try {
      await _player.stop();
      await _player.play(BytesSource(
        wavFromPcm(pcm),
        mimeType: 'audio/wav',
      ));
    } on MissingPluginException catch (e) {
      throw VoicePlaybackException(
          VoicePlaybackFailure.unavailable, 'no audio player here: ${e.message}');
    } on PlatformException catch (e) {
      throw VoicePlaybackException(
          VoicePlaybackFailure.refused, e.message ?? e.code);
    } on ArgumentError catch (e) {
      // `wavFromPcm` refuses a half sample; the surface says the note is
      // broken rather than the player.
      throw VoicePlaybackException(VoicePlaybackFailure.refused, '$e');
    }
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// A player that keeps what it was asked to play and plays nothing.
///
/// The widget tests need to prove that the preview and the received-note row
/// hand over the right PCM — the decoded frames, once, in order — without a
/// platform channel. It also records the stop calls, because a note that keeps
/// playing after the sheet closes is a defect a fake can catch.
final class SilentVoicePlayback implements VoicePlayback {
  SilentVoicePlayback({this.available = true});

  final bool available;

  /// Every PCM buffer handed to [play], in order.
  final List<Uint8List> played = <Uint8List>[];

  int stops = 0;

  final StreamController<void> _complete = StreamController<void>.broadcast();

  @override
  bool get isAvailable => available;

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  Future<void> play(Uint8List pcm) async {
    if (!available) {
      throw const VoicePlaybackException(
          VoicePlaybackFailure.unavailable, 'this build has no audio player');
    }
    played.add(Uint8List.fromList(pcm));
  }

  /// Ends the current note, as a real player would when it runs to the end.
  void finish() => _complete.add(null);

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    await _complete.close();
  }
}
