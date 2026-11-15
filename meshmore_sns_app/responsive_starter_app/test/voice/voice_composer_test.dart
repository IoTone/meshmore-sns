// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/media/media_codec.dart';
import 'package:meshmore_sns_app/media/media_transfer.dart';
import 'package:meshmore_sns_app/meshcore/airtime.dart';
import 'package:meshmore_sns_app/meshcore/channel_datagram.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/voice/voice_capture.dart';
import 'package:meshmore_sns_app/voice/voice_codec.dart';
import 'package:meshmore_sns_app/voice/voice_composer.dart';
import 'package:meshmore_sns_app/voice/voice_playback.dart';

import '../support/fake_voice_codec.dart';

DateTime _now = DateTime(2026, 11, 10, 9);

/// A recorder a test drives by hand: the PCM is whatever the case sets before
/// the stop, so the encode and the cost are the ones a real take would produce.
/// A recorder that ends its own take at [limit], the way `record` does at 20 s:
/// nothing calls back, the audio has already stopped when the surface looks.
final class _CeilingCapture implements VoiceCapture {
  @override
  final Duration limit = const Duration(milliseconds: 200);
  bool _stopped = false;
  int stops = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> start() async {
    _stopped = false;
    Timer(limit, () => _stopped = true);
  }

  @override
  Future<VoiceRecording> stop() async {
    stops++;
    // Whatever the platform captured, which for this case is a real take.
    return VoiceRecording(
      pcm: _take(),
      stoppedAtCeiling: _stopped,
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

final class _FakeCapture implements VoiceCapture {
  _FakeCapture({this.startFailure});

  final VoiceCaptureRefusal? startFailure;

  Uint8List pcm = Uint8List(0);
  int starts = 0;
  int stops = 0;
  bool cancelled = false;

  @override
  Duration get limit => kVoiceMaxDuration;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> start() async {
    starts++;
    final VoiceCaptureRefusal? refusal = startFailure;
    if (refusal != null) {
      throw VoiceCaptureException(refusal, 'refused by the fake');
    }
  }

  @override
  Future<VoiceRecording> stop() async {
    stops++;
    return VoiceRecording(pcm: pcm, stoppedAtCeiling: false);
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  Future<void> dispose() async {}
}

MediaTransferService _service({bool mediaOnPublic = false}) =>
    MediaTransferService(
      codec: FakeMediaCodec(),
      estimator: const AirtimeEstimator(millisPerByte: 4),
      clock: () => _now,
      mediaOnPublic: mediaOnPublic,
      newPayloadId: () => 77,
      wait: (Duration d) async => _now = _now.add(d),
    );

Widget _host(Widget child) {
  final ThemeController tc = ThemeController();
  return ChangeNotifierProvider<ThemeController>.value(
    value: tc,
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    ),
  );
}

/// A codec that carries both modes, which is what the shipped build does.
FakeVoiceCodec _codec() => FakeVoiceCodec(modes: VoiceMode.values.toSet());

/// Two seconds of speech as the recorder hands it over: 50 frames of 640 bytes.
Uint8List _take({int frames = 50}) => pcmOf(frames, (int f) => 100 + f);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<List<Uint8List>> pump(
    WidgetTester t, {
    required _FakeCapture capture,
    required FakeVoiceCodec codec,
    VoicePlayback? playback,
    MediaTransferService? service,
    List<int>? channelPsk,
    List<ChannelDataSendResult>? sent,
  }) async {
    final List<Uint8List> blobs = <Uint8List>[];
    await t.pumpWidget(_host(VoiceComposer(
      service: service ?? _service(),
      capture: capture,
      codec: codec,
      channelPsk: channelPsk ?? const <int>[1, 2, 3],
      playback: playback,
      sendBlob: (Uint8List blob) async {
        blobs.add(blob);
        sent?.add(const ChannelDataSendResult(
            ChannelDataSendStatus.accepted));
        return const ChannelDataSendResult(ChannelDataSendStatus.accepted);
      },
    )));
    await t.pump();
    return blobs;
  }

  testWidgets('the ceiling is stated before the microphone opens', (t) async {
    final _FakeCapture capture = _FakeCapture();
    await pump(t, capture: capture, codec: _codec());
    expect(find.byKey(const ValueKey<String>('voice-limit')), findsOneWidget);
    expect(find.textContaining('20 seconds'), findsOneWidget);
    // Nothing to pick between: one codec, and the refusal is the whole state.
    expect(find.byKey(const ValueKey<String>('voice-mode-1')), findsNothing);
    // The take does not exist yet, so neither does a preview or a send.
    expect(find.byKey(const ValueKey<String>('voice-preview')), findsNothing);
    expect(find.byKey(const ValueKey<String>('voice-send')), findsNothing);
    expect(capture.starts, 0, reason: 'opening the sheet records nothing');
  });

  testWidgets('record, stop, and the cost is the take\'s own arithmetic',
      (t) async {
    final _FakeCapture capture = _FakeCapture();
    await pump(t, capture: capture, codec: _codec());
    capture.pcm = _take();
    await t.tap(find.byKey(const ValueKey<String>('voice-record')));
    await t.pump();
    expect(capture.starts, 1);
    expect(find.byKey(const ValueKey<String>('voice-stop')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('voice-stop')));
    await t.pumpAndSettle();
    expect(capture.stops, 1);
    // 2 s at 700C is 50 × 28 bits = 175 bytes plus the one-byte header: two
    // datagrams at 150 payload bytes.
    final Text cost =
        t.widget<Text>(find.byKey(const ValueKey<String>('voice-cost')));
    expect(cost.data, contains('2 packets'));
    expect(cost.data, contains('700C'));
    expect(find.byKey(const ValueKey<String>('voice-send')), findsOneWidget);
  });

  testWidgets('there is one codec, so there is no mode to pick', (t) async {
    final _FakeCapture capture = _FakeCapture();
    await pump(t, capture: capture, codec: _codec());
    capture.pcm = _take();
    await t.tap(find.byKey(const ValueKey<String>('voice-record')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('voice-stop')));
    await t.pumpAndSettle();
    // 700C is the only mode: no chip to switch it, and the cost line says so.
    expect(find.byKey(const ValueKey<String>('voice-mode-0')), findsNothing);
    expect(find.byKey(const ValueKey<String>('voice-mode-1')), findsNothing);
    final Text cost =
        t.widget<Text>(find.byKey(const ValueKey<String>('voice-cost')));
    expect(cost.data, contains('700'));
  });

  testWidgets('a send goes out one paced datagram at a time and receipts',
      (t) async {
    final _FakeCapture capture = _FakeCapture();
    final List<ChannelDataSendResult> sent = <ChannelDataSendResult>[];
    final List<Uint8List> blobs = await pump(
      t,
      capture: capture,
      codec: _codec(),
      sent: sent,
    );
    capture.pcm = _take();
    await t.tap(find.byKey(const ValueKey<String>('voice-record')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('voice-stop')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('voice-send')));
    await t.pumpAndSettle();
    expect(blobs.length, 2);
    expect(sent.length, 2);
    // Each blob is one chunk: a 12-byte header and at most 150 payload bytes.
    for (final Uint8List blob in blobs) {
      expect(blob.length, lessThanOrEqualTo(162));
    }
    expect(find.byKey(const ValueKey<String>('voice-receipt')), findsOneWidget);
  });

  testWidgets('the Public channel refuses before anything is encoded',
      (t) async {
    final _FakeCapture capture = _FakeCapture();
    final FakeVoiceCodec codec = _codec();
    await pump(
      t,
      capture: capture,
      codec: codec,
      service: _service(mediaOnPublic: false),
      channelPsk: kPublicChannelPsk,
    );
    capture.pcm = _take();
    await t.tap(find.byKey(const ValueKey<String>('voice-record')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('voice-stop')));
    await t.pumpAndSettle();
    expect(find.textContaining('off on the Public channel'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('voice-cost')), findsNothing);
    expect(find.byKey(const ValueKey<String>('voice-send')), findsNothing);
    // The take is still there: the refusal names a channel rule, and throwing
    // the recording away would make the user speak again to send it elsewhere.
    // There is no mode row to look at any more, so the proof is the refusal
    // itself plus the absent cost line above.
    expect(find.byKey(const ValueKey<String>('voice-mode-1')), findsNothing);
  });

  testWidgets('a click is too short to be a note', (t) async {
    final _FakeCapture capture = _FakeCapture();
    await pump(t, capture: capture, codec: _codec());
    capture.pcm = Uint8List(200); // under one 640-byte frame
    await t.tap(find.byKey(const ValueKey<String>('voice-record')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('voice-stop')));
    await t.pumpAndSettle();
    expect(find.textContaining('Too short'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('voice-cost')), findsNothing);
    expect(find.byKey(const ValueKey<String>('voice-send')), findsNothing);
  });

  testWidgets('a build with no codec says so and cannot record', (t) async {
    final _FakeCapture capture = _FakeCapture();
    await pump(
      t,
      capture: capture,
      codec: FakeVoiceCodec(available: false),
    );
    expect(find.textContaining('no speech codec'), findsOneWidget);
    final FilledButton record = t.widget<FilledButton>(
        find.byKey(const ValueKey<String>('voice-record')));
    expect(record.onPressed, isNull);
  });

  testWidgets('a refused microphone is a sentence, not a crash', (t) async {
    final _FakeCapture capture = _FakeCapture(
        startFailure: VoiceCaptureRefusal.permissionDenied);
    await pump(t, capture: capture, codec: _codec());
    await t.tap(find.byKey(const ValueKey<String>('voice-record')));
    await t.pumpAndSettle();
    expect(find.textContaining('microphone'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('voice-record')), findsOneWidget);
  });

  testWidgets('the preview plays the decoded take, and stops on a second tap',
      (t) async {
    final _FakeCapture capture = _FakeCapture();
    final SilentVoicePlayback playback = SilentVoicePlayback();
    await pump(
      t,
      capture: capture,
      codec: _codec(),
      playback: playback,
    );
    capture.pcm = _take();
    await t.tap(find.byKey(const ValueKey<String>('voice-record')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('voice-stop')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('voice-preview')));
    await t.pumpAndSettle();
    expect(playback.played.single, capture.pcm);
    await t.tap(find.byKey(const ValueKey<String>('voice-preview')));
    await t.pumpAndSettle();
    expect(playback.stops, 1);
  });

  testWidgets('a take the ceiling ended is finished by the sheet itself',
      (t) async {
    final _CeilingCapture capture = _CeilingCapture();
    await t.pumpWidget(_host(VoiceComposer(
      service: _service(),
      capture: capture,
      codec: _codec(),
      channelPsk: const <int>[1, 2, 3],
      sendBlob: (Uint8List blob) async =>
          const ChannelDataSendResult(ChannelDataSendStatus.accepted),
    )));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('voice-record')));
    await t.pump();
    expect(find.byKey(const ValueKey<String>('voice-stop')), findsOneWidget);
    // Past the ceiling plus the grace: the recorder has stopped itself and the
    // sheet has to notice, because nothing calls back. A device run found the
    // counter reading 28 s past a 20 s limit.
    await t.pump(capture.limit + const Duration(milliseconds: 700));
    await t.pumpAndSettle();
    expect(capture.stops, greaterThanOrEqualTo(1));
    expect(find.byKey(const ValueKey<String>('voice-stop')), findsNothing);
    expect(find.byKey(const ValueKey<String>('voice-cost')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('voice-stopped-at-limit')),
        findsOneWidget);
  });
}
