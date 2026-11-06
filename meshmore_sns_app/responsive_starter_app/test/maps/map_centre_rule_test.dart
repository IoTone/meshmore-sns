// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:meshmore_sns_app/maps/map_centre.dart';
import 'package:meshmore_sns_app/screens/street_map_view.dart';

/// A panned map is never moved again.
///
/// The map resolves a starting camera from a ladder (phone fix, radio fix, the
/// view the user left, the world). A position that arrives after the user has
/// moved the camera must not drag it back: that is the one rule the map has
/// about taking control from a finger, and the reason its `initialCenter` is
/// not simply the ladder's answer.
void main() {
  const MapCentre resolved = MapCentre(
    centre: LatLng(39.7, -104.7),
    zoom: MapCentre.personalZoom,
    source: MapCentreSource.radio,
  );

  test('an untouched map starts where the ladder says', () {
    expect(StreetMapView.initialCentreFor(resolved: resolved, userCentre: null),
        resolved.centre);
  });

  test('a map the user moved stays where they put it', () {
    const LatLng whereTheyPutIt = LatLng(51.5, -0.12);
    expect(
        StreetMapView.initialCentreFor(
            resolved: resolved, userCentre: whereTheyPutIt),
        whereTheyPutIt,
        reason: 'a fix that arrives late must not yank a panned map');
  });

  test('the world view is a camera, not a failure', () {
    // No source knows anything: the ladder answers with the world, and that
    // answer is a real camera to start from.
    const MapCentre world = MapCentre(
      centre: MapCentre.worldCentre,
      zoom: MapCentre.worldZoom,
      source: MapCentreSource.world,
    );
    expect(StreetMapView.initialCentreFor(resolved: world, userCentre: null),
        MapCentre.worldCentre);
  });
}
