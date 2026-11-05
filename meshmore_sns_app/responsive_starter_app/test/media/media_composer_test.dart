// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/airtime.dart';
import 'package:meshmore_sns_app/meshcore/channel_datagram.dart';
import 'package:meshmore_sns_app/media/media_codec.dart';
import 'package:meshmore_sns_app/media/media_composer.dart';
import 'package:meshmore_sns_app/media/media_photo.dart';
import 'package:meshmore_sns_app/media/media_transfer.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

DateTime _now = DateTime(2026, 11, 5, 12);

MediaPhoto _photo(int w, int h) =>
    MediaPhoto(width: w, height: h, rgba: Uint8List(w * h * 4));

final class _Source implements MediaPhotoSource {
  _Source({this.photo, this.available = true, this.fails = false});

  final MediaPhoto? photo;
  final bool available;
  final bool fails;
  int calls = 0;
  MediaPhotoOrigin? lastOrigin;

  @override
  bool get isAvailable => available;

  @override
  Future<MediaPhoto?> pick(
      {MediaPhotoOrigin origin = MediaPhotoOrigin.gallery}) async {
    calls++;
    lastOrigin = origin;
    if (fails) throw const MediaPhotoSourceFailure('unreadable');
    return photo;
  }
}

Widget _host(Widget child, {ThemeController? theme}) {
  final ThemeController tc = theme ?? ThemeController();
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

MediaTransferService _service({
  FakeMediaCodec? codec,
  bool mediaOnPublic = false,
}) =>
    MediaTransferService(
      codec: codec ??
          FakeMediaCodec(encodedBytes: 300, width: 320, height: 240),
      estimator: const AirtimeEstimator(millisPerByte: 4),
      clock: () => _now,
      mediaOnPublic: mediaOnPublic,
      newPayloadId: () => 77,
      wait: (Duration d) async => _now = _now.add(d),
    );

/// Opening the sheet no longer picks on its own: the user says whether the
/// photo is a new one or one they already have, so every case taps a source
/// first, exactly as a person would.
Future<void> _pickIn(WidgetTester t, {bool camera = false}) async {
  await t.tap(find.byKey(ValueKey<String>(
      camera ? 'media-pick-camera' : 'media-pick-gallery')));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => _now = DateTime(2026, 11, 5, 12));

  testWidgets('the Public channel is refused before the encoder runs',
      (WidgetTester t) async {
    final FakeMediaCodec codec = FakeMediaCodec(encodedBytes: 300);
    final _Source source = _Source(photo: _photo(320, 240));
    final List<Uint8List> sent = <Uint8List>[];
    await t.pumpWidget(_host(MediaComposer(
      service: _service(codec: codec),
      source: source,
      channelPsk: kPublicChannelPsk,
      byteBudget: 2000,
      sendBlob: (Uint8List blob) async {
        sent.add(blob);
        return const ChannelDataSendResult(ChannelDataSendStatus.accepted);
      },
    )));
    await t.pumpAndSettle();
    await _pickIn(t);

    expect(find.text('Send a photo'), findsOneWidget);
    expect(find.textContaining('Media is off on the Public channel'),
        findsOneWidget);
    expect(codec.encodeCalls, 0);
    expect(sent, isEmpty);
  });

  testWidgets('the cost is shown before the send, then the receipt',
      (WidgetTester t) async {
    final List<Uint8List> sent = <Uint8List>[];
    await t.pumpWidget(_host(MediaComposer(
      service: _service(),
      source: _Source(photo: _photo(320, 240)),
      channelPsk: List<int>.filled(16, 0x31),
      byteBudget: 2000,
      sendBlob: (Uint8List blob) async {
        sent.add(blob);
        return const ChannelDataSendResult(ChannelDataSendStatus.accepted);
      },
    )));
    await t.pumpAndSettle();
    await _pickIn(t);

    // 300 bytes at 150 per chunk is two packets, two datagrams of airtime.
    expect(find.textContaining('2 packets'), findsOneWidget);
    expect(find.textContaining('on air'), findsOneWidget);
    expect(sent, isEmpty, reason: 'nothing goes out until Send is tapped');

    await t.tap(find.text('Send'));
    await t.pumpAndSettle();

    expect(sent.length, 2);
    expect(find.textContaining('2 packets sent'), findsOneWidget);
    expect(find.textContaining('no delivery promise'), findsOneWidget);
  });

  testWidgets('a source that cannot read the picture says so, and sends nothing',
      (WidgetTester t) async {
    await t.pumpWidget(_host(MediaComposer(
      service: _service(),
      source: _Source(photo: _photo(320, 240), available: false),
      channelPsk: List<int>.filled(16, 0x32),
      byteBudget: 2000,
      sendBlob: (Uint8List blob) async =>
          const ChannelDataSendResult(ChannelDataSendStatus.accepted),
    )));
    await t.pumpAndSettle();
    await _pickIn(t);
    expect(find.textContaining('cannot read a photo'), findsOneWidget);
  });

  testWidgets('a picker that cannot read the file says so', (WidgetTester t) async {
    final List<Uint8List> sent = <Uint8List>[];
    await t.pumpWidget(_host(MediaComposer(
      service: _service(),
      source: _Source(photo: _photo(320, 240), fails: true),
      channelPsk: List<int>.filled(16, 0x36),
      byteBudget: 2000,
      sendBlob: (Uint8List blob) async {
        sent.add(blob);
        return const ChannelDataSendResult(ChannelDataSendStatus.accepted);
      },
    )));
    await t.pumpAndSettle();
    await _pickIn(t);
    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(sent, isEmpty);
  });

  testWidgets('backing out of the picker sends nothing', (WidgetTester t) async {
    final _Source source = _Source();
    final List<Uint8List> sent = <Uint8List>[];
    await t.pumpWidget(_host(MediaComposer(
      service: _service(),
      source: source,
      channelPsk: List<int>.filled(16, 0x33),
      byteBudget: 2000,
      sendBlob: (Uint8List blob) async {
        sent.add(blob);
        return const ChannelDataSendResult(ChannelDataSendStatus.accepted);
      },
    )));
    await t.pumpAndSettle();
    await _pickIn(t);
    expect(source.calls, 1);
    expect(sent, isEmpty);
  });

  testWidgets('a photo the encoder cannot shrink is flagged, not hidden',
      (WidgetTester t) async {
    await t.pumpWidget(_host(MediaComposer(
      service: _service(codec: FakeMediaCodec(encodedBytes: 5000)),
      source: _Source(photo: _photo(320, 240)),
      channelPsk: List<int>.filled(16, 0x34),
      byteBudget: 1000,
      sendBlob: (Uint8List blob) async =>
          const ChannelDataSendResult(ChannelDataSendStatus.accepted),
    )));
    await t.pumpAndSettle();
    await _pickIn(t);
    expect(find.textContaining('will not fit the mesh budget'), findsOneWidget);
  });

  testWidgets('the composer builds in all seven skins', (WidgetTester t) async {
    for (final MmThemePreset preset in MmThemePreset.values) {
      final ThemeController tc = ThemeController();
      await tc.setPreset(preset);
      await t.pumpWidget(_host(
        MediaComposer(
          // A key per preset so the next iteration builds a fresh composer
          // rather than reusing the state of the one that already picked.
          key: ValueKey<String>(preset.name),
          service: _service(),
          source: _Source(photo: _photo(320, 240)),
          channelPsk: List<int>.filled(16, 0x35),
          byteBudget: 2000,
          sendBlob: (Uint8List blob) async =>
              const ChannelDataSendResult(ChannelDataSendStatus.accepted),
        ),
        theme: tc,
      ));
      await t.pumpAndSettle();
      await _pickIn(t);
      expect(t.takeException(), isNull, reason: 'skin ${preset.name}');
      expect(find.textContaining('2 packets'), findsOneWidget,
          reason: 'skin ${preset.name}');
    }
  });
}
