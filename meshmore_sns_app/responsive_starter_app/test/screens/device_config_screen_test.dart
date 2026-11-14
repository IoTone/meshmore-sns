// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/device_config_screen.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
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


/// The radio-config transaction sends its three writes one at a time and
/// waits for each answer, as the firmware requires: a bare OK per command
/// (`MyMesh.cpp:1386-1478`). The fake radio answers in order.
Future<void> answerRadioConfig(
    WidgetTester t, FakeMeshcoreTransport fake) async {
  for (int i = 0; i < 3; i++) {
    fake.emit(Uint8List.fromList(<int>[0x00]));
    await t.pump();
  }
}

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
    fake.emit(deviceInfoFrame());
    await t.pumpAndSettle();

    final int before0B =
        fake.sent.where((f) => f.isNotEmpty && f[0] == 0x0B).length;
    final int before0C =
        fake.sent.where((f) => f.isNotEmpty && f[0] == 0x0C).length;

    // The preset chooser is a row; a pick fills the form and nothing is sent
    // until Apply.
    await t.tap(find.text('Band preset'));
    await t.pumpAndSettle();
    await t.tap(find.text('USA / Canada'));
    await t.pumpAndSettle();
    expect(fake.sent.where((f) => f.isNotEmpty && f[0] == 0x0B).length, before0B,
        reason: 'picking a preset must not send');
    await t.tap(find.text('Apply radio params'));
    await t.pumpAndSettle();
    await answerRadioConfig(t, fake);

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
    fake.emit(deviceInfoFrame());
    await t.pumpAndSettle();

    await t.tap(find.text('Band preset'));
    await t.pumpAndSettle();
    await t.tap(find.text('Japan (ARIB STD-T108)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Apply radio params'));
    await t.pumpAndSettle();
    await answerRadioConfig(t, fake);

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
    // The tail field only exists from protocol 10, and the decoder now reads the
    // length as well as the version: an 82-byte frame claiming protocol 9 is
    // inconsistent, and a real radio would not send one.
    fake.emit(deviceInfoFrame(fwVer: 10, pathHashMode: 2));
    await t.pumpAndSettle();

    final Iterable<SegmentedButton<int>> segs = t
        .widgetList<SegmentedButton<int>>(find.byType(SegmentedButton<int>));
    expect(segs.any((SegmentedButton<int> s) => s.selected.contains(3)), isTrue,
        reason: 'device path_hash_mode 2 means a 3-byte hash is in force');

    await t.tap(find.text('Apply radio params'));
    await t.pumpAndSettle();
    await answerRadioConfig(t, fake);

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
    await t.tap(find.text('Band preset'));
    await t.pumpAndSettle();
    await t.tap(find.text('Hungary'));
    await t.pumpAndSettle();
    await t.tap(find.text('Apply radio params'));
    await t.pumpAndSettle();
    await answerRadioConfig(t, fake);
    expect(
        fake.sent
            .where((List<int> f) => f.isNotEmpty && f[0] == 0x3D)
            .toList(),
        <List<int>>[
          <int>[0x3D, 0, 1]
        ]);
    ctrl.dispose();
  });

  testWidgets('USA / Canada applies the radio tuple and keeps the path hash '
      'size in force (the feed lists one for Canada only)', (WidgetTester t) async {
    final (FakeMeshcoreTransport fake, MeshcoreController ctrl) =
        await openScreen(t);
    await t.tap(find.text('Band preset'));
    await t.pumpAndSettle();
    await t.tap(find.text('USA / Canada'));
    await t.pumpAndSettle();
    await t.tap(find.text('Apply radio params'));
    await t.pumpAndSettle();
    await answerRadioConfig(t, fake);
    expect(fake.sent.any((List<int> f) => f.isNotEmpty && f[0] == 0x0B), isTrue);
    // The operating point is written whole, so the hash size is written too --
    // with the value already in force (deviceInfoFrame's mode 0 = 1 byte), not
    // with a value the feed invents for a country that has none.
    expect(
        fake.sent
            .where((List<int> f) => f.isNotEmpty && f[0] == 0x3D)
            .toList(),
        <List<int>>[
          <int>[0x3D, 0, 0]
        ],
        reason: 'a preset without a hash size must not change the one in force '
            '(deviceInfoFrame mode 0, so the wire byte stays 0)');
    ctrl.dispose();
  });

  testWidgets('W2 the label sizes come from the skin ladder, not literals',
      (WidgetTester t) async {
    // Four roles replaced literals here: a quiet family heading and helper
    // (11 -> sizeSm), a list label and the section label (12 -> sizeBody),
    // the "currently applied" caption (10 -> sizeMicro) and the region name
    // (15, no role, size()). Under SEELE the scale is 1.0, so every one of
    // them must still resolve to the number it replaced.
    await t.binding.setSurfaceSize(const Size(900, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MmType type = mmSkinFor(MmThemePreset.seele).type;
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
    await t.pumpAndSettle();

    Text find1(String s) => t.widget<Text>(find.text(s));
    // CHANNELS is a section header now, not a hand-rolled letter-spaced Text,
    // so it answers to the shared section-label role: the small ladder step and
    // the skin's own tracking. The point of the assertion is unchanged — the
    // size is a role, never a literal — but a literal is exactly what the old
    // 12 was, so the role is what gets asserted here.
    expect(find1('CHANNELS').style?.fontSize, mmSectionLabelStyle(
        mmSkinFor(MmThemePreset.seele)).fontSize);
    expect(find1('CHANNELS').style?.letterSpacing,
        mmSectionLabelStyle(mmSkinFor(MmThemePreset.seele)).letterSpacing);
    expect(find1('Path hash size').style?.fontSize, type.sizeBody);
    expect(find1('Path hash size').style?.fontSize, 12);

    ctrl.dispose();
    await t.pumpWidget(const SizedBox());
  });
}
