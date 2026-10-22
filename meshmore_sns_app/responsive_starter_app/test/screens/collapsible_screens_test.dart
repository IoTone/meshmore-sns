// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/device_config_screen.dart';
import 'package:meshmore_sns_app/screens/personalization_screen.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/mm_collapse_controller.dart';
import 'package:meshmore_sns_app/ui/mm_collapsible.dart';

/// R64 — the long settings screens are grouped into collapsible
/// sections. Every group starts open (nothing hidden by default), the
/// header folds only its own group, and Channels (a single row) is
/// deliberately not wrapped.
Widget _host(Widget screen, [MmCollapseController? collapse]) => MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        if (collapse != null)
          ChangeNotifierProvider<MmCollapseController>.value(value: collapse),
        ChangeNotifierProvider<ThemeController>(
            create: (_) => ThemeController()),
        ChangeNotifierProvider<MeshcoreController>(
            create: (_) => MeshcoreController()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: screen,
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets(
      'Device configuration: five groups, four open, each folds '
      'alone, Channels stays a plain row', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 3200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_host(const DeviceConfigScreen()));
    await t.pumpAndSettle();
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(DeviceConfigScreen)));

    expect(find.byType(MmCollapsibleSection), findsNWidgets(5));
    expect(find.text('Frequency (MHz)'), findsOneWidget, reason: 'open');
    expect(find.text('Manage channels'), findsOneWidget);
    // R103: the band picker starts folded; its applied value is the banner
    // above the section, which is always visible.
    expect(find.text('USA / Canada'), findsNothing, reason: 'folded');

    await t.tap(find.text(l.deviceRadioParams.toUpperCase()));
    await t.pumpAndSettle();
    expect(find.text('Frequency (MHz)'), findsNothing,
        reason: 'the radio group folded');
    expect(find.text('USA / Canada'), findsNothing,
        reason: 'the region group stayed folded');
    expect(find.text('Advert name'), findsOneWidget,
        reason: 'the identity group did not');
    expect(find.text('Manage channels'), findsOneWidget);
  });

  testWidgets(
      'Device configuration: region presets sit under three labelled '
      'families, not one wall of chips (R68)', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 3200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_host(const DeviceConfigScreen()));
    await t.pumpAndSettle();
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(DeviceConfigScreen)));
    // R103: the picker is folded until asked for.
    await t.tap(find.text(l.deviceRegionBand.toUpperCase()));
    await t.pumpAndSettle();
    final Finder americas = find.text(l.deviceRegionFamilyAmericas);
    final Finder europe = find.text(l.deviceRegionFamilyEurope);
    final Finder apac = find.text(l.deviceRegionFamilyAsiaPacific);
    expect(americas, findsOneWidget);
    expect(europe, findsOneWidget);
    expect(apac, findsOneWidget);
    expect(find.text(l.deviceRegionFamilyOther), findsNothing,
        reason: 'no preset is ungrouped, so no empty/other heading');
    double y(Finder f) => t.getTopLeft(f).dy;
    // Order: Americas, Europe, Asia-Pacific; each chip under its heading.
    expect(y(americas), lessThan(y(europe)));
    expect(y(europe), lessThan(y(apac)));
    expect(y(find.text('USA / Canada')), greaterThan(y(americas)));
    expect(y(find.text('USA / Canada')), lessThan(y(europe)));
    expect(y(find.text('EU / UK (Long Range)')), greaterThan(y(europe)));
    expect(y(find.text('EU / UK (Long Range)')), lessThan(y(apac)));
    expect(y(find.text('Vietnam')), greaterThan(y(apac)));
  });

  testWidgets(
      'Personalization: every group folds, with no plain header between '
      'two folding ones (R68)', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_host(const PersonalizationScreen()));
    await t.pumpAndSettle();
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(PersonalizationScreen)));

    expect(find.byType(MmCollapsibleSection), findsNWidgets(4),
        reason: 'preset, type, accessibility, audio: one idiom throughout');
    for (final MmThemePreset p in MmThemePreset.values) {
      expect(find.text(p.label), findsOneWidget, reason: '${p.name} open');
    }
    expect(find.text(l.personalizationReduceMotion), findsOneWidget);

    await t.tap(find.text(l.personalizationThemePreset));
    await t.pumpAndSettle();
    expect(find.text(MmThemePreset.studio.label), findsNothing);
    expect(find.text(l.personalizationReduceMotion), findsOneWidget,
        reason: 'folding presets leaves accessibility alone');

    await t.tap(find.text(l.personalizationAccessibility));
    await t.pumpAndSettle();
    expect(find.text(l.personalizationReduceMotion), findsNothing);
    expect(find.text(l.personalizationAudioMaster), findsOneWidget);

    // TYPE used to sit between two folding groups with no chevron.
    expect(find.text(l.personalizationFontSize), findsOneWidget);
    await t.tap(find.text(l.personalizationType));
    await t.pumpAndSettle();
    expect(find.text(l.personalizationFontSize), findsNothing,
        reason: 'the TYPE group folds');
    await t.tap(find.text(l.personalizationAudioAlerts));
    await t.pumpAndSettle();
    expect(find.text(l.personalizationAudioMaster), findsNothing,
        reason: 'the audio group folds');
  });

  testWidgets(
      'R65: a group folded on Device configuration stays folded '
      'the next time the screen opens', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 3200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    MmCollapseController c = MmCollapseController();
    await c.load();
    await t.pumpWidget(_host(const DeviceConfigScreen(), c));
    await t.pumpAndSettle();
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(DeviceConfigScreen)));
    await t.tap(find.text(l.deviceRadioParams.toUpperCase()));
    await t.pumpAndSettle();
    expect(find.text('Frequency (MHz)'), findsNothing);

    await t.pumpWidget(const SizedBox()); // leave the screen
    c = MmCollapseController(); // a cold start: prefs only
    await c.load();
    await t.pumpWidget(_host(const DeviceConfigScreen(), c));
    await t.pumpAndSettle();
    expect(find.text('Frequency (MHz)'), findsNothing,
        reason: 'the radio group is still folded');
    expect(find.text('Advert name'), findsOneWidget,
        reason: 'the other groups are still open');
  });
}
