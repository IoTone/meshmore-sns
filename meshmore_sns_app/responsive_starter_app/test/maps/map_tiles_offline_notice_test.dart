// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/map_source.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/screens/street_map_view.dart';

/// A map with no network has to say so.
///
/// The copy existed in the degraded model and was never drawn, so a user
/// offline with an empty cache saw a blank grey grid and no reason for it.
/// The rule is a function so it can be checked here: the map itself schedules
/// timers and animations that a widget test cannot settle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppLocalizations l;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = await Directory.systemTemp.createTemp('map_offline_rule');
    l = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<MapsController> controller({required bool online}) async {
    final MapsController maps = MapsController(
      rootDir: () async => dir,
      fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs}) async => online
          ? const FetchResult(FetchStatus.ok, bytes: null)
          : const FetchResult(FetchStatus.failed),
      pace: Duration.zero,
    );
    await maps.load();
    // A single miss is not an outage: the controller marks itself offline
    // only after its run of consecutive failures, which is the rule the map
    // inherits rather than re-decides.
    for (int i = 0; i < 4; i++) {
      await maps.loadTile(kBuiltInSources.first, 3, i, 1);
    }
    return maps;
  }

  test('no controller, no claim', () {
    expect(StreetMapView.tilesOfflineNoticeFor(l, null), isNull,
        reason: 'a map with no tile machinery must not blame the network');
  });

  test('a controller that is fetching keeps quiet', () async {
    final MapsController maps = await controller(online: true);
    addTearDown(maps.dispose);
    expect(StreetMapView.tilesOfflineNoticeFor(l, maps), isNull);
  });

  test('a controller that cannot fetch says why the map is empty', () async {
    final MapsController maps = await controller(online: false);
    addTearDown(maps.dispose);
    expect(StreetMapView.tilesOfflineNoticeFor(l, maps), l.degradedMapOffline,
        reason: 'the notice names the reason the grid is bare');
  });
}
