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

/// Settings carries one switch for the Public channel: whether messages there
/// alert this phone at all.
///
/// The switch is not a second setting beside the per-channel bundle the chat
/// header edits. It is slot 0's `muted` flag, so the two can never disagree,
/// and the live suite proves the service honours it
/// (`test/notifications/notification_service_test.dart`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ValueKey<String> switchKey =
      ValueKey<String>('settings-public-channel-notifications');

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

  Future<void> revealSwitch(WidgetTester t) async {
    await t.scrollUntilVisible(
      find.byKey(switchKey),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
  }

  testWidgets('the switch starts on and says what on means',
      (WidgetTester t) async {
    await pump(t);
    await revealSwitch(t);
    final SwitchListTile tile = t.widget<SwitchListTile>(find.byKey(switchKey));
    expect(tile.value, isTrue);
    expect(find.textContaining('alert this phone'), findsOneWidget);
  });

  testWidgets(
      'turning it off mutes slot 0, and the copy names the SOS '
      'exception', (WidgetTester t) async {
    final NotificationPrefs np = await pump(t);
    await revealSwitch(t);
    await t.tap(find.byKey(switchKey));
    await t.pumpAndSettle();

    expect(np.prefsFor(0).muted, isTrue,
        reason: 'the switch is the channel bundle, not a setting beside it');
    expect(find.textContaining('SOS'), findsOneWidget,
        reason: 'a user has to be able to see that an SOS is not silenced');
  });

  testWidgets('turning it back on restores the switches the user had',
      (WidgetTester t) async {
    // Silenced while speech was on for this channel: re-enabling must bring
    // the speech back rather than resetting the channel to its defaults.
    final NotificationPrefs np = NotificationPrefs(
      seed: <int, ChannelNotificationPrefs>{
        0: const ChannelNotificationPrefs(tts: true, muted: true),
      },
    );
    await pump(t, prefs: np);
    await revealSwitch(t);
    await t.tap(find.byKey(switchKey));
    await t.pumpAndSettle();
    expect(np.prefsFor(0).muted, isFalse);
    expect(np.prefsFor(0).tts, isTrue,
        reason: 'a master silence must not rewrite the bundle it silences');
  });
}
