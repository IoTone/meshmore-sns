// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/chat/channel_read_store.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/dashboards/pinned_cards_section.dart';
import 'package:meshmore_sns_app/shell/shell_view_request.dart';
import 'package:meshmore_sns_app/sos/sos_controller.dart';
import 'package:meshmore_sns_app/telemetry/coverage_session.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/dashboard_pins_controller.dart';
import 'package:meshmore_sns_app/ui/mm_pin_card.dart';

import '../meshcore/fake_transport.dart';

Widget _host({
  required ThemeController tc,
  required DashboardPinsController pins,
  MeshcoreController? mc,
  SosController? sos,
  CoverageSession? coverage,
  PlaceStore? places,
}) {
  final MeshcoreController controller = mc ??
      MeshcoreController(transportFactory: () async => FakeMeshcoreTransport());
  return MultiProvider(
    providers: <SingleChildWidget>[
      ChangeNotifierProvider<ThemeController>.value(value: tc),
      ChangeNotifierProvider<DashboardPinsController?>.value(value: pins),
      ChangeNotifierProvider<MeshcoreController>.value(value: controller),
      ChangeNotifierProvider<SosController>.value(
          value: sos ?? SosController(mc: controller, autoTick: false)),
      if (coverage != null)
        ChangeNotifierProvider<CoverageSession>.value(value: coverage),
      ChangeNotifierProvider<PlaceStore>.value(value: places ?? PlaceStore()),
      ChangeNotifierProvider<ChannelReadStore?>.value(
          value: ChannelReadStore()),
      ChangeNotifierProvider<BlockStore>.value(value: BlockStore()),
      ChangeNotifierProvider<ShellViewRequest?>.value(
          value: ShellViewRequest()),
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
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: SingleChildScrollView(child: PinnedCardsSection()),
        ),
      ),
    ),
  );
}

Future<DashboardPinsController> _pins(List<String> ids) async {
  final DashboardPinsController c = DashboardPinsController();
  await c.load();
  for (final String id in ids) {
    await c.pin(id);
  }
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('nothing pinned renders nothing at all', (WidgetTester t) async {
    final DashboardPinsController pins = await _pins(<String>[]);
    await t.pumpWidget(_host(tc: ThemeController(), pins: pins));
    expect(find.byType(MmPinCard), findsNothing);
    expect(find.text('Pinned'), findsNothing);
  });

  testWidgets('cards render in the order the user put them',
      (WidgetTester t) async {
    final DashboardPinsController pins =
        await _pins(<String>[MmPinIds.coverage, MmPinIds.sos]);
    final CoverageSession coverage = CoverageSession(
      mc: MeshcoreController(
          transportFactory: () async => FakeMeshcoreTransport()),
      pinger: null,
    );
    await t.pumpWidget(_host(
      tc: ThemeController(),
      pins: pins,
      coverage: coverage,
    ));
    final List<String> keys = t
        .widgetList<MmPinCard>(find.byType(MmPinCard))
        .map((MmPinCard c) => (c.key! as ValueKey<String>).value)
        .toList();
    expect(keys, <String>[
      'pin-card-${MmPinIds.coverage}',
      'pin-card-${MmPinIds.sos}',
    ]);
  });

  testWidgets('unpinning from edit mode removes the card and persists',
      (WidgetTester t) async {
    final DashboardPinsController pins =
        await _pins(<String>[MmPinIds.sos, MmPinIds.places]);
    await t.pumpWidget(_host(tc: ThemeController(), pins: pins));
    expect(find.byType(MmPinCard), findsNWidgets(2));

    await t.tap(find.byTooltip('Edit pins'));
    await t.pump();
    await t.tap(find.byKey(ValueKey<String>('pin-remove-${MmPinIds.sos}')));
    await t.pump();

    expect(find.byType(MmPinCard), findsOneWidget);
    expect(pins.contains(MmPinIds.sos), isFalse);

    final DashboardPinsController reloaded = DashboardPinsController();
    await reloaded.load();
    expect(reloaded.pins, <String>[MmPinIds.places]);
  });

  testWidgets('move down reorders, and the first card cannot move up',
      (WidgetTester t) async {
    final DashboardPinsController pins =
        await _pins(<String>[MmPinIds.sos, MmPinIds.places]);
    await t.pumpWidget(_host(tc: ThemeController(), pins: pins));
    await t.tap(find.byTooltip('Edit pins'));
    await t.pump();

    final IconButton up = t.widget<IconButton>(
        find.byKey(ValueKey<String>('pin-up-${MmPinIds.sos}')));
    expect(up.onPressed, isNull, reason: 'the first card has nowhere to go');

    await t.tap(find.byKey(ValueKey<String>('pin-down-${MmPinIds.sos}')));
    await t.pump();
    expect(pins.pins, <String>[MmPinIds.places, MmPinIds.sos]);
  });

  testWidgets('a card expands in place and offers its tap-through',
      (WidgetTester t) async {
    final DashboardPinsController pins = await _pins(<String>[MmPinIds.sos]);
    await t.pumpWidget(_host(tc: ThemeController(), pins: pins));
    expect(find.text('Open SOS'), findsNothing);

    await t.tap(find.byType(MmPinCard));
    await t.pump();
    expect(pins.isOpen(MmPinIds.sos), isTrue);
    expect(find.text('Open SOS'), findsOneWidget);
  });

  testWidgets('every skin renders the pinned section', (WidgetTester t) async {
    // One controller set for the whole loop: seven fresh sets would cost more
    // time than the assertion is worth and the loop is about paint, not state.
    final DashboardPinsController pins = await _pins(<String>[
      MmPinIds.sos,
      MmPinIds.activity,
      MmPinIds.places,
      MmPinIds.coverage,
    ]);
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    final CoverageSession coverage = CoverageSession(mc: mc);
    final ThemeController theme = ThemeController();
    for (final MmThemePreset preset in MmThemePreset.values) {
      await t.pumpWidget(_host(
        tc: theme..setPreset(preset),
        pins: pins,
        mc: mc,
        coverage: coverage,
      ));
      await t.pump();
      expect(t.takeException(), isNull, reason: preset.name);
      expect(find.byType(MmPinCard), findsNWidgets(4), reason: preset.name);
    }
  });
}
