// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/tools/trace_screen.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tools/tools_controller.dart';

import '../meshcore/fake_transport.dart';

/// A synced contact with a known one-hop route, so Trace lists it enabled.
Uint8List _routedContact() {
  final Contact c = Contact(
    publicKey:
        Uint8List.fromList(List<int>.generate(32, (int i) => (0x55 + i) & 0xFF)),
    type: 1,
    flags: 0,
    outPathLen: 1,
    outPath: Uint8List(64)..[0] = 0x11,
    name: 'peer',
    lastAdvertTimestamp: 1700000000,
    latitudeMicros: 0,
    longitudeMicros: 0,
    lastMod: 1,
  );
  final Uint8List f = MeshcoreFrameCodec.addUpdateContact(c);
  f[0] = 0x03;
  return f;
}

void main() {
  // The Trace target picker is a bottom sheet the user can leave open while
  // the screen under it goes away (system Back on the route below, a deep
  // link). Choosing a contact afterwards used to call setState on the
  // disposed screen.
  testWidgets('choosing a contact after the screen is gone does not throw',
      (WidgetTester t) async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pump();
    fake.emit(_routedContact());
    await t.pump();
    final ToolsController tools = ToolsController(mc);
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<ToolsController>.value(value: tools),
        ChangeNotifierProvider<ThemeController>(
            create: (_) => ThemeController()),
      ],
      child: MaterialApp(
        navigatorKey: nav,
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: Text('home')),
      ),
    ));
    final MaterialPageRoute<void> traceRoute = MaterialPageRoute<void>(
        builder: (_) => const TraceScreen());
    nav.currentState!.push(traceRoute);
    await t.pumpAndSettle();
    await t.tap(find.text('Choose…'));
    await t.pumpAndSettle();
    expect(find.text('peer'), findsOneWidget);

    // The screen underneath the open sheet goes away.
    nav.currentState!.removeRoute(traceRoute);
    await t.pump();
    expect(find.byType(TraceScreen), findsNothing);

    await t.tap(find.text('peer'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    tools.dispose();
    mc.dispose();
  });
}
