// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:meshmore_sns_app/maps/map_centre.dart';
import 'package:meshmore_sns_app/maps/map_view_state.dart';
import 'package:meshmore_sns_app/meshcore/own_location.dart';

/// The map's short-term memory, and the ordering it exists to fix.
///
/// The defect was not a missing store: the camera was already saved to disk and
/// restored on mount. It was the resolve ladder, which put the phone fix above
/// the saved view, so switching to another tab and back re-centred on the reader
/// and threw away where they had panned. These cases pin the new order.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DateTime now = DateTime(2026, 11, 13, 12);
  DateTime clock() => now;

  setUp(() => now = DateTime(2026, 11, 13, 12));

  MapViewState holder() =>
      MapViewState(clock: clock, observeLifecycle: false);

  OwnLocation phone(double lat, double lon) => OwnLocation(
        latitude: lat,
        longitude: lon,
        source: OwnLocationSource.phoneFix,
      );

  test('a fresh view beats a live phone fix', () {
    // The defect itself. A reader pans to a place, opens Chat, comes back, and
    // the map must still be where they left it even though the phone has a fix.
    final MapViewState v = holder();
    v.remember(centre: const LatLng(40.0, -105.0), zoom: 15);
    final MapCentre c = MapCentre.resolve(
      phone: phone(39.0, -104.0),
      fresh: v.freshView,
    );
    expect(c.source, MapCentreSource.lastView);
    expect(c.centre.latitude, 40.0);
    expect(c.zoom, 15);
  });

  test('a stale view loses to the phone fix', () {
    final MapViewState v = holder();
    v.remember(centre: const LatLng(40.0, -105.0), zoom: 15);
    now = now.add(MapViewState.freshFor + const Duration(seconds: 1));
    expect(v.freshView, isNull);
    final MapCentre c = MapCentre.resolve(
      phone: phone(39.0, -104.0),
      fresh: v.freshView,
    );
    expect(c.source, MapCentreSource.phone);
    expect(c.centre.latitude, 39.0);
  });

  test('exactly at the deadline the view is still fresh', () {
    final MapViewState v = holder();
    v.remember(centre: const LatLng(40.0, -105.0), zoom: 15);
    now = now.add(MapViewState.freshFor);
    expect(v.isFresh, isTrue);
  });

  test('the disk view is still the cold-start answer', () {
    // R90 is not reversed: with no session memory, the saved view is used.
    final MapCentre c = MapCentre.resolve(
      last: const SavedMapView(latitude: 41.0, longitude: -106.0, zoom: 12),
    );
    expect(c.source, MapCentreSource.lastView);
    expect(c.centre.latitude, 41.0);
  });

  test('paused discards, inactive does not', () {
    final MapViewState v = holder();
    v.remember(centre: const LatLng(40.0, -105.0), zoom: 15);
    // The notification shade and a permission dialog are `inactive`, and they
    // are not "the reader left".
    v.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(v.isFresh, isTrue);
    v.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(v.isFresh, isFalse);
    expect(v.sourceId, isNull);
  });

  test('hidden and detached discard too', () {
    for (final AppLifecycleState s in <AppLifecycleState>[
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    ]) {
      final MapViewState v = holder();
      v.remember(centre: const LatLng(40.0, -105.0), zoom: 15);
      v.didChangeAppLifecycleState(s);
      expect(v.isFresh, isFalse, reason: '$s');
    }
  });

  test('the basemap is remembered for the session without touching the camera',
      () {
    final MapViewState v = holder();
    v.rememberSource('usgs-imagery');
    expect(v.sourceId, 'usgs-imagery');
    expect(v.freshView, isNull, reason: 'a source is not a camera');
  });

  test('a remembered camera keeps the source it was remembered with', () {
    final MapViewState v = holder();
    v.remember(
        centre: const LatLng(40.0, -105.0), zoom: 15, sourceId: 'osm-vec');
    expect(v.sourceId, 'osm-vec');
  });
}
