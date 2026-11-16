// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/bot/bot_controller.dart';
import 'package:meshmore_sns_app/meshcore/discovered_node.dart';
import 'package:meshmore_sns_app/peer/peer_profiles.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/node_detail_sheet.dart';
import 'package:meshmore_sns_app/screens/nodes_screen.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

const List<LocalizationsDelegate<Object>> _delegates =
    <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// The node surfaces on a paper ground.
///
/// The rule pinned here: a **tag** is delimited by its tint alone; a
/// **callout** (a paragraph with an action) keeps its hairline. A tint and a
/// stroke in the same colour on one small pill says the same edge twice, which
/// is the "small box" a reader sees on a light skin.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<(MeshcoreController, ThemeController, FakeMeshcoreTransport)> pumpNodes(
    WidgetTester t, {
    Size size = const Size(360, 780),
    double textScale = 1.0,
  }) async {
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    final ThemeController theme = ThemeController();
    await theme.setPreset(MmThemePreset.air);
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
      ],
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: _delegates,
          home: const Scaffold(body: NodesScreen()),
        ),
      ),
    ));
    await mc.connect();
    fake.emit(selfInfoFrame());
    // One heard node, so the floor is measured on a row and not only on the
    // empty state.
    fake.emit(advertFrame(name: 'Ada', firstPubByte: 0xA1));
    await t.pumpAndSettle();
    mc.dispose();
    await t.pump(const Duration(seconds: 1));
    return (mc, theme, fake);
  }

  testWidgets('a status pill on the detail sheet carries a tint, not a stroke',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final ThemeController theme = ThemeController();
    await theme.setPreset(MmThemePreset.air);
    final MeshcoreController mc = MeshcoreController();
    final DiscoveredNode node = DiscoveredNode(
      pubKeyHex: 'ab' * 32,
      name: 'Ada',
      type: 1,
      lastHeardUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      viaAdvert: true,
    );
    await t.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        // The sheet's own sections read these two: the peer profile picker
        // and the bot scope block.
        ChangeNotifierProvider<PeerProfiles>(create: (_) => PeerProfiles()),
        ChangeNotifierProvider<BotController>(create: (_) => BotController()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: _delegates,
        home: Scaffold(
          // The sheet draws chips and tiles: it needs a Material ancestor,
          // which the modal bottom sheet provides in the app.
          body: NodeDetailSheet(
            node: node,
            distanceMeters: 120,
            isFavourite: false,
            isKnown: true,
            onToggleFavourite: () {},
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();

    final MmSkin skin = mmSkinFor(MmThemePreset.air);
    final Finder chips = find.byWidgetPredicate((Widget w) =>
        w is Container &&
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('node-chip-'));
    expect(chips, findsWidgets, reason: 'the sheet draws its status tags');
    for (final Container chip in t.widgetList<Container>(chips)) {
      final BoxDecoration d = chip.decoration! as BoxDecoration;
      expect(d.border, isNull,
          reason: 'a tinted pill with a stroke in the same colour is a box');
      expect(d.color, isNotNull, reason: 'the tint is what delimits a tag');
    }
    expect(skin.color.base, isNot(skin.color.surfaceAlt));
    mc.dispose();
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('the nodes list holds 320 dp at 200 % text on paper',
      (WidgetTester t) async {
    await pumpNodes(t, size: const Size(320, 780), textScale: 2.0);
    expect(find.textContaining('Ada'), findsWidgets,
        reason: 'the floor is measured on a row, not on the empty state');
    expect(t.takeException(), isNull);
  });
}
