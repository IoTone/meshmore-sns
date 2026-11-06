// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/dashboard_screen.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

const List<LocalizationsDelegate<Object>> _kLocaleDelegates =
    <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

void main() {
  testWidgets('offline → connected dashboard (status slab, radio, feed)',
      (WidgetTester t) async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: _kLocaleDelegates,
        home: ChangeNotifierProvider<MeshcoreController>.value(
          value: ctrl,
          child: const Scaffold(body: DashboardScreen()),
        ),
      ),
    );

    // Nothing yet: one status slab and its action, not eight placeholders.
    // The peers numeral, the radio block, the location block, the battery
    // block and the feed each appear when they have a value, so a fresh
    // install shows a state and the way out of it.
    expect(find.text('NODES IN RANGE'), findsNothing);
    expect(find.textContaining('OFFLINE'), findsOneWidget);
    expect(find.byTooltip('CONNECT'), findsOneWidget);
    expect(find.text('PEERS IN RANGE'), findsNothing);
    expect(find.text('Waiting for the radio…'), findsNothing);
    expect(find.text('No activity yet'), findsNothing);

    // Connect + handshake.
    await ctrl.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    expect(find.textContaining('LINKED'), findsOneWidget);
    expect(find.byTooltip('CONNECT'), findsNothing);
    expect(find.textContaining('self-info'), findsOneWidget);

    // An inbound channel message lands in the recent feed.
    final Uint8List chMsg = Uint8List.fromList(<int>[
      0x08, 0x00, 0x03, 0x00, 0x04, 0x03, 0x02, 0x01,
      ...utf8.encode('hello mesh'),
    ]);
    fake.emit(chMsg);
    await t.pumpAndSettle();
    // The feed is a fold that only exists once it has something to show.
    expect(find.textContaining('RECENT'), findsOneWidget);
    expect(find.textContaining('"hello mesh"'), findsOneWidget);
    ctrl.dispose();
  });

  testWidgets('a block says its name once, and one refresh belongs to it',
      (WidgetTester t) async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: _kLocaleDelegates,
        home: ChangeNotifierProvider<MeshcoreController>.value(
          value: ctrl,
          child: const Scaffold(body: DashboardScreen()),
        ),
      ),
    );
    await ctrl.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    // The section header carries the word; the block under it starts with the
    // value. It used to print LOCATION again, under a second refresh icon on
    // its own baseline — the light skin made that look like two blocks.
    // The list builds lazily, so scroll the block into view first.
    final Finder location = find.text('LOCATION');
    await t.scrollUntilVisible(location, 200,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(location, findsOneWidget);
    expect(find.byTooltip('Refresh location from device'), findsOneWidget);
    ctrl.dispose();
  });
}
