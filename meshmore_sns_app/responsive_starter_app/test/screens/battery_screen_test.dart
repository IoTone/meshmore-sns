// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/battery_screen.dart';

import '../meshcore/fake_transport.dart';

/// Real-radio finding (Heltec V4.3 on USB, first minutes after pairing): the
/// Time-to-empty card printed "Gathering drain data - an estimate appears
/// after a few minutes of discharge." twice, once as the headline and once as
/// a smaller caption underneath.
void main() {
  testWidgets('with no estimate yet the card says "gathering" once',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    await t.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ChangeNotifierProvider<MeshcoreController>.value(
        value: mc,
        child: const BatteryScreen(),
      ),
    ));
    await mc.connect();
    fake.emit(batteryFrame(4370));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    final Finder gathering = find.textContaining('Gathering drain data');
    expect(gathering, findsOneWidget,
        reason: 'shown once as the headline, not repeated as a caption');
    mc.dispose();
  });
}
