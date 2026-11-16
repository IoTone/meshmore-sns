// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/app_state_model.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/perms/first_run_controller.dart';
import 'package:meshmore_sns_app/screens/about_screen.dart';
import 'package:meshmore_sns_app/ui/mm_components.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// The information page had no test at all.
///
/// It carries four things a reader can check without a radio: the version, the
/// bilingual brand line, the licence page and the replay-intro action — the last
/// two being buttons, which is where a page like this rots unnoticed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester t, {bool introDone = true}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    t.view.physicalSize = const Size(420, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    addTearDown(mc.dispose);
    await t.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AppState>(create: (_) => AppState()),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
        ChangeNotifierProvider<FirstRunController>(
            create: (_) => FirstRunController.preloaded(done: introDone)),
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
        home: const AboutScreen(),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('the page names the app, its version and both brand lines',
      (WidgetTester t) async {
    await pump(t);
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(AboutScreen)));
    expect(find.text(l.appName.toUpperCase()), findsOneWidget);
    expect(find.text(l.aboutVersion(AppState().getAppVersion())),
        findsOneWidget);
    expect(find.text(l.aboutSubtitleEn), findsOneWidget);
    expect(find.text(l.aboutSubtitleJa), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('the credits screen is what the licence button opens',
      (WidgetTester t) async {
    // Flutter's own licence page groups by package and knows nothing about the
    // native libraries, the fonts or the map data, which are the components
    // with real obligations. The button goes to the app's own flat list now.
    await pump(t);
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(AboutScreen)));
    final Finder button = find.byWidgetPredicate(
        (Widget w) => w is MmAction && w.label == l.aboutLicensesButton);
    expect(button, findsOneWidget);
    expect(t.widget<MmAction>(button).onPressed, isNotNull);
  });

  testWidgets('replaying the intro is offered only once it has been seen',
      (WidgetTester t) async {
    await pump(t, introDone: false);
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(AboutScreen)));
    // An action on this page is an MmAction now, not a Material outlined
    // button: one family per screen, which is the rule the 2026-11-14 audit
    // produced, and this page was carrying three Material buttons.
    final Finder replay = find.byWidgetPredicate(
        (Widget w) => w is MmAction && w.label == l.aboutReplayIntro);
    expect(replay, findsOneWidget);
    expect(t.widget<MmAction>(replay).onPressed, isNull,
        reason: 'an intro that has not been seen cannot be replayed');
  });

  testWidgets('replaying the intro is enabled after one full run',
      (WidgetTester t) async {
    await pump(t);
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(AboutScreen)));
    final Finder replay = find.byWidgetPredicate(
        (Widget w) => w is MmAction && w.label == l.aboutReplayIntro);
    expect(t.widget<MmAction>(replay).onPressed, isNotNull);
  });
}
