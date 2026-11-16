// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/maps/geofence_render.dart';

/// A fence is the one map element that is supposed to shout, and it was drawn as
/// two 1.6 px rings in the secondary colour with no fill: invisible over a busy
/// basemap. These cases pin the two things that make it visible, the area and the
/// inside state, and the one thing that keeps it honest in every theme: the
/// colour comes from the skin's alert role, never from a literal.
void main() {
  const Color alert = Color(0xFFFF3B30);

  test('a fence is an area, not a line', () {
    final GeofenceRender r = GeofenceRender.of(alert: alert, inside: false);
    expect(r.fill.a, greaterThan(0),
        reason: 'a transparent fill is a line, and a line disappears');
    expect(r.fill.a, lessThan(.3),
        reason: 'the basemap and the pins have to stay legible through it');
    expect(r.ring.a, greaterThan(.8));
    expect(r.ringWidth, greaterThanOrEqualTo(2),
        reason: '1.6 px did not survive a busy basemap');
  });

  test('standing inside a fence looks different from standing outside', () {
    final GeofenceRender out = GeofenceRender.of(alert: alert, inside: false);
    final GeofenceRender in_ = GeofenceRender.of(alert: alert, inside: true);
    expect(in_.fill.a, greaterThan(out.fill.a));
    expect(in_.ring.a, greaterThan(out.ring.a));
    expect(in_.ringWidth, greaterThan(out.ringWidth));
    expect(in_.inside, isTrue);
  });

  test('the colour is the skin role, so every theme gets its own loud', () {
    // Two different alert roles must produce two different fences: a literal
    // would make all eleven themes identical and would be wrong on the light
    // ones.
    const Color other = Color(0xFFBE2C11);
    final GeofenceRender a = GeofenceRender.of(alert: alert, inside: false);
    final GeofenceRender b = GeofenceRender.of(alert: other, inside: false);
    expect(a.ring, isNot(b.ring));
    expect(a.ring.r, alert.r);
    expect(a.ring.g, alert.g);
    expect(a.ring.b, alert.b);
  });
}
