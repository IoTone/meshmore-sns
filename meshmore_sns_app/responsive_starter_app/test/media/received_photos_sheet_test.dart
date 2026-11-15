// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/media/media_codec.dart';
import 'package:meshmore_sns_app/media/media_photo.dart';
import 'package:meshmore_sns_app/media/photo_inbox.dart';
import 'package:meshmore_sns_app/media/received_photos_sheet.dart';

/// The surface that makes a received picture visible.
///
/// Before this sheet existed a photo sent on a channel was reassembled and then
/// dropped: the sender's receipt said "accepted" and the receiver saw nothing.
class _FakeCodec implements MediaCodec {
  _FakeCodec({this.fail = false});

  final bool fail;
  int decodes = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<EncodedPhoto> encode(MediaPhoto photo,
          {required int byteBudget,
          int? maxWidth,
          int? maxHeight,
          bool grayscale = false}) async =>
      EncodedPhoto(
          bytes: Uint8List(4), width: 1, height: 1, byteBudget: 4);

  @override
  Future<MediaPhoto> decode(Uint8List bytes) async {
    decodes++;
    if (fail) throw StateError('not an AVIF this build can read');
    return MediaPhoto(
      width: 2,
      height: 2,
      rgba: Uint8List.fromList(List<int>.filled(2 * 2 * 4, 0x80)),
    );
  }
}

ReceivedPhoto _photo(int id, {int channel = 1}) => ReceivedPhoto(
      payloadId: id,
      channelIndex: channel,
      receivedAt: DateTime(2026, 11, 13, 10, 30),
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    );

Widget _host(Widget child) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const <Locale>[Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('a received picture is decoded and shown', (WidgetTester t) async {
    final _FakeCodec codec = _FakeCodec();
    await t.pumpWidget(_host(ReceivedPhotosSheet(
      photos: <ReceivedPhoto>[_photo(1)],
      codec: codec,
    )));
    await _settle(t);
    expect(codec.decodes, 1, reason: 'the picture was never decoded');
    expect(find.byKey(const ValueKey<String>('received-photo-1')), findsOneWidget);
  });

  testWidgets('a payload this build cannot read is one row, not the sheet',
      (WidgetTester t) async {
    final _FakeCodec codec = _FakeCodec(fail: true);
    await t.pumpWidget(_host(ReceivedPhotosSheet(
      photos: <ReceivedPhoto>[_photo(1), _photo(2)],
      codec: codec,
    )));
    await _settle(t);
    // Both rows are present and both say so; the sheet did not throw.
    expect(find.byKey(const ValueKey<String>('received-photo-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('received-photo-2')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a picture in a codec this build lacks is named, not dropped',
      (WidgetTester t) async {
    // AEIC is MeshCore Open's neural codec and this build does not carry it.
    // The fetch service counted those datagrams and no screen read the count,
    // so an arriving AEIC picture looked exactly like nobody sending one.
    await t.pumpWidget(_host(ReceivedPhotosSheet(
      photos: <ReceivedPhoto>[_photo(1)],
      codec: _FakeCodec(),
      foreign: 2,
    )));
    await _settle(t);
    expect(find.byKey(const ValueKey<String>('received-photos-foreign')),
        findsOneWidget);
    expect(find.textContaining('2 more arrived'), findsOneWidget);
  });

  testWidgets('no foreign line when nothing arrived in another codec',
      (WidgetTester t) async {
    await t.pumpWidget(_host(ReceivedPhotosSheet(
      photos: <ReceivedPhoto>[_photo(1)],
      codec: _FakeCodec(),
    )));
    await _settle(t);
    expect(find.byKey(const ValueKey<String>('received-photos-foreign')),
        findsNothing);
  });

  testWidgets('the sheet says how long the pictures are kept',
      (WidgetTester t) async {
    // A picture is as durable as the process, and the sheet has to say so
    // rather than letting a reader assume it is in the history.
    await t.pumpWidget(_host(ReceivedPhotosSheet(
      photos: <ReceivedPhoto>[_photo(1)],
      codec: _FakeCodec(),
    )));
    await _settle(t);
    expect(find.textContaining('kept until the app closes'), findsOneWidget);
  });

  testWidgets('the sheet holds a 320 dp phone at 200 % text',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(_host(ReceivedPhotosSheet(
      photos: <ReceivedPhoto>[_photo(1)],
      codec: _FakeCodec(),
    )));
    await _settle(t);
    expect(t.takeException(), isNull);
  });
}

/// Bounded pumps: the picture view spins while the engine decodes, and a
/// spinner that never stops is a settle that never returns.
Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 40));
  }
}
