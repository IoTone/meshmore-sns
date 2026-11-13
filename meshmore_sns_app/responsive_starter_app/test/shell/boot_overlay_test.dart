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
import 'package:meshmore_sns_app/meshcore/reconnect_policy.dart';
import 'package:meshmore_sns_app/shell/boot_overlay.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.log);
  final List<String> log;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.log.add('init');
  }

  @override
  void dispose() {
    widget.log.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('shell');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // R68 — dismissing the overlay used to swap Stack -> bare child, which
  // unmounted the shell and built a second one: every screen's State was
  // created twice at launch (and, once screens carry unique ids, tripped
  // their duplicate-id assertion in debug builds).
  testWidgets('dismissing the overlay keeps the shell mounted (one State)',
      (WidgetTester t) async {
    final List<String> log = <String>[];
    final MeshcoreController mc = MeshcoreController();
    await t.pumpWidget(
      ChangeNotifierProvider<MeshcoreController>.value(
        value: mc,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: BootOverlay(child: _Probe(log)),
        ),
      ),
    );
    expect(log, <String>['init']);
    // No paired radio and not connecting: quiescent, so it dismisses.
    await t.pumpAndSettle();
    expect(find.text('shell'), findsOneWidget);
    expect(log, <String>['init'],
        reason: 'the shell must not be rebuilt as a second State');
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  // The overlay is a launch screen, not a gate. Measured on the handset: a
  // paired radio that was out of range left the whole app behind a spinner for
  // the length of the reconnect ladder (about two and a half minutes), and the
  // only way through was the SKIP button.
  testWidgets('a launch that never settles stops covering the app',
      (WidgetTester t) async {
    final MeshcoreController mc = MeshcoreController(
      reconnectPolicy: ReconnectPolicy(
        base: const Duration(milliseconds: 1),
        random: () => 1.0,
        maxAttempts: 20,
      ),
      reconnectDelay: (Duration d) async {},
      transportFactory: () async => throw StateError('radio is out of range'),
    );
    addTearDown(mc.dispose);
    await t.pumpWidget(
      ChangeNotifierProvider<MeshcoreController>.value(
        value: mc,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const BootOverlay(child: Text('shell')),
        ),
      ),
    );
    await t.pump();
    // A paired radio that will not answer: the ladder keeps trying, and the
    // overlay has to give the app back on its own.
    await mc.connect();
    await t.pump(const Duration(seconds: 1));
    expect(find.text('boot'), findsNothing);
    await t.pump(const Duration(seconds: 10));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('CONNECTING TO RADIO…'), findsNothing,
        reason: 'the launch screen gave the app back');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  // R68 — Studio is monochrome; the boot surface used to flash the NERV
  // orange/lime on every preset.
  Future<List<Color>> bootGradient(WidgetTester t, MmThemePreset? p) async {
    final MeshcoreController mc = MeshcoreController();
    final ThemeController tc = ThemeController();
    if (p != null) await tc.setPreset(p);
    await t.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<ThemeController>.value(value: tc),
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
          home: const BootOverlay(child: Text('shell')),
        ),
      ),
    );
    final Iterable<Container> boxes = t
        .widgetList<Container>(find.byType(Container))
        .where((Container c) =>
            c.decoration is BoxDecoration &&
            (c.decoration! as BoxDecoration).gradient is LinearGradient);
    final List<Color> colors = (((boxes.first.decoration! as BoxDecoration)
            .gradient!) as LinearGradient)
        .colors;
    await t.pumpAndSettle();
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
    return colors;
  }

  testWidgets('Studio boots in its own greys', (WidgetTester t) async {
    final MmTokens st = kMmPresets[MmThemePreset.studio]!;
    expect(await bootGradient(t, MmThemePreset.studio),
        <Color>[st.surface, st.base]);
  });

  testWidgets('no stored choice boots in the skin it will show',
      (WidgetTester t) async {
    // The splash is what the user sees before the theme loads, so a fresh
    // install must not flash a palette that is not the one it is about to
    // render: it takes the default preset's greys, and every other preset
    // keeps the brand palette below.
    final MmTokens def = kMmPresets[kDefaultPreset]!;
    expect(await bootGradient(t, null), <Color>[def.surface, def.base]);
  });

  testWidgets('every preset boots in its own surfaces', (WidgetTester t) async {
    // The launch screen is the most-seen screen in the app, and it used to be
    // the one screen drawn in a palette the reader had not chosen: NERV orange
    // on near-black whatever the preset, with Studio exempt. A reader on
    // Daybreak got a dark console and then a white page.
    for (final MmThemePreset p in MmThemePreset.values) {
      final MmTokens tok = kMmPresets[p]!;
      expect(await bootGradient(t, p), <Color>[tok.surface, tok.base],
          reason: '$p booted in a palette that is not its own');
    }
  });

  testWidgets('the launch screen holds a 320 dp phone at 200 % text',
      (WidgetTester t) async {
    // The overlay is not a route, so `a11y_floors_test` cannot reach it, and it
    // is the first thing every launch draws: a clipped name here is the first
    // thing a reader ever sees.
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);

    final MeshcoreController mc = MeshcoreController();
    await t.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
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
          home: BootOverlay(child: _Probe(<String>[])),
        ),
      ),
    );
    await t.pump();
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(BootOverlay)));
    // Both halves of the name are present and neither is ellipsised: the header
    // wraps above the subtitle rather than truncating the app's own name.
    expect(find.text(l.bootHeader), findsOneWidget);
    expect(find.text(l.bootSubtitle), findsOneWidget);
    for (final Text w in t.widgetList<Text>(find.byType(Text))) {
      expect(w.overflow, anyOf(isNull, TextOverflow.visible, TextOverflow.clip));
    }
    expect(t.takeException(), isNull,
        reason: 'the launch screen overflowed at the a11y floor');
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

}
