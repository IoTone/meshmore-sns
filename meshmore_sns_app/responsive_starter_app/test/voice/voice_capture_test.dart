// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/voice/voice_capture.dart';

/// Capture is where the product's promises meet the platform.
///
/// Three are testable without a microphone: the recorder is asked for exactly
/// 16-bit mono PCM at 8 kHz (anything else would need resampling before the
/// codec could encode it), the 20-second ceiling stops the recording itself
/// rather than truncating afterwards, and a platform that cannot give that PCM
/// is refused by name instead of being worked around.
void main() {
  group('the recorder is asked for the PCM the codec can encode', () {
    test('16-bit mono at 8 kHz, and the microphone is opened for nothing else',
        () async {
      final _FakePlatform platform = _FakePlatform();
      final PlatformVoiceCapture capture =
          PlatformVoiceCapture(platform: platform);
      expect(await capture.isAvailable(), isTrue);
      await capture.start();
      expect(platform.started, isTrue);
      expect(platform.sampleRate, 8000);
      expect(platform.channels, 1);
      await capture.dispose();
    });

    test('a 20-second take is 320,000 bytes and reports 20 seconds', () async {
      final _FakePlatform platform = _FakePlatform();
      final PlatformVoiceCapture capture =
          PlatformVoiceCapture(platform: platform);
      await capture.start();
      // 20 s × 8,000 samples × 2 bytes.
      platform.emit(Uint8List(kVoiceSampleRate * 2 * 20));
      final VoiceRecording r = await capture.stop();
      expect(r.pcm.length, 320000);
      expect(r.samples, 160000);
      expect(r.duration, const Duration(seconds: 20));
      expect(r.stoppedAtCeiling, isFalse);
      await capture.dispose();
    });
  });

  group('the ceiling stops the recording itself', () {
    test('it fires at the limit, says so, and the take ends there', () async {
      final _FakePlatform platform = _FakePlatform();
      int ceilingCalls = 0;
      // 30 ms instead of 20 s: the behaviour under test is that the timer stops
      // the recording and reports it, and the constant that production passes
      // is asserted separately below.
      final PlatformVoiceCapture capture = PlatformVoiceCapture(
        platform: platform,
        ceiling: const Duration(milliseconds: 30),
        onCeiling: () => ceilingCalls++,
      );
      await capture.start();
      platform.emit(Uint8List(400));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(ceilingCalls, 1, reason: 'the surface is told while it is watching');
      expect(platform.stopped, isTrue,
          reason: 'the recorder is stopped by the timer, not by the caller');
      final VoiceRecording r = await capture.stop();
      expect(r.stoppedAtCeiling, isTrue,
          reason: 'a look-alike reading is the defect: a note that stopped by '
              'itself must say so');
      await capture.dispose();
    });

    test('production passes 20 seconds, which is what the cost quote assumes',
        () {
      expect(kVoiceMaxDuration, const Duration(seconds: 20));
      expect(kVoiceSampleRate, 8000);
      expect(kVoiceChannels, 1);
      expect(kVoiceSampleRate * 2 * kVoiceMaxDuration.inSeconds, 320000);
    });
  });

  group('a platform that cannot give that PCM is refused by name', () {
    test('no microphone permission is its own refusal', () async {
      final _FakePlatform platform = _FakePlatform()..permission = false;
      final PlatformVoiceCapture capture =
          PlatformVoiceCapture(platform: platform);
      expect(await capture.isAvailable(), isFalse);
      await expectLater(
          capture.start(),
          throwsA(isA<VoiceCaptureException>().having(
              (VoiceCaptureException e) => e.refusal,
              'refusal',
              VoiceCaptureRefusal.permissionDenied)));
      expect(platform.started, isFalse);
      await capture.dispose();
    });

    test('no PCM encoder is its own refusal, and nothing is resampled',
        () async {
      final _FakePlatform platform = _FakePlatform()..pcmSupported = false;
      final PlatformVoiceCapture capture =
          PlatformVoiceCapture(platform: platform);
      await expectLater(
          capture.start(),
          throwsA(isA<VoiceCaptureException>().having(
              (VoiceCaptureException e) => e.refusal,
              'refusal',
              VoiceCaptureRefusal.pcmUnsupported)));
      expect(platform.started, isFalse,
          reason: 'the microphone is never opened for a format the codec '
              'cannot take');
      await capture.dispose();
    });

    test('a platform that refuses 8 kHz becomes the same typed refusal',
        () async {
      final _FakePlatform platform = _FakePlatform()..startThrows = true;
      final PlatformVoiceCapture capture =
          PlatformVoiceCapture(platform: platform);
      await expectLater(
          capture.start(),
          throwsA(isA<VoiceCaptureException>().having(
              (VoiceCaptureException e) => e.refusal,
              'refusal',
              VoiceCaptureRefusal.pcmUnsupported)));
      await capture.dispose();
    });
  });

  group('a cancelled take produces nothing', () {
    test('cancel discards the chunks and closes the recorder', () async {
      final _FakePlatform platform = _FakePlatform();
      final PlatformVoiceCapture capture =
          PlatformVoiceCapture(platform: platform);
      await capture.start();
      platform.emit(Uint8List(400));
      await capture.cancel();
      final VoiceRecording r = await capture.stop();
      expect(r.pcm, isEmpty);
      expect(platform.stopped, isTrue);
      await capture.dispose();
    });
  });
}

/// The platform seam as the capture sees it: permission, PCM support, a byte
/// stream, and stop. Nothing else, so the capture cannot come to depend on a
/// `record` feature no test covers.
final class _FakePlatform implements VoiceRecorderPlatform {
  // Broadcast, so closing it completes even when nothing ever listened: a
  // single-subscription controller's close() waits for a listener that a
  // refusal test never creates, and the await then hangs the test.
  StreamController<Uint8List> _stream =
      StreamController<Uint8List>.broadcast();
  bool permission = true;
  bool pcmSupported = true;
  bool startThrows = false;
  bool started = false;
  bool stopped = false;

  int? sampleRate;
  int? channels;

  void emit(Uint8List bytes) => _stream.add(bytes);

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> supportsPcm16() async => pcmSupported;

  @override
  Future<Stream<Uint8List>> startStream({
    required int sampleRate,
    required int channels,
  }) async {
    if (startThrows) {
      throw StateError('the platform refused this sample rate');
    }
    started = true;
    stopped = false;
    this.sampleRate = sampleRate;
    this.channels = channels;
    _stream = StreamController<Uint8List>.broadcast();
    return _stream.stream;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_stream.isClosed) await _stream.close();
  }

  @override
  Future<void> dispose() async {
    if (!_stream.isClosed) await _stream.close();
  }
}
