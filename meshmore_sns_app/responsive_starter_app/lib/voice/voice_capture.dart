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

/// Bytes of PCM in one 40 ms Codec 2 frame: 320 samples at two bytes each.
///
/// Both modes carry 40 ms per frame, so this is the one alignment the recorder
/// and every decoder agree on, and it is why a take is trimmed here rather than
/// in the codec: the platform streams whatever byte counts it likes, and a
/// recording whose last partial frame reached the encoder would be refused by
/// the codec on almost every real press of the button.
const int kVoicePcmFrameBytes = kVoiceSampleRate * 2 * 40 ~/ 1000;

/// How long the recorder's stream is given to drain after the platform stops.
///
/// `record` resolves its stop before every queued event is necessarily
/// delivered, so the subscription is cancelled a moment later rather than at
/// once. Thirty milliseconds is below what anyone hears as a delay and enough
/// for the plugin's own controller to hand over what it already had.
const Duration kVoiceStopDrain = Duration(milliseconds: 30);

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
  /// How long one take may run. Stated before the microphone opens and used by
  /// a surface to notice that the capture stopped itself at the ceiling, which
  /// no callback reports: the recorder ends the take quietly, and a composer
  /// that only listens for its own stop button sits on "Recording" past the
  /// limit while the audio has already ended.
  Duration get limit;

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

  /// The take the last stop produced, so asking twice returns it twice
  /// instead of an empty buffer.
  ///
  /// This matters because the 20-second ceiling stops the recording itself: a
  /// surface whose own timer fires at the same moment asks for a take that a
  /// `_recording == false` check used to answer with zero bytes, and a note
  /// that ran to the ceiling — the common case for a long message — arrived
  /// empty with `stoppedAtCeiling` set. One future is shared by every caller,
  /// so the ceiling's stop and the button's stop are the same stop.
  Future<VoiceRecording>? _stopping;
  VoiceRecording? _take;   // the take produced by the last stop()

  @override
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
    _stopping = null;
    _take = null;
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

  /// Stops and returns the take.
  ///
  /// Idempotent: the ceiling's own stop, a surface's stop and a second tap all
  /// resolve to one take, because the first caller's future is shared and its
  /// result is kept. A stop on a capture that never started is an empty take,
  /// which is a fact rather than an error.
  @override
  Future<VoiceRecording> stop() {
    final Future<VoiceRecording>? running = _stopping;
    if (running != null) return running;
    final VoiceRecording? finished = _take;
    if (finished != null) return Future<VoiceRecording>.value(finished);
    return _stopping = _stopInternal().then((VoiceRecording take) {
      _take = take;
      return take;
    });
  }

  Future<VoiceRecording> _stopInternal() async {
    _ceilingTimer?.cancel();
    _ceilingTimer = null;
    if (!_recording) {
      return VoiceRecording(
          pcm: Uint8List(0), stoppedAtCeiling: _stoppedAtCeiling);
    }
    _recording = false;
    await _platform.stop();
    await Future<void>.delayed(kVoiceStopDrain);
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
    // Cut back to whole 40 ms frames. The tail beyond the last frame is at most
    // 39 ms of speech and is dropped rather than padded, because padding
    // silence changes the duration a receiver computes from the stream and a
    // stream that is not a whole number of frames is refused by every decoder
    // on the path.
    final int whole = total - (total % kVoicePcmFrameBytes);
    final Uint8List usable = whole <= 0
        ? Uint8List(0)
        : (whole == total ? pcm : Uint8List.fromList(pcm.sublist(0, whole)));
    return VoiceRecording(pcm: usable, stoppedAtCeiling: _stoppedAtCeiling);
  }

  @override
  Future<void> cancel() async {
    _ceilingTimer?.cancel();
    _ceilingTimer = null;
    _stopping = null;
    _take = null;
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
