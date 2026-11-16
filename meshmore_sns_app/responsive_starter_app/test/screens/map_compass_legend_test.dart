// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/perms/location_service.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/map_screen.dart';

import '../meshcore/fake_transport.dart';

/// The Map tab draws exactly one heading, and it is the phone's.
///
/// A MeshCore node reports a position, never a facing, so the arrow on the self
/// marker comes from the phone's magnetometer. It carried a legend line for a
/// while ("The arrow is this phone's compass") and the owner removed it: a
/// compass needle needs no caption, and the line was permanent text under a map
/// that is already busy. This test holds the removal, because a legend that
/// creeps back is a permanent piece of chrome nobody asked for again.
class _NoSettings implements PermissionsService {
  @override
  Future<void> openAppSettingsPage() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('a compass reading draws the arrow with no legend under it',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));

    // The platform's own compass, which is what the app reads: the fused
    // rotation vector, the display rotation and the OS's accuracy figure,
    // exactly as `CompassStreamHandler` reports them. This quaternion is a
    // level phone facing east, so the heading it implies is 90 degrees.
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
      const EventChannel('meshmore/compass'),
      MockStreamHandler.inline(
        onListen: (Object? arguments, MockStreamHandlerEventSink sink) =>
            sink.success(<String, Object?>{
              'qx': 0.0,
              'qy': 0.0,
              'qz': -0.7071067811865476,
              'qw': 0.7071067811865476,
              'rotation': 0,
              'accuracy': 15,
            }),
      ),
    );

    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      locationService: NoopLocationService(),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(
      MaterialApp(
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
            ChangeNotifierProvider<MeshcoreController>.value(value: ctrl),
            ChangeNotifierProvider<PlaceStore>.value(value: PlaceStore()),
            Provider<PlaceReportBudget>(
                create: (_) => PlaceReportBudget(clock: DateTime.now)),
            Provider<PermissionsService>.value(value: _NoSettings()),
          ],
          child: const Scaffold(body: MapScreen()),
        ),
      ),
    );
    await ctrl.connect();
    fake.emit(selfInfoFrameAt(lat: 47.61, lon: -122.33));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('map-compass-legend')),
        findsNothing);
    expect(find.text("The arrow is this phone's compass."), findsNothing);
    // Disposed inside the body: the controller's poll is a periodic timer,
    // and the harness checks for pending timers before tear-downs run.
    ctrl.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
