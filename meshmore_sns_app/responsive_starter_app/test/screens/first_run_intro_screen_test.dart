// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/app/demo_mode.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/media/media_prefs.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/perms/first_run_controller.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/screens/first_run_intro_screen.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/util/mm_format.dart';

/// Counts the drops the demo path asks for. The intro cannot prove a link went
/// down without a radio, so it proves the call that drops one.
class _CountingController extends MeshcoreController {
  int disconnects = 0;

  @override
  Future<void> disconnect() async {
    disconnects++;
    await super.disconnect();
  }
}

Widget _host(
  FirstRunController fr,
  PermissionsService perms, {
  MeshcoreController? mc,
  ThemeController? theme,
  FormatPrefs? fmt,
}) =>
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
        ChangeNotifierProvider<ThemeController>.value(
            value: theme ?? ThemeController()),
        ChangeNotifierProvider<FormatPrefs>.value(value: fmt ?? FormatPrefs()),
      ],
      child: MaterialApp(
        theme: (theme ?? ThemeController()).theme,
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

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // A first run is where a new user meets the app, and the one screen with no
  // app bar to escape through, so an overflow there is a wall. Every preset,
  // because the picker re-skins the flow as the choice is made.
  for (final MmThemePreset preset in MmThemePreset.values) {
    testWidgets('${preset.name}: the first page holds 320 dp at 200 % text',
        (WidgetTester t) async {
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
      await _settle(t);
      expect(t.takeException(), isNull,
          reason: 'the first page overflowed at the accessibility floor');
    });
  }

  testWidgets('the theme page and the settings page hold the same floor',
      (WidgetTester t) async {
    t.view.physicalSize = const Size(320, 780);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
      child: _host(FirstRunController(), NoopPermissionsService()),
    ));
    await _settle(t);
    await t.tap(find.byKey(const ValueKey<String>('first-run-skip')));
    await _settle(t);
    expect(t.takeException(), isNull, reason: 'the theme page overflowed');
    await t.tap(find.byKey(const ValueKey<String>('first-run-next')));
    await _settle(t);
    expect(t.takeException(), isNull, reason: 'the settings page overflowed');
  });

  testWidgets('the flow advances and goes back', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FirstRunController fr = FirstRunController();
    await fr.load();
    await t.pumpWidget(_host(fr, NoopPermissionsService()));
    await _settle(t);

    // Page 1 is the permission explainer.
    expect(find.text('What this app will ask for'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('first-run-skip')));
    await _settle(t);
    // Page 2 is the theme picker.
    expect(find.text('Choose a theme'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('first-run-next')));
    await _settle(t);
    // Page 3 is the settings, and it is where the flow ends.
    expect(find.text('A few choices'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('first-run-demo')), findsOneWidget);
    // Back returns to the picker.
    await t.tap(find.byKey(const ValueKey<String>('first-run-back')));
    await _settle(t);
    expect(find.text('Choose a theme'), findsOneWidget);
  });

  testWidgets('a theme tap is applied live', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final ThemeController tc = ThemeController();
    final FirstRunController fr = FirstRunController();
    await fr.load();
    await t.pumpWidget(_host(fr, NoopPermissionsService(), theme: tc));
    await _settle(t);
    await t.tap(find.byKey(const ValueKey<String>('first-run-skip')));
    await _settle(t);

    expect(tc.preset, isNot(MmThemePreset.air));
    await t.tap(find.byKey(
        ValueKey<String>('first-run-theme-${MmThemePreset.air.name}')));
    await _settle(t);
    expect(tc.preset, MmThemePreset.air,
        reason: 'the picker re-skins as the choice is made');
  });

  testWidgets('the units choice is persisted', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FormatPrefs fmt = FormatPrefs();
    final FirstRunController fr = FirstRunController();
    await fr.load();
    await t.pumpWidget(_host(fr, NoopPermissionsService(), fmt: fmt));
    await _settle(t);
    await t.tap(find.byKey(const ValueKey<String>('first-run-skip')));
    await _settle(t);
    await t.tap(find.byKey(const ValueKey<String>('first-run-next')));
    await _settle(t);

    expect(fmt.units, DistanceUnits.metric);
    await t.tap(find.byKey(const ValueKey<String>('first-run-units')));
    await _settle(t);
    expect(fmt.units, DistanceUnits.imperial);
    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(p.getBool('mm.format.units'), isFalse,
        reason: 'metric=true, so imperial is stored as false');
  });

  testWidgets('Skip never asks for Bluetooth', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FirstRunController fr = FirstRunController();
    await fr.load();
    final NoopPermissionsService perms = NoopPermissionsService(ble: false);
    await t.pumpWidget(_host(fr, perms));
    await _settle(t);
    await t.tap(find.byKey(const ValueKey<String>('first-run-skip')));
    await _settle(t);
    expect(fr.done, isFalse, reason: 'skipping permissions is not finishing');
  });

  testWidgets('Grant asks for Bluetooth and carries on to the theme page',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FirstRunController fr = FirstRunController();
    await fr.load();
    final NoopPermissionsService perms = NoopPermissionsService();
    await t.pumpWidget(_host(fr, perms));
    await _settle(t);

    await t.tap(find.byKey(const ValueKey<String>('first-run-grant')));
    await _settle(t);
    expect(find.text('Choose a theme'), findsOneWidget);
    expect(fr.done, isFalse, reason: 'two decisions are still to come');
  });

  testWidgets('Grant denied keeps the flow here and offers OS settings',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FirstRunController fr = FirstRunController();
    await fr.load();
    final NoopPermissionsService perms = NoopPermissionsService(ble: false);
    await t.pumpWidget(_host(fr, perms));
    await _settle(t);

    await t.tap(find.byKey(const ValueKey<String>('first-run-grant')));
    await _settle(t);
    expect(fr.done, isFalse);
    expect(find.text('What this app will ask for'), findsOneWidget);
    expect(find.text('Open OS settings'), findsOneWidget);
  });

  testWidgets('the demo path finishes and drops a link that was already up',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FirstRunController fr = FirstRunController();
    await fr.load();
    final _CountingController mc = _CountingController();
    await t.pumpWidget(_host(fr, NoopPermissionsService(ble: false), mc: mc));
    await _settle(t);
    await t.tap(find.byKey(const ValueKey<String>('first-run-skip')));
    await _settle(t);
    await t.tap(find.byKey(const ValueKey<String>('first-run-next')));
    await _settle(t);

    await t.tap(find.byKey(const ValueKey<String>('first-run-demo')));
    await _settle(t);

    expect(fr.done, isTrue);
    expect(mc.disconnects, 1,
        reason: 'a radio that answered the auto-connect before the choice must '
            'not keep running under a DEMO chip');
  });

  testWidgets('replay opens on the first page with the current choices',
      (WidgetTester t) async {
    // Replay is a review of the choices, not a reset of them: the theme and the
    // units are already the reader's when the flow mounts again.
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final ThemeController tc = ThemeController();
    await tc.setPreset(MmThemePreset.forest);
    final FormatPrefs fmt = FormatPrefs();
    await fmt.setUnits(DistanceUnits.imperial);
    final FirstRunController fr = FirstRunController();
    await fr.reset();

    await t.pumpWidget(_host(fr, NoopPermissionsService(), theme: tc, fmt: fmt));
    await _settle(t);
    expect(find.text('What this app will ask for'), findsOneWidget,
        reason: 'page 1, not wherever the reader stopped last time');
    await t.tap(find.byKey(const ValueKey<String>('first-run-skip')));
    await _settle(t);
    final Icon checked = t.widget<Icon>(find.descendant(
      of: find.byKey(ValueKey<String>(
          'first-run-theme-${MmThemePreset.forest.name}')),
      matching: find.byType(Icon),
    ));
    expect(checked.icon, Icons.radio_button_checked,
        reason: 'the current theme is the one marked');
    await t.tap(find.byKey(const ValueKey<String>('first-run-next')));
    await _settle(t);
    final SwitchListTile units =
        t.widget<SwitchListTile>(find.byKey(const ValueKey<String>('first-run-units')));
    expect(units.value, isTrue, reason: 'imperial is what the reader chose');
  });

  test('the colour-photo preference starts off', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    expect(await MediaPrefs.colorPhotos(), isFalse,
        reason: 'grey is a third of the data');
  });
}
