// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_connection.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/device_config_screen.dart';

import '../meshcore/fake_transport.dart';

const List<LocalizationsDelegate<Object>> _kLocaleDelegates =
    <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

void main() {
  testWidgets('R39: tapping USA/Canada chip applies the canonical '
      'tuple (910.525 / 62.5 / SF7 / CR5 / 22 dBm) — emits 0x0B + 0x0C',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
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
    await t.pumpAndSettle();

    final int before0B =
        fake.sent.where((f) => f.isNotEmpty && f[0] == 0x0B).length;
    final int before0C =
        fake.sent.where((f) => f.isNotEmpty && f[0] == 0x0C).length;

    // R103: the band picker is folded until asked for.
    await t.tap(find.text('REGION / BAND'));
    await t.pumpAndSettle();
    await t.tap(find.text('USA / Canada'));
    await t.pumpAndSettle();

    // Form fields were filled.
    String fieldText(String label) => t
        .widget<TextField>(find.widgetWithText(TextField, label))
        .controller!
        .text;
    expect(fieldText('Frequency (MHz)'), '910.525');
    expect(fieldText('Bandwidth (kHz)'), '62.5');
    expect(fieldText('Spreading factor (5–12)'), '7');
    expect(fieldText('Coding rate (5–8)'), '5');
    expect(fieldText('TX power (dBm)'), '22');

    // And the wire frames went out immediately.
    final int after0B =
        fake.sent.where((f) => f.isNotEmpty && f[0] == 0x0B).length;
    final int after0C =
        fake.sent.where((f) => f.isNotEmpty && f[0] == 0x0C).length;
    expect(after0B, before0B + 1,
        reason: 'preset tap should emit CMD_SET_RADIO_PARAMS (0x0B)');
    expect(after0C, before0C + 1,
        reason: 'preset tap should emit CMD_SET_RADIO_TX_POWER (0x0C)');
    ctrl.dispose();
  });

  testWidgets('R39: tapping Japan (ARIB STD-T108) chip applies '
      '923.2 / 125 / SF10 / CR5 / 13 dBm', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
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
    await t.pumpAndSettle();

    await t.tap(find.text('REGION / BAND'));
    await t.pumpAndSettle();
    await t.tap(find.text('Japan (ARIB STD-T108)'));
    await t.pumpAndSettle();

    String fieldText(String label) => t
        .widget<TextField>(find.widgetWithText(TextField, label))
        .controller!
        .text;
    expect(fieldText('Frequency (MHz)'), '923.2');
    expect(fieldText('Bandwidth (kHz)'), '125.0');
    expect(fieldText('Spreading factor (5–12)'), '10');
    expect(fieldText('Coding rate (5–8)'), '5');
    expect(fieldText('TX power (dBm)'), '13');
    expect(fake.sent.any((f) => f.isNotEmpty && f[0] == 0x0B), isTrue);
    ctrl.dispose();
  });

  testWidgets('Identity/Advert: Set name → 0x08, Set location → 0x0E',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 3200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
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
    await t.pumpAndSettle();

    final Finder scrollable = find.byType(Scrollable).first;
    await t.scrollUntilVisible(find.text('Set name'), 400,
        scrollable: scrollable);
    await t.enterText(
        find.widgetWithText(TextField, 'Advert name'),
        'NodeA');
    await t.tap(find.text('Set name'));
    await t.pumpAndSettle();
    expect(fake.sent.any((f) => f.isNotEmpty && f[0] == 0x08), isTrue);

    await t.scrollUntilVisible(
        find.text('Set advert location'), 400,
        scrollable: scrollable);
    await t.enterText(
        find.widgetWithText(TextField, 'Advert latitude (°)'), '35.681');
    await t.enterText(
        find.widgetWithText(TextField, 'Advert longitude (°)'),
        '139.767');
    await t.tap(find.text('Set advert location'));
    await t.pumpAndSettle();
    expect(fake.sent.any((f) => f.isNotEmpty && f[0] == 0x0E), isTrue);
    ctrl.dispose();
  });

  testWidgets('path hash size loads from DeviceInfo and is applied with '
      'the radio params (0x3D)', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
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
    // Wire field is mode (0..2); the UI shows bytes (1..3).
    fake.emit(deviceInfoFrame(pathHashMode: 2));
    await t.pumpAndSettle();

    final Iterable<SegmentedButton<int>> segs = t
        .widgetList<SegmentedButton<int>>(find.byType(SegmentedButton<int>));
    expect(segs.any((SegmentedButton<int> s) => s.selected.contains(3)), isTrue,
        reason: 'device path_hash_mode 2 means a 3-byte hash is in force');

    await t.tap(find.text('Apply radio params'));
    await t.pumpAndSettle();

    final List<List<int>> hashes = fake.sent
        .where((List<int> f) => f.isNotEmpty && f[0] == 0x3D)
        .toList();
    expect(hashes, isNotEmpty,
        reason: 'applying radio params must also send CMD_SET_PATH_HASH_MODE');
    expect(hashes.last, <int>[0x3D, 0, 2]);
    ctrl.dispose();
  });

  Future<(FakeMeshcoreTransport, MeshcoreController)> openScreen(
      WidgetTester t) async {
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
    return (fake, ctrl);
  }

  testWidgets('a preset that carries a path hash size applies it (Hungary: '
      '2 bytes -> mode 1)', (WidgetTester t) async {
    final (FakeMeshcoreTransport fake, MeshcoreController ctrl) =
        await openScreen(t);
    await t.tap(find.text('REGION / BAND'));
    await t.pumpAndSettle();
    await t.tap(find.text('Hungary'));
    await t.pumpAndSettle();
    expect(
        fake.sent
            .where((List<int> f) => f.isNotEmpty && f[0] == 0x3D)
            .toList(),
        <List<int>>[
          <int>[0x3D, 0, 1]
        ]);
    ctrl.dispose();
  });

  testWidgets('USA / Canada applies the radio tuple but NEVER a path hash '
      'size (the feed lists one for Canada only)', (WidgetTester t) async {
    final (FakeMeshcoreTransport fake, MeshcoreController ctrl) =
        await openScreen(t);
    await t.tap(find.text('REGION / BAND'));
    await t.pumpAndSettle();
    await t.tap(find.text('USA / Canada'));
    await t.pumpAndSettle();
    expect(fake.sent.any((List<int> f) => f.isNotEmpty && f[0] == 0x0B), isTrue);
    expect(fake.sent.any((List<int> f) => f.isNotEmpty && f[0] == 0x3D), isFalse,
        reason: 'the feed lists a hash size for Canada only; a US user keeps theirs');
    ctrl.dispose();
  });
}
