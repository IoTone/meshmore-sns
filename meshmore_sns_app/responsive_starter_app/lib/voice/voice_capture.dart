// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart' as rec;


/// The one capture configuration the speech codec accepts.
///
/// Codec 2 takes raw 16-bit mono PCM at 8 kHz and nothing else, so the recorder
/// is asked for exactly that: any container (AAC, Opus, AMR) would have to be
/// decoded before the codec could encode it, which is two lossy stages and a
/// second native dependency for no gain.
const int kVoiceSampleRate = 8000;
const int kVoiceChannels = 1;

/// The longest note the app records.
///
/// Not a technical limit — Codec 2 would happily encode longer — but the
/// airtime one: 20 seconds at 700C is 1,750 bytes, twelve datagrams at 150
/// payload bytes each, and at 1300 it is 3,250 bytes, twenty-two. Past that one
/// message is competing with the hourly budget, so the ceiling is stated before
/// the microphone opens rather than enforced by truncation after.
const Duration kVoiceMaxDuration = Duration(seconds: 20);

/// Why a recording did not start.
enum VoiceCaptureRefusal {
  /// The microphone permission is not granted.
  permissionDenied,

  /// The platform cannot record the PCM the codec needs. Reported rather than
  /// worked around: resampling silently would either change the pitch the codec
  /// is tuned for or cost a second native dependency, and either way the user
  /// would be told nothing.
  pcmUnsupported,
}

/// Thrown when a recording cannot start.
final class VoiceCaptureException implements Exception {
  const VoiceCaptureException(this.refusal, this.detail);

  final VoiceCaptureRefusal refusal;
  final String detail;

  @override
  String toString() => 'VoiceCaptureException(${refusal.name}: $detail)';
}

/// One finished recording: raw PCM, and whether the ceiling stopped it.
final class VoiceRecording {
  const VoiceRecording({required this.pcm, required this.stoppedAtCeiling});

  /// 16-bit mono PCM at [kVoiceSampleRate], in host byte order.
  final Uint8List pcm;

  /// True when [kVoiceMaxDuration] ended the recording rather than the user.
  /// A surface says so, because a note that stopped by itself is otherwise
  /// indistinguishable from a button that was ignored.
  final bool stoppedAtCeiling;

  Duration get duration => Duration(
      microseconds:
          pcm.isEmpty ? 0 : pcm.length * 500000 ~/ kVoiceSampleRate);

  int get samples => pcm.length ~/ 2;
}

/// The handful of `record` calls capture needs.
///
/// `AudioRecorder` is a concrete class over platform channels, so this interface
/// is what lets a widget test prove the configuration handed to the platform and
/// the behaviour of the 20-second ceiling. Keeping it this narrow also means the
/// capture cannot quietly start depending on a `record` feature that no test
/// covers.
abstract interface class VoiceRecorderPlatform {
  Future<bool> hasPermission();

  /// True when the platform can encode 16-bit PCM.
  Future<bool> supportsPcm16();

  Future<Stream<Uint8List>> startStream({
    required int sampleRate,
    required int channels,
  });

  Future<void> stop();

  Future<void> dispose();
}

/// [VoiceRecorderPlatform] over the `record` package.
///
/// The three platform effects are deliberately off: they alter the signal after
/// capture, and a codec tuned for an 8 kHz speech band does not need a second
/// compressor in front of it.
final class RecordPackagePlatform implements VoiceRecorderPlatform {
  RecordPackagePlatform({rec.AudioRecorder? recorder})
      : _recorder = recorder ?? rec.AudioRecorder();

  final rec.AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<bool> supportsPcm16() =>
      _recorder.isEncoderSupported(rec.AudioEncoder.pcm16bits);

  @override
  Future<Stream<Uint8List>> startStream({
    required int sampleRate,
    required int channels,
  }) =>
      _recorder.startStream(rec.RecordConfig(
        encoder: rec.AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: channels,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ));

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// A capture session the surfaces drive.
abstract interface class VoiceCapture {
  /// True when the microphone is granted and the platform can record the PCM
  /// the codec needs.
  Future<bool> isAvailable();

  /// Starts recording, or throws a [VoiceCaptureException].
  ///
  /// The ceiling is a timer started here, not a check at stop time: stopping at
  /// 20 s is what keeps the memory bound and the quoted cost true, whereas
  /// truncating afterwards would record past the limit and then throw the end
  /// away.
  Future<void> start();

  /// Stops and returns what was recorded.
  Future<VoiceRecording> stop();

  /// Abandons the recording without producing one.
  Future<void> cancel();

  Future<void> dispose();
}

/// [VoiceCapture] over a [VoiceRecorderPlatform].
final class PlatformVoiceCapture implements VoiceCapture {
  PlatformVoiceCapture({
    VoiceRecorderPlatform? platform,
    this.onCeiling,
    Duration ceiling = kVoiceMaxDuration,
  })  : _platform = platform ?? RecordPackagePlatform(),
        _ceiling = ceiling;

  final VoiceRecorderPlatform _platform;

  /// Called when the ceiling stopped the recording, so a surface can say so
  /// while the user is still looking at it.
  final void Function()? onCeiling;

  /// Injected so a test can watch the ceiling act without waiting twenty
  /// seconds; production always passes the constant.
  final Duration _ceiling;

  final List<Uint8List> _chunks = <Uint8List>[];
  StreamSubscription<Uint8List>? _sub;
  Timer? _ceilingTimer;
  bool _stoppedAtCeiling = false;
  bool _recording = false;

  /// What a full take is allowed to run for, for a surface that states the
  /// limit before the microphone opens.
  Duration get limit => _ceiling;

  @override
  Future<bool> isAvailable() async {
    if (!await _platform.hasPermission()) return false;
    return _platform.supportsPcm16();
  }

  @override
  Future<void> start() async {
    if (!await _platform.hasPermission()) {
      throw const VoiceCaptureException(
          VoiceCaptureRefusal.permissionDenied, 'the microphone is not granted');
    }
    if (!await _platform.supportsPcm16()) {
      throw const VoiceCaptureException(VoiceCaptureRefusal.pcmUnsupported,
          'this device cannot record 16-bit PCM');
    }
    _chunks.clear();
    _stoppedAtCeiling = false;
    final Stream<Uint8List> stream;
    try {
      stream = await _platform.startStream(
          sampleRate: kVoiceSampleRate, channels: kVoiceChannels);
    } catch (e) {
      // Anything the platform raises here means the same thing to the caller:
      // the microphone could not be opened in the format the codec needs.
      // `record` reports an unsupported sample rate as a PlatformException, but
      // a plugin that fails its own state check raises a StateError, and that is
      // an Error rather than an Exception — so catching only `Exception` let one
      // shape of failure escape as an untyped crash.
      _recording = false;
      throw VoiceCaptureException(VoiceCaptureRefusal.pcmUnsupported,
          'the platform refused 16-bit PCM at $kVoiceSampleRate Hz: $e');
    }
    _recording = true;
    _sub = stream.listen(_chunks.add);
    _ceilingTimer = Timer(_ceiling, () {
      if (!_recording) return;
      _stoppedAtCeiling = true;
      onCeiling?.call();
      unawaited(stop());
    });
  }

  @override
  Future<VoiceRecording> stop() async {
    _ceilingTimer?.cancel();
    _ceilingTimer = null;
    if (!_recording) {
      return VoiceRecording(
          pcm: Uint8List(0), stoppedAtCeiling: _stoppedAtCeiling);
    }
    _recording = false;
    await _platform.stop();
    await _sub?.cancel();
    _sub = null;
    final int total =
        _chunks.fold<int>(0, (int n, Uint8List c) => n + c.length);
    final Uint8List pcm = Uint8List(total);
    int at = 0;
    for (final Uint8List c in _chunks) {
      pcm.setAll(at, c);
      at += c.length;
    }
    _chunks.clear();
    return VoiceRecording(pcm: pcm, stoppedAtCeiling: _stoppedAtCeiling);
  }

  @override
  Future<void> cancel() async {
    _ceilingTimer?.cancel();
    _ceilingTimer = null;
    _chunks.clear();
    if (_recording) {
      _recording = false;
      await _platform.stop();
    }
    await _sub?.cancel();
    _sub = null;
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _platform.dispose();
  }
}
