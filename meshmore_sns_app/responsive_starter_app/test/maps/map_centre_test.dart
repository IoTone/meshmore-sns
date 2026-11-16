// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:meshcore/meshcore.dart';

import 'package:meshmore_sns_app/maps/map_centre.dart';
import 'package:meshmore_sns_app/maps/tile_math.dart';
import 'package:meshmore_sns_app/meshcore/own_location.dart';

SelfInfo _radio(double lat, double lon) => SelfInfo(
      advType: 1,
      txPowerDbm: 14,
      maxTxPowerDbm: 22,
      publicKey: _zeros(),
      latitude: lat,
      longitude: lon,
      multiAcks: 0,
      advertLocPolicy: 0,
      telemetryModeRaw: 0,
      manualAddContacts: false,
      frequencyMhz: 915.0,
      bandwidthKhz: 125.0,
      spreadingFactor: 8,
      codingRate: 5,
      name: 'radio',
    );

/// The package model wants a 32-byte key; the ladder never reads it.
Uint8List _zeros() => Uint8List(32);

OwnLocation _phone(double lat, double lon) => OwnLocation(
      latitude: lat,
      longitude: lon,
      source: OwnLocationSource.phoneFix,
    );

void main() {
  group('the centring ladder', () {
    test('the phone comes first', () {
      final MapCentre c = MapCentre.resolve(
        phone: _phone(38.9, -104.8),
        radio: _radio(51.5, -0.1),
        last: const SavedMapView(latitude: 1, longitude: 2, zoom: 9),
      );
      expect(c.source, MapCentreSource.phone);
      expect(c.centre, const LatLng(38.9, -104.8));
      expect(c.zoom, MapCentre.personalZoom);
    });

    test('the radio is used when the phone has no position', () {
      final MapCentre c = MapCentre.resolve(
        radio: _radio(51.5, -0.1),
        last: const SavedMapView(latitude: 1, longitude: 2, zoom: 9),
      );
      expect(c.source, MapCentreSource.radio);
      expect(c.centre, const LatLng(51.5, -0.1));
    });

    test('the view the user left is used when neither reports a position', () {
      final MapCentre c = MapCentre.resolve(
        last: const SavedMapView(latitude: 35.0, longitude: 139.0, zoom: 11),
      );
      expect(c.source, MapCentreSource.lastView);
      expect(c.centre, const LatLng(35.0, 139.0));
      expect(c.zoom, 11);
    });

    test('the world view is the last rung, and says so', () {
      final MapCentre c = MapCentre.resolve();
      expect(c.source, MapCentreSource.world);
      expect(c.centre, MapCentre.worldCentre);
      expect(c.zoom, MapCentre.worldZoom);
    });

    test('a radio that has not been asked yet is not a position', () {
      // (0, 0) is what a firmware reports before it knows, and Null Island is
      // a real place - drawing somebody there would be the lie this ladder
      // exists to avoid.
      final MapCentre c = MapCentre.resolve(radio: _radio(0, 0));
      expect(c.source, MapCentreSource.world);
    });

    test('a position outside the map projection is refused', () {
      final MapCentre c = MapCentre.resolve(phone: _phone(91, 0));
      expect(c.source, MapCentreSource.world);
      final MapCentre d = MapCentre.resolve(phone: _phone(0, 181));
      expect(d.source, MapCentreSource.world);
    });

    test('a region wider than the globe still resolves to a usable zoom', () {
      const GeoBox world = GeoBox(south: -85, west: -180, north: 85, east: 180);
      expect(MapCentre.zoomToFit(world), MapCentre.worldZoom);
      const GeoBox tiny = GeoBox(south: 38.0, west: -105.0, north: 38.001, east: -104.999);
      expect(MapCentre.zoomToFit(tiny), MapCentre.personalZoom);
    });
  });

  group('the saved view', () {
    test('round-trips through JSON', () {
      const SavedMapView v = SavedMapView(latitude: 35.6, longitude: 139.7, zoom: 12.5);
      final SavedMapView? back = SavedMapView.fromJson(v.toJson());
      expect(back, isNotNull);
      expect(back!.latitude, 35.6);
      expect(back.longitude, 139.7);
      expect(back.zoom, 12.5);
    });

    test('a corrupt or out-of-range value is dropped', () {
      expect(SavedMapView.fromJson(null), isNull);
      expect(SavedMapView.fromJson(<String, Object>{'lat': 'x', 'lon': 1, 'z': 2}), isNull);
      expect(SavedMapView.fromJson(<String, Object>{'lat': 0, 'lon': 0, 'z': 99}), isNull);
      expect(SavedMapView.fromJson(<String, Object>{'lat': 91, 'lon': 0, 'z': 5}), isNull);
    });
  });
}
