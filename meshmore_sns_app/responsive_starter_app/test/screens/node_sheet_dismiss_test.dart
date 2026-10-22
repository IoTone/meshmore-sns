// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/bot/bot_controller.dart';
import 'package:meshmore_sns_app/cue/cue_service.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/meshcore/discovered_node.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/peer/peer_profiles.dart';
import 'package:meshmore_sns_app/screens/node_detail_sheet.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/fake_transport.dart';

final String peerHex = 'cd' * 32;

DiscoveredNode _node() => DiscoveredNode(
      pubKeyHex: peerHex,
      name: 'Bravo',
      type: 1,
      lastHeardUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      viaAdvert: true,
    );

NodeDetailSheet _sheet({bool cameFromDm = false}) => NodeDetailSheet(
      node: _node(),
      distanceMeters: null,
      isFavourite: false,
      isKnown: true,
      cameFromDm: cameFromDm,
      onToggleFavourite: () {},
    );

Widget _app(Widget home) {
  final ThemeController theme = ThemeController();
  final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true));
  addTearDown(mc.dispose);
  return MultiProvider(
    providers: <ChangeNotifierProvider<ChangeNotifier>>[
      ChangeNotifierProvider<PeerProfiles>(create: (_) => PeerProfiles()),
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<MeshcoreController>.value(value: mc),
      ChangeNotifierProvider<BotController>(create: (_) => BotController()),
    ],
    child: Provider<CueService>.value(
      value: CueService(theme: theme),
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('R96 the sheet can be dismissed without the scrim', (t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await t.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_app(Scaffold(
      body: Builder(
        builder: (BuildContext c) => Center(
          child: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: c,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (BuildContext _) => _sheet(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byType(NodeDetailSheet), findsOneWidget);

    // A tap target, not only the drag handle / scrim / OS back gesture.
    final Finder close = find.byTooltip('Close');
    expect(close, findsOneWidget);
    await t.tap(close);
    await t.pumpAndSettle();
    expect(find.byType(NodeDetailSheet), findsNothing,
        reason: 'the close button dismisses the sheet');
    expect(t.takeException(), isNull);
  });

  testWidgets('R96 a sheet opened from a DM does not offer Message',
      (t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await t.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(_app(Scaffold(body: _sheet(cameFromDm: true))));
    await t.pump();
    expect(find.byIcon(Icons.send), findsNothing,
        reason: 'pushing /dm for the thread we came from stacks a duplicate');
    // The favourite action stays.
    expect(find.byIcon(Icons.star_border), findsOneWidget);

    await t.pumpWidget(_app(Scaffold(body: _sheet())));
    await t.pump();
    expect(find.byIcon(Icons.send), findsOneWidget,
        reason: 'every other entry point keeps the Message action');
    expect(t.takeException(), isNull);
  });
}
