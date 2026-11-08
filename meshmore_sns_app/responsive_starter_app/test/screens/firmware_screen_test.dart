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
import 'package:meshmore_sns_app/screens/firmware_screen.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// D8.19 is a decision with a reason, and the reason is the page.
///
/// An install consumes the radio's offline queue, so the app reads status and
/// refuses to start one. The refusal is a value the page renders, not an
/// exception a caller can swallow, and there must be no control on the page that
/// installs anything.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport();
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    addTearDown(mc.dispose);
    await t.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AppState>(create: (_) => AppState()),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
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
        home: const FirmwareScreen(),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('says what it knows, and admits what it does not',
      (WidgetTester t) async {
    await pump(t);
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(FirmwareScreen)));
    expect(find.text(l.firmwareTitle), findsOneWidget);
      // It appears twice: as the capability row and as the gate's answer.
      expect(find.text(l.firmwareOtaUnknown), findsWidgets,
          reason: 'with no radio the capability is unknown, not absent');
    // The app's own version is always here; the radio's is a dash.
    expect(find.text(AppState().getAppVersion()), findsOneWidget);
  });

  testWidgets('the refusal names the cost and offers no control',
      (WidgetTester t) async {
    await pump(t);
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(FirmwareScreen)));
    expect(find.textContaining(l.firmwareNoInstallWhy), findsWidgets);
    // Nothing on this page installs, and nothing pretends to check.
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
