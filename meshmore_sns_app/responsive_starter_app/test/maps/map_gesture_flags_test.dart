// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/screens/street_map_view.dart';

/// The screen says "Drag a corner to move it". On the handset a drag on a corner
/// panned the *map*: both recognisers claimed the gesture and the map won, so the
/// picture slid and the corner stayed. The map's pan is withheld while a finger is
/// on a handle, and this pins the decision.
void main() {
  test('a normal map pans', () {
    final int flags =
        StreetMapView.mapFlagsFor(interactive: true, draggingCorner: false);
    expect(flags & InteractiveFlag.drag, isNot(0),
        reason: 'panning is the map\'s main gesture');
    expect(flags & InteractiveFlag.pinchZoom, isNot(0));
    expect(flags & InteractiveFlag.doubleTapZoom, isNot(0));
  });

  test('a drag that starts on a corner belongs to the corner', () {
    final int flags =
        StreetMapView.mapFlagsFor(interactive: true, draggingCorner: true);
    expect(flags & InteractiveFlag.drag, 0,
        reason: 'the map must not pan a drag that is moving a corner');
    // Zoom is not a pan and cannot be confused with moving a corner, so it stays.
    expect(flags & InteractiveFlag.pinchZoom, isNot(0));
    expect(flags & InteractiveFlag.scrollWheelZoom, isNot(0));
  });

  test('a non-interactive map claims nothing at all', () {
    expect(StreetMapView.mapFlagsFor(interactive: false, draggingCorner: false),
        InteractiveFlag.none);
    expect(StreetMapView.mapFlagsFor(interactive: false, draggingCorner: true),
        InteractiveFlag.none);
  });
}
