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
import 'package:meshmore_sns_app/screens/dashboard_screen.dart';
import 'package:meshmore_sns_app/screens/dashboards/dashboard_host.dart';
import 'package:meshmore_sns_app/screens/dashboards/studio_dashboard.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/mm_collapse_controller.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

/// The face machine data is set in, taken from the skin rather than
/// restated: the rule under test is *words sans, data mono*, and the
/// preset chooses which mono.
final String _mono = mmSkinFor(MmThemePreset.studio).type.monoFamily;

Future<void> _pump(WidgetTester t, MeshcoreController mc) async {
  final ThemeController tc = ThemeController();
  await tc.setPreset(MmThemePreset.studio);
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: tc),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<MmCollapseController>(
            create: (_) => MmCollapseController()),
      ],
      child: Builder(
        builder: (BuildContext c) => MaterialApp(
          theme: c.read<ThemeController>().theme,
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: DashboardHost()),
        ),
      ),
    ),
  );
}

MeshcoreController _mc(FakeMeshcoreTransport fake) => MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );

Future<void> _drain(WidgetTester t, MeshcoreController mc) async {
  mc.dispose();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

Iterable<Text> _texts(WidgetTester t) =>
    t.widgetList<Text>(find.byType(Text)).where((Text w) => w.data != null);

String? _family(WidgetTester t, Text w) {
  final BuildContext ctx = t.element(find.byWidget(w).first);
  return DefaultTextStyle.of(ctx).style.merge(w.style).fontFamily;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  final MmTokens tok = kMmPresets[MmThemePreset.studio]!;

  testWidgets('Studio has its own dashboard, not the SEELE monolith',
      (WidgetTester t) async {
    final MeshcoreController mc = _mc(FakeMeshcoreTransport(connected: true));
    await _pump(t, mc);
    expect(find.byType(StudioDashboard), findsOneWidget);
    expect(find.byType(DashboardScreen), findsNothing);
    await _drain(t, mc);
  });

  testWidgets(
      'offline is a quiet row: text + ring dot, one CONNECT, and no '
      'saturated fill anywhere', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(1100, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = _mc(FakeMeshcoreTransport(connected: true));
    await _pump(t, mc);
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget,
        reason: 'the old banner was read as drawing CONNECT twice');
    // No filled block: no decoration or ColoredBox uses alert / error.
    final Color error =
        Theme.of(t.element(find.byType(StudioDashboard))).colorScheme.error;
    final bool filled = t
            .widgetList<Container>(find.byType(Container))
            .any((Container c) {
          final Decoration? d = c.decoration;
          return d is BoxDecoration &&
              (d.color == tok.alert || d.color == error);
        }) ||
        t
            .widgetList<ColoredBox>(find.byType(ColoredBox))
            .any((ColoredBox c) => c.color == tok.alert || c.color == error);
    expect(filled, isFalse, reason: 'status must not be a colour fill');
    // The ring dot has a border but no fill: shape, not colour, says offline.
    final Iterable<Container> rings = t
        .widgetList<Container>(find.byType(Container))
        .where((Container c) =>
            c.decoration is BoxDecoration &&
            (c.decoration! as BoxDecoration).shape == BoxShape.circle);
    expect(rings, isNotEmpty);
    for (final Container c in rings) {
      expect((c.decoration! as BoxDecoration).color, isNull);
    }
    await _drain(t, mc);
  });

  testWidgets('linked: filled dot, no CONNECT; LOCATION tile carries the fix',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(1100, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _mc(fake);
    await _pump(t, mc);
    await mc.connect();
    fake.emit(selfInfoFrameAt(lat: 38.925, lon: -104.772826));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Connect'), findsNothing);
    expect(find.text('LOCATION'), findsOneWidget);
    expect(find.textContaining('38.92'), findsOneWidget);
    final Iterable<Container> dots = t
        .widgetList<Container>(find.byType(Container))
        .where((Container c) =>
            c.decoration is BoxDecoration &&
            (c.decoration! as BoxDecoration).shape == BoxShape.circle);
    // R97: the dot is the link green, the same hue as the app-bar chip,
    // not the accent grey it used while the chip above it was sage.
    expect(
        dots.any((Container c) =>
            (c.decoration! as BoxDecoration).color == tok.link),
        isTrue,
        reason: 'linked = filled link-green dot');
    await _drain(t, mc);
  });

  testWidgets('type roles: words are sans, only machine data is mono (R68)',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(1100, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _mc(fake);
    await _pump(t, mc);
    await mc.connect();
    fake.emit(selfInfoFrameAt(lat: 38.925, lon: -104.772826));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    // Machine data IS mono.
    final Text coords = t.widget<Text>(find.textContaining('38.92'));
    expect(_family(t, coords), _mono);
    // Section labels, the name and the status are sans (null = UI face).
    for (final String word in <String>[
      'RADIO',
      'LOCATION',
      'RECENT',
      'NODES IN RANGE',
      '(unnamed)',
      'LINKED',
    ]) {
      final Finder f = find.text(word);
      if (f.evaluate().isEmpty) continue;
      expect(_family(t, t.widget<Text>(f.first)), isNot(_mono),
          reason: '"$word" is a word, so it must not be in the data face');
    }
    // And the converse, enforced for the whole screen: every mono string
    // contains a digit (a count, coordinate, parameter, key or time), so no
    // prose or label can drift into the data face unnoticed.
    final RegExp hasDigit = RegExp(r'\d');
    for (final Text w in _texts(t)) {
      if (_family(t, w) == _mono) {
        expect(hasDigit.hasMatch(w.data!), isTrue,
            reason: 'mono text "${w.data}" is not machine data');
      }
    }
    await _drain(t, mc);
  });

  testWidgets('the sections fold, and are open by default',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(1100, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _mc(fake);
    await _pump(t, mc);
    await mc.connect();
    fake.emit(selfInfoFrameAt(lat: 38.925, lon: -104.772826));
    await t.pump();
    expect(find.textContaining('38.92'), findsOneWidget);
    await t.tap(find.text('LOCATION'));
    await t.pump();
    expect(find.textContaining('38.92'), findsNothing);
    expect(find.text('RADIO'), findsOneWidget,
        reason: 'folding one group leaves the others alone');
    await _drain(t, mc);
  });

  testWidgets(
      'R75: the RECENT mono stamp keeps clear of the event text, also at '
      '1.3x text scale', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(1100, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    // The defect only showed up as a collision: the 70dp column was
    // ~3dp narrower than its own 8-character stamp, so at a larger
    // text scale the stamp ran under the event text.
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.platformDispatcher.clearAllTestValues);

    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _mc(fake);
    await _pump(t, mc);
    await mc.connect();
    fake.emit(batteryFrame(4380));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    final Finder stamp =
        find.textContaining(RegExp(r'^\d{2}:\d{2}:\d{2}$'));
    expect(stamp, findsWidgets, reason: 'a battery event should be listed');

    // No fixed-width box around the stamp: mono self-aligns the column.
    expect(
        find.ancestor(
            of: stamp.first,
            matching: find.byWidgetPredicate((Widget w) =>
                w is SizedBox && w.width != null && w.width! >= 60)),
        findsNothing,
        reason: 'a fixed stamp column is narrower than its own text');

    // The stamp must end at least 8dp before the event text starts.
    // With the old fixed column the stamp filled its 70dp box, so it
    // ended exactly where the event text began and this fails.
    final Row row = t.widget<Row>(find
        .ancestor(of: stamp.first, matching: find.byType(Row))
        .first);
    expect(row.children.length, greaterThanOrEqualTo(3));
    final Rect stampRect = t.getRect(stamp.first);
    final Rect eventRect = t.getRect(find.byWidget(row.children.last));
    expect(stampRect.right, lessThanOrEqualTo(eventRect.left - 8),
        reason: 'the stamp must not run into the event text');
    await _drain(t, mc);
  });

}
