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
/// A MeshCore node reports a position, never a facing, so the arrow on the
/// self marker comes from the phone's magnetometer. Nothing in the UI said so
/// — a reader could only guess whether the arrow was the radio's or the
/// phone's. The legend says it now, and says it only while there is an arrow
/// to explain: a legend for a mark that is not drawn is its own small lie.
class _NoSettings implements PermissionsService {
  @override
  Future<void> openAppSettingsPage() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('a compass reading puts the legend under the map',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));

    // The sensors the view subscribes to. It reads the same `CompassHeading`
    // the radars do, so a phone's sensors are what a fake looks like from
    // inside the app: accelerometer reporting the reaction to gravity (so the
    // phone is flat) and a magnetometer pointing north.
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/sensors/method'),
        (MethodCall call) async => null);
    final int micros = DateTime.now().microsecondsSinceEpoch;
    void sensor(String channel, List<double> values) {
      messenger.setMockStreamHandler(
        EventChannel(channel),
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink sink) =>
              sink.success(<double>[...values, micros.toDouble()]),
        ),
      );
    }

    sensor('dev.fluttercommunity.plus/sensors/accelerometer',
        <double>[0, 0, 9.81]);
    sensor('dev.fluttercommunity.plus/sensors/magnetometer',
        <double>[0, 40, -46]);
    sensor('dev.fluttercommunity.plus/sensors/gyroscope', <double>[0, 0, 0]);

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
        findsOneWidget);
    expect(find.text("The arrow is this phone's compass."), findsOneWidget);
    // Disposed inside the body: the controller's poll is a periodic timer,
    // and the harness checks for pending timers before tear-downs run.
    ctrl.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
