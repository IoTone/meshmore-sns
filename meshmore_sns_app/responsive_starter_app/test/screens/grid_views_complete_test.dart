// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/gen/app_localizations_en.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'dart:typed_data';

import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/elevation_profile_view.dart';
import 'package:meshmore_sns_app/screens/meshbook_view.dart';
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

    // Nobody has reported an altitude, so the chart would draw only the
    // reference objects: the view says which it is instead of looking broken.
    expect(find.text(_en.elevationEmpty), findsOneWidget);
    // And with nobody to ask, the action is absent rather than a dead button.
    expect(find.text(_en.elevationAskNodes), findsNothing);
    expect(t.takeException(), isNull,
        reason: '320 dp at the default scale must not overflow');
    await _drain(t, mc);
  });
  // The floor, per view. The tab's own sweep can only reach the view it opens
  // on, so each of these is built here at the narrowest supported width with
  // the largest text the product promises, with no radio and nothing known.
  for (final String name in <String>[
    'weather',
    'survey',
    'meshbook',
    'altitude',
  ]) {
    testWidgets('$name holds 320 dp at 200 % text', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = _controller(fake);
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: _host(
          mc,
          switch (name) {
            'weather' => const WeatherView(),
            'meshbook' => const MeshbookView(),
            _ => const ElevationProfileView(),
          },
        ),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(t.takeException(), isNull,
          reason: '$name overflowed at the accessibility floor');
      await _drain(t, mc);
    });
  }
  testWidgets('the weather view holds the floor with a reading on it',
      (WidgetTester t) async {
    // The empty state is the easy layout; the summary card and the window rows
    // are where a 320 dp screen at 200 % actually breaks.
    await t.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _controller(fake);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
      child: _host(mc, const WeatherView()),
    ));
    await t.pump();
    // An environment triplet lands as self telemetry (LPP channel 1, type
    // 0x67 = temperature, 20.0 C).
    fake.emit(Uint8List.fromList(<int>[
      0x8B, 0x00, 0, 0, 0, 0, 0, 0, 0x01, 0x67, 0x00, 0xC8,
    ]));
    await t.pump(const Duration(milliseconds: 50));
    expect(t.takeException(), isNull,
        reason: 'a real reading overflowed at the accessibility floor');
    await _drain(t, mc);
  });
}
