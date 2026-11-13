import 'dart:typed_data';

// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// The developer blocks are folded away by default (D1): the page opens on
  /// the connection facts and the one action.
  Future<void> openDeveloper(WidgetTester t) async {
    await t.tap(find.text('DEVELOPER'));
    await t.pumpAndSettle();
  }

  testWidgets('starts disconnected; connect → ready shows device',
      (WidgetTester t) async {
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake) =
        await pump(t);

    expect(find.textContaining('State: disconnected'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);

    await t.tap(find.text('Connect'));
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
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    final int before = fake.sent.length; // APP_START already sent
    await openDeveloper(t);
    // The developer half is a scrolling section: reach the button rather than
    // assuming it fits, which stopped being true when the section grew.
    await t.ensureVisible(find.text("Read the radio's clock"));
    await t.pumpAndSettle();
    await t.tap(find.text("Read the radio's clock"));
    await t.pumpAndSettle();
    expect(fake.sent.length, greaterThan(before));
    expect(find.text('Sent get-time'), findsOneWidget);
    ctrl.dispose();
  });

  testWidgets('the raw-record tool sits in the developer section',
      (WidgetTester t) async {
    // D10.1 kept the raw send; this is its caller, and it belongs behind the
    // developer fold rather than beside the one action the page leads with.
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake) =
        await pump(t);
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    expect(find.text('Send a raw record'), findsNothing,
        reason: 'folded away by default');
    await openDeveloper(t);
    await t.ensureVisible(find.text('Send a raw record'));
    await t.pumpAndSettle();
    expect(find.text('Send a raw record'), findsOneWidget);
    expect(find.textContaining('No contact has a direct route yet'),
        findsOneWidget);
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
    await t.tap(find.text('Connect'));
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
    await t.tap(find.text('Connect'));
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

  testWidgets('forgetting a radio asks first and names the consequence',
      (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mm.paired.id': 'AA:BB:CC',
      'mm.paired.name': 'T1000-E',
    });
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
            ChangeNotifierProvider<ToolsController>(
                create: (_) => ToolsController(ctrl)),
            ChangeNotifierProvider<BotController>(
                create: (_) => BotController()),
          ],
          child: const DiagnosticsScreen(),
        ),
      ),
    );
    await ctrl.autoConnectIfPaired();
    await t.pumpAndSettle();
    expect(ctrl.hasPairedDevice, isTrue);

    await t.tap(find.text('Forget'));
    await t.pumpAndSettle();
    expect(find.text('Forget this radio?'), findsOneWidget);
    expect(find.textContaining('You will need to pair it again'), findsOneWidget);

    // Cancelling changes nothing.
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(ctrl.hasPairedDevice, isTrue);

    await t.tap(find.text('Forget'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Forget'));
    await t.pumpAndSettle();
    expect(ctrl.hasPairedDevice, isFalse);
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
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    fake.emit(currentTimeFrame());
    await t.pumpAndSettle();

    // Folded until asked for.
    expect(find.textContaining('CurrentTimeFrame'), findsNothing);
    await openDeveloper(t);
    expect(find.textContaining('CurrentTimeFrame'), findsWidgets);
    ctrl.dispose();
  });

  testWidgets('a link that handshook twice says so', (WidgetTester t) async {
    // The owner's report was "it said handshaking for a long time", and the
    // only trace of it afterwards is that the link did it more than once. The
    // line stays silent for one clean handshake, because that is every launch
    // and this page is already dense.
    final List<FakeMeshcoreTransport> links = <FakeMeshcoreTransport>[];
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async {
        final FakeMeshcoreTransport f = FakeMeshcoreTransport(connected: true);
        links.add(f);
        return f;
      },
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
            ChangeNotifierProvider<ToolsController>(
                create: (_) => ToolsController(ctrl)),
            ChangeNotifierProvider<BotController>(
                create: (_) => BotController()),
          ],
          child: const DiagnosticsScreen(),
        ),
      ),
    );

    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    links.last.emit(selfInfoFrame());
    await t.pumpAndSettle();

    expect(find.textContaining('link handshakes:'), findsNothing,
        reason: 'one clean handshake is the normal case');

    // A user retry: the app tears the old link down and opens a new one.
    await ctrl.connect();
    links.last.emit(selfInfoFrame());
    await t.pumpAndSettle();

    expect(find.textContaining('link handshakes: 2 started, 0 with no answer'),
        findsOneWidget);
    ctrl.dispose();
  });

  testWidgets('the console keeps its frames and names the way back',
      (WidgetTester t) async {
    // The split's other half: a reader-facing screen for the facts, and this
    // page for the evidence. The row at the top is the way back, and the
    // developer fold is still here rather than deleted.
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake) = await pump(t);
    await t.tap(find.byKey(const ValueKey<String>('diag-connect')));
    await t.pumpAndSettle();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    expect(
        find.byKey(const ValueKey<String>('diagnostics-connection-row')),
        findsOneWidget);
    expect(find.text('DEVELOPER'), findsOneWidget);
    await openDeveloper(t);
    await t.ensureVisible(find.text('Send a raw record'));
    await t.pumpAndSettle();
    expect(find.text('Send a raw record'), findsOneWidget);
    ctrl.dispose();
  });

}
