// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/device_config_screen.dart';

import '../meshcore/fake_transport.dart';

/// Device finding (motorola edge 2024, 387dp, system font scale 1.3): the
/// telemetry-sharing rows on Device configuration broke "Environment" as
/// "Environme / nt" because the label column was a fixed 88dp.
Future<void> _bundledFonts() async {
  for (final MapEntry<String, String> e in <String, String>{
    'Saira': 'assets/fonts/Saira.ttf',
    'JetBrains Mono': 'assets/fonts/JetBrainsMono.ttf',
  }.entries) {
    final FontLoader fl = FontLoader(e.key)
      ..addFont(Future<ByteData>.value(
          ByteData.sublistView(File(e.value).readAsBytesSync())));
    await fl.load();
  }
}

/// The screen is a lazy ListView: bring the telemetry rows into the build range.
Future<void> _toTelemetry(WidgetTester t) async {
  await t.scrollUntilVisible(find.text('Environment'), 400,
      scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

Future<MeshcoreController> _pump(
    WidgetTester t, {required double width, required double scale}) async {
  t.view.physicalSize = Size(width, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
  final MeshcoreController mc =
      MeshcoreController(transportFactory: () async => fake);
  await t.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: LocaleController.supported,
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(fontFamily: 'Saira'),
    builder: (BuildContext c, Widget? child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: ChangeNotifierProvider<MeshcoreController>.value(
      value: mc,
      child: const DeviceConfigScreen(),
    ),
  ));
  await mc.connect();
  fake.emit(selfInfoFrame());
  await t.pumpAndSettle();
  return mc;
}

void main() {
  setUpAll(_bundledFonts);

  test('the label column is 88dp at normal size and grows to a 120dp cap', () {
    expect(telemLabelWidth(TextScaler.noScaling), 88);
    expect(telemLabelWidth(const TextScaler.linear(0.8)), 88,
        reason: 'never narrower than before');
    expect(telemLabelWidth(const TextScaler.linear(1.3)), closeTo(114.4, 0.01));
    expect(telemLabelWidth(const TextScaler.linear(3.0)), 120);
  });

  testWidgets('"Environment" stays on one line at 1.3x on a 387dp phone',
      (WidgetTester t) async {
    final MeshcoreController mc = await _pump(t, width: 387, scale: 1.3);
    await _toTelemetry(t);
    final Finder env = find.text('Environment');
    expect(env, findsOneWidget);
    final double one = t.getSize(find.text('Base')).height;
    expect(t.getSize(env).height, one,
        reason: 'one line, same height as "Base"');
    expect(t.takeException(), isNull);
    mc.dispose();
  });

  testWidgets('at 1.0x the column is unchanged (88dp)',
      (WidgetTester t) async {
    final MeshcoreController mc = await _pump(t, width: 387, scale: 1.0);
    await _toTelemetry(t);
    final Rect base = t.getRect(find.text('Base'));
    final Rect seg = t.getRect(find
        .descendant(
            of: find.byType(SegmentedButton<int>).last,
            matching: find.text('Off'))
        .first);
    // label box is 88 wide, then an 8dp gap, then the segments.
    expect(base.left, 16, reason: 'page padding');
    expect(seg.left, greaterThan(16 + 88 + 8));
    expect(t.takeException(), isNull);
    mc.dispose();
  });

  testWidgets('no overflow at 320dp even at 2.0x', (WidgetTester t) async {
    final MeshcoreController mc = await _pump(t, width: 320, scale: 2.0);
    await _toTelemetry(t);
    expect(t.takeException(), isNull);
    mc.dispose();
  });
}
