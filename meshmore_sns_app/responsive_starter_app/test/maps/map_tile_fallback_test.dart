// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/maps/basemap.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/map_source.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/maps/tile_store.dart';

/// R114 — a missing fine tile paints its coarse parent instead of nothing.
///
/// This drives the real `MapTileImage` the tile layer uses, so it fails if the
/// fallback is only wired in the controller: the provider must resolve to a
/// 256 px image built from the ancestor, and must still fail honestly when
/// there is no ancestor at all.
class _NeverFetch {
  Future<FetchResult> call(Uri url,
          {String? etag, int? ifModifiedSinceMs}) async =>
      const FetchResult(FetchStatus.failed);
}

const MapSource kTestRaster = MapSource(
  id: 'test-raster',
  name: 'Test raster',
  urlTemplate: 'https://tiles.test/{z}/{x}/{y}.png',
  attribution: 'test',
  allowsPacks: true,
);

ImageDecoderCallback _decoder() =>
    (ui.ImmutableBuffer buffer, {ui.TargetImageSizeCallback? getTargetSize}) =>
        ui.instantiateImageCodecWithSize(buffer, getTargetSize: getTargetSize);

/// The first frame a completer produces, or the error it produces instead.
Future<ImageInfo> _firstFrame(ImageStreamCompleter completer) {
  final Completer<ImageInfo> done = Completer<ImageInfo>();
  completer.addListener(ImageStreamListener(
    (ImageInfo info, bool sync) {
      if (!done.isCompleted) done.complete(info);
    },
    onError: (Object error, StackTrace? stack) {
      if (!done.isCompleted) done.completeError(error, stack);
    },
  ));
  return done.future;
}

/// A 64x64 PNG, so the ancestor is a real image and the crop path is real.
Future<Uint8List> _png(int side, int red) async {
  final ui.PictureRecorder rec = ui.PictureRecorder();
  Canvas(rec).drawRect(
    Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    Paint()..color = Color.fromARGB(255, red, 40, 40),
  );
  final ui.Image img = await rec.endRecording().toImage(side, side);
  final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = await Directory.systemTemp.createTemp('map_tile_fallback_test');
    now = DateTime(2026, 10, 15, 12);
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<MapsController> controller() async {
    final MapsController maps = MapsController(
      rootDir: () async => dir,
      fetcher: _NeverFetch().call,
      clock: () => now,
      pace: Duration.zero,
    );
    await maps.load();
    return maps;
  }

  Future<void> seedAncestor(int z, int x, int y, Uint8List bytes) async {
    final TileStore store = TileStore(dir, clock: () => now);
    await store.load();
    await store.write(TileStore.keyOf(kTestRaster.id, z, x, y), bytes,
        maxAge: const Duration(days: 1));
    await store.flush();
  }

  test('a missing tile paints its parent, cropped to the cell', () async {
    await seedAncestor(10, 500, 751, await _png(64, 200));
    final MapsController maps = await controller();
    addTearDown(maps.dispose);

    final MapTileImage tile = MapTileImage(maps, kTestRaster, 12, 2001, 3007);
    final ImageStreamCompleter completer = tile.loadImage(tile, _decoder());
    final ImageInfo info = await _firstFrame(completer);
    addTearDown(info.dispose);

    // The stand-in is emitted at the tile edge, so it lands in the cell
    // without a second scale.
    expect(info.image.width, kTilePixelSize);
    expect(info.image.height, kTilePixelSize);
  });

  test('no tile and no ancestor still fails honestly', () async {
    final MapsController maps = await controller();
    addTearDown(maps.dispose);

    final MapTileImage tile = MapTileImage(maps, kTestRaster, 12, 2001, 3007);
    final ImageStreamCompleter completer = tile.loadImage(tile, _decoder());
    await expectLater(_firstFrame(completer), throwsStateError);
  });
}
