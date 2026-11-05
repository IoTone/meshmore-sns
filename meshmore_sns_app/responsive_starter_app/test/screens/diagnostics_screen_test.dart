import 'dart:typed_data';

// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/bot/bot_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/ble_connector.dart';
import 'package:meshmore_sns_app/screens/diagnostics_screen.dart';
import 'package:meshmore_sns_app/tools/tools_controller.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

void main() {
  Future<(MeshcoreController, FakeMeshcoreTransport)> pump(
      WidgetTester t) async {
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
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<MeshcoreController>.value(value: ctrl),
            // R109 radio health: the block reads the stats tool, which the
            // app always provides on this screen.
            ChangeNotifierProvider<ToolsController>(
                create: (_) => ToolsController(ctrl)),
            // R59 — Diagnostics carries the bot soak panel.
            ChangeNotifierProvider<BotController>(
                create: (_) => BotController()),
          ],
          child: const DiagnosticsScreen(),
        ),
      ),
    );
    return (ctrl, fake);
  }

  testWidgets('starts disconnected; connect → ready shows device',
      (WidgetTester t) async {
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake) =
        await pump(t);

    expect(find.textContaining('State: disconnected'), findsOneWidget);
    expect(find.text('Scan & connect'), findsOneWidget);

    await t.tap(find.text('Scan & connect'));
    await t.pumpAndSettle();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    expect(find.textContaining('State: ready'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    ctrl.dispose();
  });

  testWidgets('send button transmits a frame once connected',
      (WidgetTester t) async {
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake) =
        await pump(t);
    await t.tap(find.text('Scan & connect'));
    await t.pumpAndSettle();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    final int before = fake.sent.length; // APP_START already sent
    await t.tap(find.text('Get time'));
    await t.pumpAndSettle();
    expect(fake.sent.length, greaterThan(before));
    expect(find.text('Sent get-time'), findsOneWidget);
    ctrl.dispose();
  });

  testWidgets('a link whose MTU is too small says so, with the number',
      (WidgetTester t) async {
    // The connector refuses a link below 179 on Android; the refusal is
    // typed so this screen can state the number instead of echoing an
    // exception string, and the reconnect policy must not spin on it.
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => throw BleMtuTooSmall(23),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      reconnectDelay: (_) async {},
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
        home: MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<MeshcoreController>.value(value: ctrl),
            // R109 radio health: the block reads the stats tool, which the
            // app always provides on this screen.
            ChangeNotifierProvider<ToolsController>(
                create: (_) => ToolsController(ctrl)),
            ChangeNotifierProvider<BotController>(
                create: (_) => BotController()),
          ],
          child: const DiagnosticsScreen(),
        ),
      ),
    );
    await ctrl.connect();
    await t.pumpAndSettle();

    expect(ctrl.mtuRefusal?.mtu, 23);
    expect(find.textContaining('is 23 bytes'), findsOneWidget);
    expect(find.textContaining('needs 179'), findsOneWidget);
    // No backoff: the same radio negotiates the same MTU.
    expect(ctrl.reconnectAttempt, 0);
    ctrl.dispose();
  });

  testWidgets('a good link shows the MTU it negotiated',
      (WidgetTester t) async {
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake) =
        await pump(t);
    fake.mtuValue = 247;
    await t.tap(find.text('Scan & connect'));
    await t.pumpAndSettle();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    expect(find.textContaining('Link size 247 bytes'), findsOneWidget);
    expect(find.textContaining('179 needed'), findsOneWidget);
    ctrl.dispose();
  });

  testWidgets('a channel datagram reports which radio carried it',
      (WidgetTester t) async {
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake) =
        await pump(t);
    await t.tap(find.text('Scan & connect'));
    await t.pumpAndSettle();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    // 0x1B: snr, via=0xA1 (the second profile), reserved, channel, pathLen,
    // dataType, len, payload.
    fake.emit(Uint8List.fromList(<int>[
      0x1B, 0x20, 0xA1, 0x00, 0x01, 0xFF, 0x0A, 0x00, 0x02, 0xDE, 0xAD,
    ]));
    await t.pumpAndSettle();

    expect(find.textContaining('radio 2'), findsOneWidget);
    ctrl.dispose();
  });

  testWidgets('raw frame log decodes inbound frames', (WidgetTester t) async {
    // The health readout sits above the log, so the log is no longer inside
    // the default 800x600 test viewport; this is a decode assertion, not a
    // scroll-geometry one.
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake) =
        await pump(t);
    await t.tap(find.text('Scan & connect'));
    await t.pumpAndSettle();
    fake.emit(currentTimeFrame());
    await t.pumpAndSettle();

    expect(find.textContaining('CurrentTimeFrame'), findsWidgets);
    ctrl.dispose();
  });
}
