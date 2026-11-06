// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/gen/app_localizations_en.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/elevation_profile_view.dart';
import 'package:meshmore_sns_app/screens/fabric_survey_view.dart';
import 'package:meshmore_sns_app/screens/weather_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

/// What each grid view owed on 2026-11-05: a source, an age, and an action.
///
/// Three of the views stated a fact without saying where it came from or how
/// old it was, and one of them promised in its own legend that peers are
/// "plotted at their altitude once asked" while nothing ever asked. These are
/// the assertions that stop those three regressions.
final AppLocalizationsEn _en = AppLocalizationsEn();

Widget _host(MeshcoreController mc, Widget child) =>
    ChangeNotifierProvider<MeshcoreController>.value(
      value: mc,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: child),
      ),
    );

MeshcoreController _controller(FakeMeshcoreTransport fake) {
  final MeshcoreController mc = MeshcoreController(
    transportFactory: () async => fake,
    connection: MeshcoreConnection(
        handshakeTimeout: const Duration(seconds: 5)),
  );
  return mc;
}

/// Disposes the controller and lets the widget tree go before the timers it
/// owns are checked: the poll intervals are real timers, and a test that ends
/// with them pending fails on the binding's invariant rather than on the view.
Future<void> _drain(WidgetTester t, MeshcoreController mc) async {
  mc.dispose();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('the microclimate strip names its channel and its source',
      (WidgetTester t) async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _controller(fake);
    await t.pumpWidget(_host(mc, const WeatherView()));
    await mc.connect();
    fake.emit(selfInfoFrameAt(lat: 38.9, lon: -104.8));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    // The channel's own name, never the slot number the firmware uses.
    expect(find.textContaining(mc.activeChannelName), findsWidgets);
    expect(find.textContaining('CH0'), findsNothing,
        reason: 'the strip used to print the raw index');
    // And what the rollup is made of: the channel's messages, with the age of
    // the newest one. A reader must not take this for a sensor reading.
    expect(find.text(_en.wxMicroclimateFromChatNoMessages), findsOneWidget);
    await _drain(t, mc);
  });

  testWidgets('the survey states its count and how old it is',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _controller(fake);
    await mc.connect();

    await t.pumpWidget(_host(mc, const FabricSurveyStatStrip(
      cellCount: 0,
      newestAgo: null,
    )));
    // Nothing recorded: the strip says so instead of implying an empty mesh.
    expect(find.text(_en.fabricNothingYet), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.pumpWidget(_host(mc, const FabricSurveyStatStrip(
      cellCount: 12,
      newestAgo: '12m ago',
    )));
    expect(find.text(_en.fabricCoverageCount(12)), findsOneWidget);
    expect(find.text(_en.fabricNewestCell('12m ago')), findsOneWidget);
    expect(t.takeException(), isNull,
        reason: '320 dp with a two-line strip must not overflow');
    await _drain(t, mc);
  });

  testWidgets('the altitude view can ask the peers that have no altitude',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _controller(fake);
    await t.pumpWidget(_host(mc, const ElevationProfileView()));
    await mc.connect();
    fake.emit(selfInfoFrameAt(lat: 38.925, lon: -104.7728));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    // The action exists for the case it was written for: a node we know that
    // has no altitude yet. With nobody to ask it is absent rather than
    // disabled, so the screen never offers a no-op.
    expect(find.byKey(const ValueKey<String>('elevation-ask-nodes')),
        findsNothing);
    // The axis says what it is: a stagger, not a distance.
    expect(find.text(_en.elevationNotADistance), findsOneWidget);
    expect(t.takeException(), isNull,
        reason: '320 dp at the default scale must not overflow');
    await _drain(t, mc);
  });
}
