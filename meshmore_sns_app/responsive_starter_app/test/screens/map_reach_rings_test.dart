// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/perms/location_service.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/street_map_view.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// The map's reach rings: where they are centred, and which ones are drawn.
///
/// Two reports, one cause. The self ring was centred on `start.centre`, which
/// is the ladder's answer for where to *look* — a remembered view, or wherever
/// the reader last panned — so it followed the camera while the marker, the
/// trail and every distance were computed from the real fix. And a peer ring
/// was drawn when the peer's *position* was inside the cull box, which reaches a
/// fifth of the view past the edge: a ring up to 5 km across whose centre sat in
/// that margin still swept across the middle of the screen, so a circle appeared
/// fully formed in the middle of the view as the reader panned.
class _NoPermissions implements PermissionsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<bool>.value(false);
}

Widget _host(MeshcoreController mc) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<ThemeController>(
              create: (_) => ThemeController()),
          ChangeNotifierProvider<PlaceStore>.value(value: PlaceStore()),
          Provider<PlaceReportBudget>(
              create: (_) => PlaceReportBudget(clock: DateTime.now)),
          Provider<PermissionsService>.value(value: _NoPermissions()),
        ],
        child: const Scaffold(body: StreetMapView()),
      ),
    );

MeshcoreController _mc(FakeMeshcoreTransport f) => MeshcoreController(
      transportFactory: () async => f,
      locationService: NoopLocationService(),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );

Future<void> _drain(WidgetTester t, MeshcoreController mc) async {
  mc.dispose();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

/// Every circle the map is drawing, from the one `CircleLayer` it builds.
List<CircleMarker> _circles(WidgetTester t) {
  final Finder f = find.byType(CircleLayer);
  if (f.evaluate().isEmpty) return const <CircleMarker>[];
  return t.widget<CircleLayer>(f).circles;
}

/// The self range ring: the only circle drawn with the heavier stroke.
List<CircleMarker> _selfRings(WidgetTester t) => _circles(t)
    .where((CircleMarker c) => c.borderStrokeWidth == 1.4)
    .toList();

void main() {
  testWidgets('the self ring is centred on the fix, not on the camera',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _mc(fake);
    await t.pumpWidget(_host(mc));
    await mc.connect();
    fake.emit(selfInfoFrameAt(lat: 39.0, lon: -105.0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    final List<CircleMarker> before = _selfRings(t);
    expect(before, isNotEmpty,
        reason: 'a fix and a radio tuple are enough to draw the range ring');
    expect(before.single.point.latitude, closeTo(39.0, 1e-6));
    expect(before.single.point.longitude, closeTo(-105.0, 1e-6));

    // Pan the map away from the fix. The ring must stay where the radio is.
    await t.drag(find.byType(FlutterMap), const Offset(-260, -260));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    final List<CircleMarker> after = _selfRings(t);
    expect(after, isNotEmpty, reason: 'the ring is still on screen');
    expect(after.single.point.latitude, closeTo(39.0, 1e-6),
        reason: 'the ring followed the camera instead of the fix');
    expect(after.single.point.longitude, closeTo(-105.0, 1e-6));
    await _drain(t, mc);
  });

  testWidgets('a peer ring is drawn when its extent reaches the view, not '
      'when its centre does', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _mc(fake);
    await t.pumpWidget(_host(mc));
    await mc.connect();
    fake.emit(selfInfoFrameAt(lat: 39.0, lon: -105.0));
    // One peer a few hundred metres away, one about 1.5 km away: both rings
    // are readable at this zoom and both must be drawn.
    fake.emit(advertFrameAt(lat: 39.002, lon: -105.002, name: 'NEAR'));
    fake.emit(advertFrameAt(
        lat: 39.011, lon: -105.011, name: 'FAR', firstPubByte: 40));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    final List<CircleMarker> peer = _circles(t)
        .where((CircleMarker c) => c.borderStrokeWidth == 1.0)
        .toList();
    expect(peer.length, 2,
        reason: 'both peers are within the view and both have a distance; '
            'drew ${peer.length} of 2');
    // The ring is centred on the peer, and its radius is the distance to us.
    for (final CircleMarker c in peer) {
      expect(c.useRadiusInMeter, isTrue);
      expect(c.radius, greaterThan(0));
    }
    await _drain(t, mc);
  });
}
