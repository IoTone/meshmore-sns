// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/gateway/gateway_service.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_connection.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/connected_apps_screen.dart';

import '../meshcore/fake_transport.dart';

const List<LocalizationsDelegate<Object>> _delegates =
    <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

String _hex(Uint8List b) =>
    b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<(MeshcoreController, GatewayService)> boot(
    WidgetTester t, {
    int port = 0,
  }) async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final GatewayService svc = GatewayService(
      mc,
      persistence: InMemoryPairingPersistence(),
      port: port,
    );
    await t.runAsync(() async {
      await mc.connect();
      fake.emit(selfInfoFrame());
      for (int i = 0; i < 50 && !mc.isReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await svc.load();
    });
    return (mc, svc);
  }

  // The controller owns timers that testWidgets insists are gone before the
  // body returns, so this runs at the end of each test, not in tearDown.
  Future<void> finish(
      WidgetTester t, MeshcoreController mc, GatewayService svc) async {
    await t.pumpWidget(const SizedBox());
    await t.runAsync(() async {
      svc.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    mc.dispose();
  }

  Future<void> show(WidgetTester t, GatewayService svc) async {
    await t.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: _delegates,
      home: ChangeNotifierProvider<GatewayService>.value(
        value: svc,
        child: const ConnectedAppsScreen(),
      ),
    ));
    await t.pump();
  }

  testWidgets('off: no token is shown', (WidgetTester t) async {
    final (MeshcoreController mc, GatewayService svc) = await boot(t);
    await show(t, svc);
    expect(find.text('Off'), findsOneWidget);
    expect(find.byKey(const Key('gateway-token-text')), findsNothing);
    expect(find.byKey(const Key('gateway-token-qr')), findsNothing);
    await finish(t, mc, svc);
  });

  testWidgets('turning it on shows the running state, token text and QR',
      (WidgetTester t) async {
    final (MeshcoreController mc, GatewayService svc) = await boot(t);
    await show(t, svc);

    await t.tap(find.byType(Switch));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();

    expect(svc.status, GatewayRunState.running);
    final String shown =
        t.widget<SelectableText>(find.byKey(const Key('gateway-token-text')))
            .data!;
    expect(shown, _hex(svc.pairingToken!),
        reason: 'the text must be the live token, not a placeholder');
    expect(shown, hasLength(32));
    // QrImageView exposes no public `data`, so presence is all that can be
    // asserted of the code; the text above is the same string it encodes.
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Listening on 127.0.0.1:${svc.port}'), findsOneWidget);
    expect(find.text('No app connected'), findsOneWidget);
    await finish(t, mc, svc);
  });

  testWidgets('Revoke asks first; confirming issues a new token, cancel keeps it',
      (WidgetTester t) async {
    final (MeshcoreController mc, GatewayService svc) = await boot(t);
    await t.runAsync(() => svc.setEnabled(true));
    await show(t, svc);
    final String before = _hex(svc.pairingToken!);

    await t.tap(find.byKey(const Key('gateway-revoke')));
    await t.pumpAndSettle();
    expect(find.text('Revoke pairing?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(_hex(svc.pairingToken!), before, reason: 'cancel must not revoke');

    await t.tap(find.byKey(const Key('gateway-revoke')));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.text('Revoke'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    final String after = _hex(svc.pairingToken!);
    expect(after, isNot(before));
    expect(
        t.widget<SelectableText>(find.byKey(const Key('gateway-token-text')))
            .data,
        after,
        reason: 'the screen must show the NEW token');
    await finish(t, mc, svc);
  });

  testWidgets('a bind failure is shown on the screen, not swallowed',
      (WidgetTester t) async {
    late ServerSocket squatter;
    await t.runAsync(() async {
      squatter = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    });
    addTearDown(() => squatter.close());
    final (MeshcoreController mc, GatewayService svc) =
        await boot(t, port: squatter.port);
    await t.runAsync(() => svc.setEnabled(true));
    await show(t, svc);

    expect(svc.status, GatewayRunState.failed);
    final Text state = t.widget<Text>(find.byKey(const Key('gateway-state')));
    expect(state.data, startsWith('Could not start:'));
    expect(state.data!.length, greaterThan('Could not start: '.length),
        reason: 'the reason must be included');
    expect(find.byKey(const Key('gateway-token-text')), findsNothing);
    await finish(t, mc, svc);
  });
}
