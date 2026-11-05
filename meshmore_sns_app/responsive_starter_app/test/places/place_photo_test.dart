// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/places/place_detail_sheet.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import 'package:meshmore_sns_app/media/media_chunk.dart';
import 'package:meshmore_sns_app/media/media_codec.dart';
import 'package:meshmore_sns_app/media/media_photo.dart';
import 'package:meshmore_sns_app/media/media_transfer.dart';
import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_photo.dart';

DateTime _now = DateTime(2026, 11, 5, 12);

Place _place({String id = 'abcd1234', PlaceTtl ttl = PlaceTtl.h6}) => Place(
      id: id,
      reporterName: 'Ana',
      type: PlaceType.water,
      typeToken: PlaceType.water.token,
      label: 'Water at the ford',
      latE6: 51500741,
      lonE6: -124596,
      decimals: 6,
      provenance: PlaceProvenance.received,
      ttl: ttl,
      sentAt: _now,
      expiresAt: _now.add(ttl.life),
      lastSeen: _now,
    );

PlacePhoto _photoFor(Place p) => PlacePhoto(
      placeId: p.id,
      ref: const PlacePhotoRef(contentHash: 'abc123', payloadId: 5),
      photo: MediaPhoto(width: 320, height: 240, rgba: Uint8List(320 * 240 * 4)),
      fetchedAt: _now,
    );

Widget _host(Widget child) => ChangeNotifierProvider<ThemeController>(
      create: (_) => ThemeController(),
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

void main() {
  setUp(() => _now = DateTime(2026, 11, 5, 12));

  group('a photo never extends the place it belongs to', () {
    test('keeping a photo leaves the TTL exactly where it was', () {
      final Place p = _place();
      final DateTime expiry = p.expiresAt;
      final PlacePhotos photos = PlacePhotos(clock: () => _now);

      expect(photos.stateFor(p), PlacePhotoState.notFetched);
      photos.keep(p, _photoFor(p));

      expect(photos.stateFor(p), PlacePhotoState.present);
      expect(p.expiresAt, expiry, reason: 'the claim keeps its own life');
      expect(p.ttl, PlaceTtl.h6);
      // Six hours later the place is expired and so is its photo.
      _now = expiry.add(const Duration(minutes: 1));
      expect(p.isLiveAt(_now), isFalse);
      expect(photos.prune(<Place>[p]), 1);
      expect(photos.stateFor(p), PlacePhotoState.notFetched);
    });

    test('pruning keeps a live place and drops an expired one', () {
      final Place live = _place(id: 'live0001', ttl: PlaceTtl.d7);
      final Place old = _place(id: 'old00001');
      final PlacePhotos photos = PlacePhotos(clock: () => _now);
      photos.keep(live, _photoFor(live));
      photos.keep(old, _photoFor(old));

      _now = old.expiresAt.add(const Duration(minutes: 1));
      expect(photos.prune(<Place>[live, old]), 1);
      expect(photos.photoFor(live), isNotNull);
      expect(photos.photoFor(old), isNull);
    });

    test('a picture that arrives after expiry is not kept', () async {
      final Place p = _place(ttl: PlaceTtl.m15);
      final PlacePhotos photos = PlacePhotos(clock: () => _now);
      final MediaDownload download = MediaDownload();
      final PlacePhotoFetch fetch = PlacePhotoFetch(
        place: p,
        ref: const PlacePhotoRef(contentHash: 'abc123', payloadId: 9),
        download: download,
        codec: FakeMediaCodec(encodedBytes: 300),
        photos: photos,
        clock: () => _now,
        sendAsk: () async {},
      );
      final Future<PlacePhoto?> result = fetch.run();
      // The payload arrives, but the claim behind it has already expired.
      _now = p.expiresAt.add(const Duration(minutes: 1));
      for (final Uint8List chunk in MediaChunkCodec.split(
        List<int>.filled(300, 1),
        payloadId: 9,
        kind: MediaKind.image,
      )) {
        fetch.accept(chunk);
      }
      expect(await result, isNull);
      expect(photos.stateFor(p), PlacePhotoState.notFetched);
    });
  });

  group('the fetch asks, waits, decodes and keeps', () {
    test('a complete payload becomes a stored picture', () async {
      final Place p = _place();
      final PlacePhotos photos = PlacePhotos(clock: () => _now);
      final MediaDownload download = MediaDownload();
      int asks = 0;
      final PlacePhotoFetch fetch = PlacePhotoFetch(
        place: p,
        ref: const PlacePhotoRef(contentHash: 'abc123', payloadId: 12),
        download: download,
        codec: FakeMediaCodec(encodedBytes: 300),
        photos: photos,
        clock: () => _now,
        sendAsk: () async => asks++,
      );
      final Future<PlacePhoto?> result = fetch.run();
      await Future<void>.delayed(Duration.zero);
      expect(asks, 1, reason: 'the ask goes out before any bytes arrive');
      for (final Uint8List chunk in MediaChunkCodec.split(
        List<int>.filled(300, 2),
        payloadId: 12,
        kind: MediaKind.image,
      )) {
        fetch.accept(chunk);
      }
      final PlacePhoto? photo = await result;
      expect(photo, isNotNull);
      expect(photo!.placeId, p.id);
      expect(photos.stateFor(p), PlacePhotoState.present);
      expect(download.transfers, isEmpty,
          reason: 'a handed-on payload is forgotten, not kept twice');
    });

    test('nothing arriving is a timeout, not a promise', () async {
      final Place p = _place();
      final PlacePhotos photos = PlacePhotos(clock: () => _now);
      final PlacePhotoFetch fetch = PlacePhotoFetch(
        place: p,
        ref: const PlacePhotoRef(contentHash: 'abc123', payloadId: 13),
        download: MediaDownload(),
        codec: FakeMediaCodec(),
        photos: photos,
        clock: () => _now,
        sendAsk: () async {},
        timeout: const Duration(milliseconds: 1),
      );
      expect(await fetch.run(), isNull);
      expect(fetch.failure, PlacePhotoFetchFailure.timedOut);
      expect(photos.stateFor(p), PlacePhotoState.notFetched);
    });

    test('a place with no reference has nothing to ask for', () async {
      final Place p = _place();
      int asks = 0;
      final PlacePhotoFetch fetch = PlacePhotoFetch(
        place: p,
        ref: null,
        download: MediaDownload(),
        codec: FakeMediaCodec(),
        photos: PlacePhotos(clock: () => _now),
        clock: () => _now,
        sendAsk: () async => asks++,
      );
      expect(await fetch.run(), isNull);
      expect(fetch.failure, PlacePhotoFetchFailure.noReference);
      expect(asks, 0);
    });
  });

  group('the detail sheet says whether the picture is here', () {
    testWidgets('without bytes it offers the fetch and warns first',
        (WidgetTester t) async {
      final Place p = _place();
      final PlaceStore store = PlaceStore(clock: () => _now);
      addTearDown(store.dispose);
      bool asked = false;
      await t.pumpWidget(_host(PlaceDetailSheet(
        place: p,
        store: store,
        photos: PlacePhotos(clock: () => _now),
        onFetchPhoto: () async {
          asked = true;
          return null;
        },
      )));
      await t.pump();
      expect(find.text('The photo may not arrive. The text will.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('place-photo-fetch')));
      await t.pump();
      expect(asked, isTrue);
    });

    testWidgets('with bytes the picture is shown and no fetch is offered',
        (WidgetTester t) async {
      final Place p = _place();
      final PlaceStore store = PlaceStore(clock: () => _now);
      addTearDown(store.dispose);
      final PlacePhotos photos = PlacePhotos(clock: () => _now);
      photos.keep(p, _photoFor(p));
      await t.pumpWidget(_host(PlaceDetailSheet(
        place: p,
        store: store,
        photos: photos,
      )));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey<String>('place-photo')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('place-photo-fetch')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });
}
