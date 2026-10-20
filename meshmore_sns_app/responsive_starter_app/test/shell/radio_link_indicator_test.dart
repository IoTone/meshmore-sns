// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_connection.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/shell/home_shell.dart';

import '../meshcore/fake_transport.dart';

void main() {
  testWidgets('reflects link state: OFFLINE → LINKED', (WidgetTester t) async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
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
        home: ChangeNotifierProvider<MeshcoreController>.value(
          value: ctrl,
          child: const Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: SafeArea(child: RadioLinkIndicator()),
            ),
          ),
        ),
      ),
    );

    expect(find.text('OFFLINE'), findsOneWidget);

    await ctrl.connect();
    await t.pump();
    expect(find.text('SYNC'), findsOneWidget); // handshaking

    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();
    expect(find.text('LINKED'), findsOneWidget);
    ctrl.dispose();
  });

  // R68 — the chip used to hard-code English ('OFFLINE', 'SCAN', ...) and
  // a semantics label 'Radio OFFLINE', so a Japanese user got English on
  // every screen's app bar.
  testWidgets('the link chip is localised (JA)', (WidgetTester t) async {
    final MeshcoreController ctrl = MeshcoreController();
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ChangeNotifierProvider<MeshcoreController>.value(
          value: ctrl,
          child: const Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: SafeArea(child: RadioLinkIndicator()),
            ),
          ),
        ),
      ),
    );
    expect(find.text('オフライン'), findsOneWidget);
    expect(find.text('OFFLINE'), findsNothing);
    expect(
        find.byWidgetPredicate(
            (Widget w) => w is Semantics && w.properties.label == 'ラジオ: オフライン'),
        findsOneWidget);
    ctrl.dispose();
  });
}
