// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/app/demo_mode.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/notifications/channel_notification_prefs.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/screens/app_settings_screen.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';

import '../meshcore/fake_transport.dart';

/// Silence is per channel, and Settings points at the one place that owns it.
///
/// Settings carried a single switch for the *public* channel, so channels 1..n
/// could not be silenced anywhere — and the channel sheet's muted notice pointed
/// back at a switch that would not have silenced that channel even if found. The
/// switch lives on each channel's own sheet now; Settings has a row that goes
/// there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ValueKey<String> rowKey =
      ValueKey<String>('settings-channel-silence');

  Future<NotificationPrefs> pump(
    WidgetTester t, {
    NotificationPrefs? prefs,
  }) async {
    await t.binding.setSurfaceSize(const Size(900, 4000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final NotificationPrefs np = prefs ?? NotificationPrefs();
    addTearDown(np.dispose);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    addTearDown(mc.dispose);
    final TtsController tts = TtsController();
    addTearDown(tts.dispose);
    final LocaleController lc = LocaleController();
    addTearDown(lc.dispose);
    await t.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<NotificationPrefs>.value(value: np),
          ChangeNotifierProvider<TtsController>.value(value: tts),
          ChangeNotifierProvider<LocaleController>.value(value: lc),
          ChangeNotifierProvider<BlockStore>(create: (_) => BlockStore()),
          ChangeNotifierProvider<DemoMode>(create: (_) => DemoMode()),
        ],
        child: Provider<PermissionsService>.value(
          value: NoopPermissionsService(),
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: LocaleController.supported,
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const AppSettingsScreen(),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return np;
  }

  Future<void> revealRow(WidgetTester t) async {
    await t.scrollUntilVisible(
      find.byKey(rowKey),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
  }

  testWidgets('Settings sends silence to the screen that owns it',
      (WidgetTester t) async {
    await pump(t);
    await revealRow(t);
    expect(find.byKey(rowKey), findsOneWidget,
        reason: 'one row, naming the effect');
    expect(find.text('Silence a channel'), findsOneWidget);
    // The per-channel switch is gone from here: two homes for one setting is how
    // the notice on the channel sheet came to point at the wrong screen.
    expect(
        find.byKey(
            const ValueKey<String>('settings-public-channel-notifications')),
        findsNothing);
  });
}
