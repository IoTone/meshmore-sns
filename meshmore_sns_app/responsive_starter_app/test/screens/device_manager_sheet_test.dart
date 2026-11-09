// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/device_contacts_screen.dart';
import 'package:meshmore_sns_app/screens/device_manager_sheet.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

const List<LocalizationsDelegate<Object>> _kLocaleDelegates =
    <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// On a real phone this row did nothing: four taps, the sheet stayed open, no
/// exception, while `Scan` and the buttons beside it in the same sheet answered
/// (`meshmore-sns-architecture-audit.md`, D2). That screen is the only place a
/// full contact table can be freed, so if the row is dead the recovery path is
/// dead with it. This test drives the real opener and the real modal, because
/// the interesting part is the navigator hand-off inside the tap handler.

void main() {
  testWidgets('the device sheet opens Radio contacts', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );

    // The provider goes ABOVE MaterialApp: showModalBottomSheet pushes onto the
    // app's navigator, which is below MaterialApp, and the real app has the
    // controller above it for the same reason.
    await t.pumpWidget(ChangeNotifierProvider<MeshcoreController>.value(
      value: ctrl,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: _kLocaleDelegates,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => DeviceManagerSheet.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));

    await ctrl.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.contacts_outlined), findsOneWidget,
        reason: 'the sheet only offers this row once the radio is ready');

    await t.tap(find.byIcon(Icons.contacts_outlined));
    await t.pumpAndSettle();

    expect(find.byType(DeviceContactsScreen), findsOneWidget,
        reason: 'tapping Radio contacts must push the screen that can free '
            'contact-table slots; a full table otherwise has no recovery path');

    // The controller schedules a reconnect timer; the binding refuses to end a
    // test with one pending, so stop it and let the tree settle first.
    ctrl.dispose();
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('the sheet holds 320 dp at 200 % text on paper',
      (WidgetTester t) async {
    // The sheet is where a radio is chosen and forgotten, often one-handed, and
    // it is a modal: there is no app bar to scroll past and no second route out.
    // Paper is the ground it is read on in daylight.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ThemeController tc = ThemeController();
    await tc.setPreset(MmThemePreset.air);
    t.view.physicalSize = const Size(320, 780);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<MeshcoreController>.value(value: ctrl),
        ChangeNotifierProvider<ThemeController>.value(value: tc),
      ],
      child: MaterialApp(
        theme: tc.theme,
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: _kLocaleDelegates,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => DeviceManagerSheet.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await ctrl.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull,
        reason: 'the device sheet overflowed at the accessibility floor');
    ctrl.dispose();
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('Radio contacts still opens at phone size with 1.3x text',
      (WidgetTester t) async {
    // The device this failed on runs font_scale 1.3 at 1080x2400 (400 dpi), so
    // the sheet's Column is taller than the space it is given. Children that
    // overflow a box are painted but are NOT hit-testable, which is exactly the
    // symptom: the row is visible, taps do nothing, and the sheet never closes
    // because the tap never reaches the barrier either.
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );

    await t.pumpWidget(ChangeNotifierProvider<MeshcoreController>.value(
      value: ctrl,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: _kLocaleDelegates,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => DeviceManagerSheet.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));

    await ctrl.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.contacts_outlined));
    await t.pumpAndSettle();

    expect(find.byType(DeviceContactsScreen), findsOneWidget);

    ctrl.dispose();
    await t.pump(const Duration(seconds: 1));
  });
}
