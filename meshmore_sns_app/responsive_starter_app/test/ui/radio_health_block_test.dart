// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

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
    {void Function(ToolsController tools)? seed,
    void Function(MeshcoreController mc, FakeMeshcoreTransport fake)?
        onReady}) async {
  final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: false);
  final MeshcoreController mc =
      MeshcoreController(transportFactory: () async => fake);
  onReady?.call(mc, fake);
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
  testWidgets('the radio\'s own ACK round trip is shown once it has one',
      (WidgetTester t) async {
    // PUSH_CODE_SEND_CONFIRMED carries a trip time the app cannot measure
    // itself, because the phone's clock stops at the radio's door. It belongs
    // beside the other readings the radio took, and it must be absent — not
    // zero — until one has arrived.
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    final ToolsController tools = ToolsController(mc);
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
    await mc.connect();
    fake.emit(selfInfoFrame());
    // Two pumps, not pumpAndSettle: the controller keeps a one-minute periodic
    // timer, so settling would wait for it.
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    expect(find.textContaining('round trip'), findsNothing,
        reason: 'nothing has been acknowledged yet');

    // 0x82: the acknowledged tag, then the radio's own trip time in ms.
    fake.emit(Uint8List.fromList(<int>[
      0x82, 0x11, 0x22, 0x33, 0x44, // tag
      0xD8, 0x04, 0x00, 0x00, // 1240 ms LE
    ]));
    await t.pump();
    // 60 ms: the controller coalesces notifications into a 50 ms window, so a
    // frame that lands inside one is rendered when the window closes.
    await t.pump(const Duration(milliseconds: 60));
    expect(find.textContaining('1240 ms round trip'), findsOneWidget);
    tools.dispose();
    mc.dispose();
  });

  testWidgets('before a read, the block says so rather than showing zeros',
      (WidgetTester t) async {
    await _pump(t);
    // The line states the fact; the Read button beside it is the action. It
    // used to say "Tap Read", which is the button's own label written out one
    // line below the button.
    expect(find.textContaining('No reading yet'), findsOneWidget);
    expect(find.textContaining('Tap Read'), findsNothing);
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
    expect(find.textContaining('From the radio'), findsOneWidget);
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
    expect(find.textContaining('Not reported'), findsOneWidget);
    expect(find.textContaining('0.00 V'), findsNothing);
  });
}
