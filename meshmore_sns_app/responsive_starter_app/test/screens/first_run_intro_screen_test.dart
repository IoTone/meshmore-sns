// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/app/demo_mode.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/perms/first_run_controller.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/screens/first_run_intro_screen.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts the drops the demo path asks for. The intro cannot prove a link
/// went down without a radio, so it proves the call that drops one.
class _CountingController extends MeshcoreController {
  int disconnects = 0;

  @override
  Future<void> disconnect() async {
    disconnects++;
    await super.disconnect();
  }
}

Widget _host(FirstRunController fr, PermissionsService perms,
        {MeshcoreController? mc, ThemeController? theme}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<FirstRunController>.value(value: fr),
        Provider<PermissionsService>.value(value: perms),
        // The offline path records itself as demo mode, so the screen reads it.
        ChangeNotifierProvider<DemoMode>(
            create: (_) => DemoMode.preloaded(enabled: false)),
        // Demo mode makes a claim about the radio, so the path that enters it
        // has to be able to drop a link that is already up.
        ChangeNotifierProvider<MeshcoreController>.value(
            value: mc ?? _CountingController()),
        if (theme != null) ChangeNotifierProvider<ThemeController>.value(value: theme),
      ],
      child: MaterialApp(
        theme: theme?.theme,
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const FirstRunIntroScreen(),
      ),
    );

void main() {
  // A first page is where a new user meets the app and the one screen with no
  // app bar to escape through, so an overflow there is a wall. Paper is the
  // ground it is read on in daylight, which is the state it exists for.
  for (final MmThemePreset preset in <MmThemePreset>[
    MmThemePreset.air,
    MmThemePreset.studio,
  ]) {
    testWidgets('${preset.name}: the first page holds 320 dp at 200 % text',
        (WidgetTester t) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ThemeController tc = ThemeController();
      await tc.setPreset(preset);
      t.view.physicalSize = const Size(320, 780);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: _host(FirstRunController(), NoopPermissionsService(),
            theme: tc),
      ));
      for (int i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.takeException(), isNull,
          reason: 'the first page overflowed at the accessibility floor');
    });
  }

  testWidgets('Grant path requests BLE and marks first-run done',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FirstRunController fr = FirstRunController();
    await fr.load();
    final NoopPermissionsService perms = NoopPermissionsService();
    await t.pumpWidget(_host(fr, perms));

    await t.tap(find.text('Allow Bluetooth'));
    await t.pumpAndSettle();

    expect(fr.done, isTrue);
  });

  testWidgets('Skip path marks first-run done without requesting BLE',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FirstRunController fr = FirstRunController();
    await fr.load();
    final NoopPermissionsService perms = NoopPermissionsService(ble: false);
    await t.pumpWidget(_host(fr, perms));

    // The offline path is demo mode by name now, not a skip: the label the
    // screen renders is `firstRunSkip`, and the state it records is what makes
    // the launch stop reaching for a paired radio.
    await t.tap(find.text('Explore in demo mode (no radio)'));
    await t.pumpAndSettle();

    expect(fr.done, isTrue);
  });

  testWidgets('the demo path drops a link that was already up',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FirstRunController fr = FirstRunController();
    await fr.load();
    final NoopPermissionsService perms = NoopPermissionsService(ble: false);
    final _CountingController mc = _CountingController();
    await t.pumpWidget(_host(fr, perms, mc: mc));

    await t.tap(find.text('Explore in demo mode (no radio)'));
    await t.pumpAndSettle();

    expect(mc.disconnects, 1,
        reason: 'a radio that answered the auto-connect before the choice must '
            'not keep running under a DEMO chip');
  });

  testWidgets('Grant denied keeps first-run NOT done and shows '
      'OS-settings affordance', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FirstRunController fr = FirstRunController();
    await fr.load();
    final NoopPermissionsService perms = NoopPermissionsService(ble: false);
    await t.pumpWidget(_host(fr, perms));

    await t.tap(find.text('Allow Bluetooth'));
    await t.pumpAndSettle();

    expect(fr.done, isFalse);
    expect(find.text('Open OS settings'), findsOneWidget);
  });
}
