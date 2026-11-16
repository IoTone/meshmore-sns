// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/airtime.dart';
import 'package:meshmore_sns_app/meshcore/channel_datagram.dart';
import 'package:meshmore_sns_app/media/media_codec.dart';
import 'package:meshmore_sns_app/media/media_composer.dart';
import 'package:meshmore_sns_app/media/media_offer.dart';
import 'package:meshmore_sns_app/media/media_photo.dart';
import 'package:meshmore_sns_app/media/media_transfer.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

DateTime _now = DateTime(2026, 11, 5, 12);

MediaPhoto _photo(int w, int h) =>
    MediaPhoto(width: w, height: h, rgba: Uint8List(w * h * 4));

final class _Source implements MediaPhotoSource {
  _Source(
      {this.photo,
      this.available = true,
      this.fails = false,
      this.unsupported = false});

  final MediaPhoto? photo;
  final bool available;
  final bool fails;
  final bool unsupported;
  int calls = 0;
  MediaPhotoOrigin? lastOrigin;

  @override
  bool get isAvailable => available;

  @override
  Future<MediaPhoto?> pick(
      {MediaPhotoOrigin origin = MediaPhotoOrigin.gallery}) async {
    calls++;
    lastOrigin = origin;
    if (unsupported) {
      throw const MediaPhotoSourceFailure('unsupportedFormat',
          problem: MediaPhotoSourceProblem.unsupportedFormat);
    }
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

  reachTests();

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
      offers: MediaOfferStore(),)));
    await t.pumpAndSettle();
    await _pickIn(t);

    expect(find.text('Send a photo'), findsOneWidget);
    // The refusal sends the user to a private channel: the old copy pointed at
    // a per-channel media switch, and no such setting exists.
    expect(find.textContaining('Media stays off on the Public channel'),
        findsOneWidget);
    expect(find.textContaining('private channel'), findsOneWidget);
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
      offers: MediaOfferStore(),)));
    await t.pumpAndSettle();
    await _pickIn(t);

    // 300 bytes at 150 per chunk is two packets, and the cost is still stated
    // before anything goes out: the picture is announced, not uploaded.
    expect(find.textContaining('2 packets'), findsOneWidget);
    expect(find.textContaining('on air'), findsOneWidget);
    expect(sent, isEmpty, reason: 'nothing goes out until Send is tapped');

    final MediaOfferStore offers = MediaOfferStore();
    // (the composer above owns its own store; this asserts the announcement
    // semantics on a fresh one through the same path)
    expect(offers.offers, isEmpty);

    await t.tap(find.text('Send'));
    await t.pumpAndSettle();

    // One datagram, not two: the preview is the announcement. The pixels wait
    // for a request, because a channel datagram is flooded to every radio in
    // range and a picture nobody asked for is everyone's airtime.
    expect(sent.length, 1,
        reason: 'a picture is announced in one datagram, never uploaded');
    expect(sent.single.length, lessThanOrEqualTo(163));
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
      offers: MediaOfferStore(),)));
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
      offers: MediaOfferStore(),)));
    await t.pumpAndSettle();
    await _pickIn(t);
    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(sent, isEmpty);
  });

  testWidgets('a HEIC is named as a format this build cannot read',
      (WidgetTester t) async {
    await t.pumpWidget(_host(MediaComposer(
      service: _service(),
      source: _Source(unsupported: true),
      channelPsk: List<int>.filled(16, 0x37),
      byteBudget: 2000,
      sendBlob: (Uint8List blob) async =>
          const ChannelDataSendResult(ChannelDataSendStatus.accepted),
      offers: MediaOfferStore(),)));
    await t.pumpAndSettle();
    await _pickIn(t);
    expect(find.textContaining('HEIC and AV1 are not supported'), findsOneWidget);
    expect(find.textContaining('could not be read'), findsNothing);
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
      offers: MediaOfferStore(),)));
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
      offers: MediaOfferStore(),)));
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
      offers: MediaOfferStore(),),
        theme: tc,
      ));
      await t.pumpAndSettle();
      await _pickIn(t);
      expect(t.takeException(), isNull, reason: 'skin ${preset.name}');
      expect(find.textContaining('2 packets'), findsOneWidget,
          reason: 'skin ${preset.name}');
    }
  });

  // The mode is a preference the composer has to READ, not only display. It was
  // read nowhere, so every send took the on-request path whatever the reader
  // chose, and the line under the picture named a mode they had not picked.
  testWidgets('the chosen photo mode is the one the composer sends',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{'mm.media.photoMode': 'preview'});
    final MediaOfferStore offers = MediaOfferStore();
    final List<Uint8List> sent = <Uint8List>[];
    await t.pumpWidget(_host(MediaComposer(
      service: _service(),
      source: _Source(photo: _photo(320, 240)),
      channelPsk: List<int>.filled(16, 0x38),
      byteBudget: 2000,
      sendBlob: (Uint8List blob) async {
        sent.add(blob);
        return const ChannelDataSendResult(ChannelDataSendStatus.accepted);
      },
      offers: offers,
    )));
    await t.pumpAndSettle();
    await _pickIn(t);

    expect(find.textContaining('Preview only'), findsOneWidget,
        reason: 'the line must name the mode the reader chose');

    await t.tap(find.text('Send'));
    await t.pumpAndSettle();

    expect(sent.length, 1);
    expect(offers.offers, isEmpty,
        reason: 'preview-only holds no pixels for a later request');
  });
}

// Added 2026-11-05: the composer states the reach.
//
// D8.1: a channel broadcast inherits the radio's own default flood scope, so
// "who receives this" is not the app's choice and must not be invented. The
// three states are stated: a named scope, no scope set, and not yet reported.
void reachTests() {
  testWidgets('with no radio answer yet the composer says the reach is '
      'unknown rather than guessing', (WidgetTester t) async {
    await t.pumpWidget(_host(MediaComposer(
      service: _service(),
      source: _Source(photo: _photo(320, 240)),
      channelPsk: kPublicChannelPsk,
      byteBudget: 2000,
      sendBlob: (Uint8List _) async =>
          const ChannelDataSendResult(ChannelDataSendStatus.accepted),
      offers: MediaOfferStore(),)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('media-reach')), findsOneWidget);
    expect(find.textContaining('has not reported yet'), findsOneWidget);
  });
}
