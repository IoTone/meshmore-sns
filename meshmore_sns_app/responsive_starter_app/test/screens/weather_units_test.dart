// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/weather_view.dart';
import 'package:meshmore_sns_app/util/mm_format.dart';

import '../meshcore/fake_transport.dart';

/// The weather numbers follow the reader's temperature scale.
///
/// The summary's three statistics and the per-node tile were hard-coded
/// `toStringAsFixed(1)°` with no unit at all, while the microclimate bubble in
/// the same screen already went through `MmFormat.temperature` — so a reader who
/// had chosen Fahrenheit saw °F in one section and an unlabelled Celsius number
/// in another, and a Celsius reader saw a bare `20.0°` that could have been
/// either.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// `[0x8B][reserved][6B pub6][LPP temperature]` — 20.0 °C.
  ///
  /// CayenneLPP temperature is type 0x67, two bytes, signed, tenths of a degree,
  /// so 20.0 °C travels as 200 = 0x00C8.
  Uint8List selfTempFrame(double celsius) {
    final int tenths = (celsius * 10).round();
    return Uint8List.fromList(<int>[
      0x8B, 0x00, // opcode + reserved
      0, 0, 0, 0, 0, 0, // pub6 — the self key in this fixture is zeroed
      0x01, 0x67, // LPP channel + temperature
      (tenths >> 8) & 0xFF, tenths & 0xFF,
    ]);
  }

  Widget host(MeshcoreController mc, FormatPrefs prefs) => MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<FormatPrefs>.value(value: prefs),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: WeatherView()),
        ),
      );

  Future<MeshcoreController> pump(WidgetTester t, FormatPrefs prefs) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await mc.connect();
    await t.pumpWidget(host(mc, prefs));
    fake.emit(selfInfoFrame());
    fake.emit(selfTempFrame(20.0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    return mc;
  }

  /// Dispose inside the body: the controller's pollers are timers, and the
  /// framework checks for pending timers before teardowns run.
  Future<void> drain(WidgetTester t, MeshcoreController mc) async {
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  }

  testWidgets('a Celsius reader sees °C, in every place a temperature appears',
      (WidgetTester t) async {
    final MeshcoreController mc = await pump(t, FormatPrefs(celsius: true));
    expect(find.textContaining('20 °C'), findsWidgets,
        reason: 'the summary and the tile both state the scale');
    await drain(t, mc);
  });

  testWidgets('a Fahrenheit reader sees °F and never a bare degree sign',
      (WidgetTester t) async {
    final MeshcoreController mc = await pump(t, FormatPrefs(celsius: false));
    expect(find.textContaining('68 °F'), findsWidgets);
    expect(find.textContaining('°C'), findsNothing,
        reason: 'Fahrenheit was chosen, so nothing may read as Celsius');
    // The old rendering was `20.0°` — a number with no scale. It must be gone
    // rather than merely joined by a correct one.
    expect(find.textContaining('20.0°'), findsNothing);
    await drain(t, mc);
  });
}
