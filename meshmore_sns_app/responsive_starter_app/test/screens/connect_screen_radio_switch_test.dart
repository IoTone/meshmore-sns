// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/connect_screen.dart';

import '../meshcore/fake_transport.dart';

/// D8.9 on the screen: the radios this phone has paired, and which one is in
/// use.
///
/// The picker lives here rather than in the app bar because the chip already
/// routes to this screen, and the row that is already in use carries a label
/// instead of an action: a control that switches to the radio you are on does
/// nothing and still costs a tap.
void main() {
  Future<(MeshcoreController, FakeMeshcoreTransport)> pump(
    WidgetTester t, {
    required List<Map<String, Object?>> history,
    String pairedId = 'AA:BB:CC',
    String pairedName = 'WIO',
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mm.paired.id': pairedId,
      'mm.paired.name': pairedName,
      'mm.pairedHistory.v1': jsonEncode(history),
    });
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await ctrl.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);
    final GoRouter router = GoRouter(
      initialLocation: '/connect',
      routes: <RouteBase>[
        GoRoute(path: '/connect', builder: (_, __) => const ConnectScreen()),
        GoRoute(path: '/pair', builder: (_, __) => const Scaffold(body: Text('pair'))),
        GoRoute(
            path: '/settings/diagnostics',
            builder: (_, __) => const Scaffold(body: Text('console'))),
      ],
    );
    await t.pumpWidget(
      ChangeNotifierProvider<MeshcoreController>.value(
        value: ctrl,
        child: MaterialApp.router(
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
        ),
      ),
    );
    await t.pumpAndSettle();
    return (ctrl, fake);
  }

  const List<Map<String, Object?>> twoRadios = <Map<String, Object?>>[
    <String, Object?>{'id': 'AA:BB:CC', 'name': 'WIO', 't': 200},
    <String, Object?>{'id': 'DD:EE:FF', 'name': 'HELTEC', 't': 100},
  ];

  testWidgets('both paired radios are listed and the one in use says so',
      (WidgetTester t) async {
    final (MeshcoreController ctrl, _) = await pump(t, history: twoRadios);

    expect(find.text('Paired radios'), findsOneWidget);
    expect(find.text('WIO'), findsWidgets);
    expect(find.text('HELTEC'), findsOneWidget);
    // The radio in use is labelled, not offered.
    expect(find.byKey(const ValueKey<String>('radio-switch-AA:BB:CC')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('radio-switch-DD:EE:FF')),
        findsOneWidget);
    expect(find.text('In use'), findsOneWidget);
    ctrl.dispose();
  });

  testWidgets('a phone with one paired radio shows no picker',
      (WidgetTester t) async {
    // One radio is not a choice: a list with a single row and nothing to switch
    // to is a section header over a restatement of the state above it.
    final (MeshcoreController ctrl, _) = await pump(
      t,
      history: <Map<String, Object?>>[
        <String, Object?>{'id': 'AA:BB:CC', 'name': 'WIO', 't': 200},
      ],
    );
    expect(find.text('Paired radios'), findsNothing);
    ctrl.dispose();
  });

  testWidgets('switching says what happened', (WidgetTester t) async {
    final (MeshcoreController ctrl, _) = await pump(t, history: twoRadios);

    await t.tap(find.byKey(const ValueKey<String>('radio-switch-DD:EE:FF')));
    await t.pump();
    expect(find.text('Switching to HELTEC.'), findsOneWidget);
    expect(ctrl.pairedRemoteId, 'DD:EE:FF');
    ctrl.dispose();
  });
}
