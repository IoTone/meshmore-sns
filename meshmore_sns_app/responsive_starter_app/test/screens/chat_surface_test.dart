// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/chat/composer_field.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/chat_screen.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';
import 'package:meshmore_sns_app/ui/mm_shape.dart';

import '../meshcore/fake_transport.dart';

class _SilentSpeaker implements TtsSpeaker {
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> setVoice(TtsVoice? voice) async {}
  @override
  Future<List<TtsVoice>> listVoices() async => const <TtsVoice>[];
  @override
  Future<bool> isLanguageAvailable(String locale) async => true;
}

const List<LocalizationsDelegate<Object>> _delegates =
    <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// The conversation surfaces, on the ground the owner says looks wrong.
///
/// Two rules are pinned here rather than in a screenshot:
///  1. a message field is delimited by its FILL, not by a stroke around it —
///     fill and hairline together is what made the light skins read as a grid
///     of boxes;
///  2. the type-in field takes its corner and its borders from the skin, so it
///     is not the one control that ignores the shape language.
///
/// The fill rule is checked on the bubble skins (Hyperlocal and AG-HUD);
/// Studio and Studio Light draw a row, not a bubble, and have no fill at all.

/// The screen's own pollers are periodic, so they stay pending until the
/// controller is disposed; the harness checks for pending timers before any
/// tear-down runs. Dispose, then let the tree settle.
Future<void> drain(WidgetTester t, MeshcoreController mc) async {
  mc.dispose();
  await t.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<(MeshcoreController, ThemeController, FakeMeshcoreTransport)> pumpChat(
    WidgetTester t,
    MmThemePreset preset, {
    Size size = const Size(360, 780),
    double textScale = 1.0,
  }) async {
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    t.view.physicalSize = size * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    final ThemeController theme = ThemeController();
    await theme.setPreset(preset);
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<TtsController>.value(
            value: TtsController(speaker: _SilentSpeaker())),
      ],
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: _delegates,
          home: const Scaffold(body: ChatScreen()),
        ),
      ),
    ));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();
    // The screen arms pollers and a scroll timer; a test that ends with them
    // pending fails the harness invariant rather than anything the app did.
    return (mc, theme, fake);
  }

  testWidgets('a bubble is a filled field, with no stroke around it',
      (WidgetTester t) async {
    final (MeshcoreController mc, _, FakeMeshcoreTransport fake) =
        await pumpChat(t, MmThemePreset.hyperlocal);
    final MmSkin skin = mmSkinFor(MmThemePreset.hyperlocal);

    fake.emit(channelMsgFrame(text: 'Ada: hello from the field'));
    await t.pumpAndSettle();

    final Iterable<Container> fields = t
        .widgetList<Container>(find.byType(Container))
        .where((Container c) => c.decoration is ShapeDecoration);
    final ShapeDecoration bubble = fields
        .map((Container c) => c.decoration! as ShapeDecoration)
        .firstWhere((ShapeDecoration d) => d.color == skin.color.raised);
    // One delimiter: the fill. A stroke round a filled field says the same
    // edge twice, which is the shape the owner objected to on paper.
    expect((bubble.shape as OutlinedBorder).side, BorderSide.none);

    // …and the fill is one step off the page in THIS skin's stack, not a
    // fixed grey that happens to work on black.
    expect(bubble.color, skin.color.raised);
    expect(bubble.color, isNot(skin.color.base));
    await drain(t, mc);
  });

  testWidgets('the type-in field takes its corner and borders from the skin',
      (WidgetTester t) async {
    final (MeshcoreController mc, ThemeController theme, _) =
        await pumpChat(t, MmThemePreset.air);
    final MmSkin skin = mmSkinFor(MmThemePreset.air);

    final TextField field = t.widget<TextField>(find.byType(TextField).first);
    final InputDecoration d = field.decoration!;
    final OutlineInputBorder enabled = d.enabledBorder! as OutlineInputBorder;
    // The same arithmetic `mmRadius` does, without a build context: a skin
    // with square controls draws the 1 px floor, the others their own corner.
    final double expected = skin.shape.squareControls
        ? kSquareRadius
        : mmCornerFloor(kRadiusSm);
    expect(enabled.borderRadius, BorderRadius.circular(expected));
    // D11.5 — an input is a control, so its resting border is the
    // control-boundary role, not the divider it used to borrow.
    expect(enabled.borderSide.color, skin.color.edge);
    expect(enabled.borderSide.width, skin.shape.borderWidth);
    // Focus is the skin's accent, not Material's primary.
    expect((d.focusedBorder! as OutlineInputBorder).borderSide.color,
        skin.color.accent);
    expect(theme.preset, MmThemePreset.air);
    await drain(t, mc);
  });

  testWidgets('both composers ask for the same decoration',
      (WidgetTester t) async {
    // The helper is the single source; a second call site cannot drift.
    late InputDecoration a;
    late InputDecoration b;
    await t.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
      ],
      child: Builder(builder: (BuildContext context) {
        a = composerFieldDecoration(context, hint: 'channel');
        b = composerFieldDecoration(context, hint: 'dm');
        return const SizedBox.shrink();
      }),
    ));
    expect(a.border, b.border);
    expect(a.enabledBorder, b.enabledBorder);
    expect(a.focusedBorder, b.focusedBorder);
  });

  for (final MmThemePreset preset in <MmThemePreset>[
    MmThemePreset.air,
    MmThemePreset.hyperlocal,
  ]) {
    testWidgets('$preset holds 320 dp at 200 % text', (WidgetTester t) async {
      final (MeshcoreController mc, _, FakeMeshcoreTransport fake) =
          await pumpChat(
        t,
        preset,
        size: const Size(320, 780),
        textScale: 2.0,
      );
      fake.emit(channelMsgFrame(
          text: 'Ada: a message long enough to wrap several times at twice the '
              'text size, with a 64-character key '
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa '
              'and a URL https://example.invalid/a/very/long/path/that/keeps/going'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await drain(t, mc);
    });
  }

  testWidgets('the send control says whether it can act',
      (WidgetTester t) async {
    final (MeshcoreController mc, _, _) =
        await pumpChat(t, MmThemePreset.air);
    final Finder send = find.widgetWithIcon(IconButton, Icons.send);
    IconButton button() => t.widget<IconButton>(send);

    // An empty field with an enabled send was a control that looked pressable
    // and returned in silence.
    expect(button().onPressed, isNull,
        reason: 'nothing typed, nothing to send');

    await t.enterText(find.byType(TextField).first, 'hello');
    await t.pumpAndSettle();
    expect(button().onPressed, isNotNull);

    // Over the radio's byte budget: disabled, and the counter that says why
    // is already on screen.
    await t.enterText(find.byType(TextField).first, 'x' * 400);
    await t.pumpAndSettle();
    expect(button().onPressed, isNull);
    await drain(t, mc);
  });
}
