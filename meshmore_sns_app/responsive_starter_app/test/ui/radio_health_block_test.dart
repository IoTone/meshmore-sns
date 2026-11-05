// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/tools/tools_controller.dart';
import 'package:meshmore_sns_app/ui/radio_health_block.dart';

import '../meshcore/fake_transport.dart';

const List<LocalizationsDelegate<Object>> _kLocaleDelegates =
    <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Future<ToolsController> _pump(WidgetTester t,
    {void Function(ToolsController tools)? seed}) async {
  final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: false);
  final MeshcoreController mc =
      MeshcoreController(transportFactory: () async => fake);
  addTearDown(mc.dispose);
  final ToolsController tools = ToolsController(mc);
  seed?.call(tools);
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: _kLocaleDelegates,
      theme: buildMmTheme(kMmPresets[MmThemePreset.seele]!,
          shape: mmSkinFor(MmThemePreset.seele).shape),
      home: MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<ToolsController>.value(value: tools),
        ],
        child: const Scaffold(body: RadioHealthBlock()),
      ),
    ),
  );
  await t.pumpAndSettle();
  return tools;
}

void main() {
  testWidgets('before a read, the block says so rather than showing zeros',
      (WidgetTester t) async {
    await _pump(t);
    expect(find.textContaining('Not read yet'), findsOneWidget);
  });

  testWidgets('the radio numbers are shown, each with its source',
      (WidgetTester t) async {
    await _pump(t, seed: (ToolsController tools) {
      tools.stats
        ..radio = const RadioStats(
          noiseFloorDbm: -117,
          lastRssi: -88,
          lastSnrDb: 7.5,
          txAirSecs: 3,
          rxAirSecs: 5,
        )
        ..core = const CoreStats(
          batteryMilliVolts: 4100,
          uptimeSecs: 5400,
          errFlags: 0,
          queueLen: 0,
        )
        ..fetchedAt = DateTime(2026, 11, 5);
    });
    expect(find.textContaining('-117'), findsOneWidget);
    expect(find.textContaining('-88'), findsOneWidget);
    expect(find.textContaining('4.10 V'), findsOneWidget);
    expect(find.textContaining('1h 30m'), findsOneWidget);
    expect(find.textContaining('own counters'), findsOneWidget);
  });

  testWidgets('a battery the firmware does not report is said, not shown as 0',
      (WidgetTester t) async {
    await _pump(t, seed: (ToolsController tools) {
      tools.stats
        ..core = const CoreStats(
          batteryMilliVolts: 0,
          uptimeSecs: 60,
          errFlags: 0,
          queueLen: 0,
        )
        ..fetchedAt = DateTime(2026, 11, 5);
    });
    expect(find.textContaining('not reported'), findsOneWidget);
    expect(find.textContaining('0.00 V'), findsNothing);
  });
}
