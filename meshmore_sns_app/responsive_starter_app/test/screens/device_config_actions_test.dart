// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/device_config_screen.dart';
import 'package:meshmore_sns_app/ui/mm_components.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

const List<LocalizationsDelegate<Object>> _kLocaleDelegates =
    <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// Device configuration says one thing the same way everywhere.
///
/// The owner's report (2026-11-14): "buttons like Set name and Set advert
/// location seem to be kind of weirdly placed ... or just get irregularly
/// done". The screen used four button families — a Material filled pill for the
/// radio write, two Material outlined pills for the location helpers, and
/// right-aligned dense `MmAction`s floating under a full-width field for the
/// name and the coordinates. Three placements, two enabled policies, one act.
///
/// These assertions are the shape of the answer, so a later edit cannot quietly
/// reintroduce a second family or a second placement on this screen.
void main() {
  Future<MeshcoreController> pump(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: _kLocaleDelegates,
        home: ChangeNotifierProvider<MeshcoreController>.value(
          value: ctrl,
          child: const DeviceConfigScreen(),
        ),
      ),
    );
    await ctrl.connect();
    fake.emit(selfInfoFrame());
    fake.emit(deviceInfoFrame());
    await t.pumpAndSettle();
    return ctrl;
  }

  /// The `MmAction` that carries this label.
  MmAction action(WidgetTester t, String label) {
    final Finder f = find.byWidgetPredicate(
      (Widget w) => w is MmAction && w.label == label,
      description: 'MmAction "$label"',
    );
    expect(f, findsOneWidget, reason: 'no MmAction labelled "$label"');
    return t.widget<MmAction>(f);
  }

  testWidgets('every write on the screen is one family, in one host',
      (WidgetTester t) async {
    final MeshcoreController ctrl = await pump(t);

    // No Material action families left on the surface: the emphasis is the
    // fill of MmAction.primary, not a different widget.
    expect(find.byType(FilledButton), findsNothing,
        reason: 'the primary write is MmAction(primary: true) now');
    expect(find.byType(OutlinedButton), findsNothing,
        reason: 'the location helpers are MmActions now');

    // Every commit action sits inside an MmActionRow, so the placement is a
    // property of the group rather than of the button.
    for (final String label in <String>[
      'Apply radio params',
      'Set name',
      'Set advert location',
      'Use phone location',
      'Read device location',
    ]) {
      final Finder row = find.ancestor(
        of: find.byWidgetPredicate(
            (Widget w) => w is MmAction && w.label == label),
        matching: find.byType(MmActionRow),
      );
      expect(row, findsOneWidget, reason: '"$label" must sit in an MmActionRow');
    }

    // The three writes are the filled ones, and only they are.
    expect(action(t, 'Apply radio params').primary, isTrue);
    expect(action(t, 'Set name').primary, isTrue);
    expect(action(t, 'Set advert location').primary, isTrue);
    expect(action(t, 'Use phone location').primary, isFalse);
    expect(action(t, 'Read device location').primary, isFalse);
    expect(action(t, 'Load from device').primary, isFalse);

    ctrl.dispose();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a write that cannot run says why instead of going grey',
      (WidgetTester t) async {
    // Same policy on every write on this screen (R25+3, applied to all three):
    // the control stays tappable and names what is missing.
    final MeshcoreController ctrl = await pump(t);
    ctrl.dispose();
    final MeshcoreController offline = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: false),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: _kLocaleDelegates,
        home: ChangeNotifierProvider<MeshcoreController>.value(
          value: offline,
          child: const DeviceConfigScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
    for (final String label in <String>[
      'Apply radio params',
      'Set name',
      'Set advert location',
    ]) {
      final MmAction a = action(t, label);
      expect(a.onPressed, isNotNull,
          reason: '"$label" is disabled when there is no radio; it must '
              'name the missing radio instead');
    }
    offline.dispose();
  });

  testWidgets('one write carries the advert policy and the pair together',
      (WidgetTester t) async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.binding.setSurfaceSize(const Size(900, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: _kLocaleDelegates,
        home: ChangeNotifierProvider<MeshcoreController>.value(
          value: ctrl,
          child: const DeviceConfigScreen(),
        ),
      ),
    );
    await ctrl.connect();
    fake.emit(selfInfoFrame());
    fake.emit(deviceInfoFrame());
    await t.pumpAndSettle();

    // Picking a policy segment must not put a frame on the wire by itself:
    // it used to transmit before the coordinates in the same section were
    // even typed.
    final int before26 =
        fake.sent.where((f) => f.isNotEmpty && f[0] == 0x26).length;
    await t.tap(find.text('Pinned'));
    await t.pumpAndSettle();
    expect(fake.sent.where((f) => f.isNotEmpty && f[0] == 0x26).length, before26,
        reason: 'selecting the advert source stages it, it does not send');

    await t.enterText(
        find.widgetWithText(TextField, 'Advert latitude (°)'), '38.919872');
    await t.enterText(
        find.widgetWithText(TextField, 'Advert longitude (°)'), '-104.772880');
    await t.pumpAndSettle();

    final int before0E =
        fake.sent.where((f) => f.isNotEmpty && f[0] == 0x0E).length;
    await t.tap(find.text('Set advert location'));
    await t.pumpAndSettle();
    expect(fake.sent.where((f) => f.isNotEmpty && f[0] == 0x0E).length,
        before0E + 1,
        reason: 'the save sends the coordinates (0x0E)');
    expect(fake.sent.where((f) => f.isNotEmpty && f[0] == 0x26).length,
        before26 + 1,
        reason: 'and the policy it staged (0x26)');
    ctrl.dispose();
  });
}
