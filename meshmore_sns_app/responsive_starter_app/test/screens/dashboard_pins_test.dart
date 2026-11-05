// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/chat/channel_read_store.dart';
import 'package:meshmore_sns_app/field/position_history.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/coverage_screen.dart';
import 'package:meshmore_sns_app/screens/dashboards/pinned_cards_section.dart';
import 'package:meshmore_sns_app/sos/sos_controller.dart';
import 'package:meshmore_sns_app/telemetry/coverage_session.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/dashboard_pins_controller.dart';
import 'package:meshmore_sns_app/ui/mm_pin_card.dart';
import 'package:meshmore_sns_app/ui/pin_blocks.dart';

import '../meshcore/fake_transport.dart';

/// A screen with a pinnable block above the dashboard's pinned section, so a
/// test can prove there is one render site: the block is either on its own
/// screen or on the dashboard, never both and never neither.
Widget _host({
  required ThemeController tc,
  required DashboardPinsController pins,
  required MeshcoreController mc,
  required CoverageSession coverage,
}) {
  return MultiProvider(
    providers: <SingleChildWidget>[
      ChangeNotifierProvider<ThemeController>.value(value: tc),
      ChangeNotifierProvider<DashboardPinsController?>.value(value: pins),
      ChangeNotifierProvider<MeshcoreController>.value(value: mc),
      ChangeNotifierProvider<SosController>.value(
          value: SosController(mc: mc, autoTick: false)),
      ChangeNotifierProvider<CoverageSession>.value(value: coverage),
      ChangeNotifierProvider<PlaceStore>.value(value: PlaceStore()),
      ChangeNotifierProvider<PositionRecorder>.value(value: PositionRecorder()),
      ChangeNotifierProvider<ChannelReadStore?>.value(
          value: ChannelReadStore()),
      ChangeNotifierProvider<BlockStore>.value(value: BlockStore()),
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
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                PinnableBlockHost(
                  key: const ValueKey<String>('origin'),
                  pinId: PinBlocks.coverageSummary,
                  child: CoverageSummaryBlock(
                    key: const ValueKey<String>('origin-block'),
                    header: PinnableBlockHeader(
                      pinId: PinBlocks.coverageSummary,
                      title: 'Coverage',
                    ),
                  ),
                ),
                const PinnedCardsSection(),
              ],
            ),
          ),
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

  testWidgets('nothing pinned renders no cards and leaves the block in place',
      (WidgetTester t) async {
    final DashboardPinsController pins = await _pins(<String>[]);
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(
      tc: ThemeController(),
      pins: pins,
      mc: mc,
      coverage: CoverageSession(mc: mc)..start(),
    ));
    expect(find.byType(MmPinCard), findsNothing);
    expect(find.byKey(const ValueKey<String>('origin-block')), findsOneWidget);
  });

  testWidgets(
      'pinning moves the block: the origin has no block and no hole, '
      'and the dashboard has the only one', (WidgetTester t) async {
    final DashboardPinsController pins =
        await _pins(<String>[PinBlocks.coverageSummary]);
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(
      tc: ThemeController(),
      pins: pins,
      mc: mc,
      coverage: CoverageSession(mc: mc)..start(),
    ));

    expect(find.byKey(const ValueKey<String>('origin-block')), findsNothing,
        reason: 'the block moved, so its screen renders without it');
    expect(find.byType(MmPinCard), findsOneWidget);
    expect(t.getSize(find.byKey(const ValueKey<String>('origin'))).height, 0,
        reason: 'no ghost row and no reserved space');
  });

  testWidgets('removing from the card puts the block back where it lives',
      (WidgetTester t) async {
    final DashboardPinsController pins =
        await _pins(<String>[PinBlocks.coverageSummary]);
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(
      tc: ThemeController(),
      pins: pins,
      mc: mc,
      coverage: CoverageSession(mc: mc)..start(),
    ));
    expect(find.byType(MmPinCard), findsOneWidget);

    await t.tap(find.byKey(const ValueKey<String>('pin-card-menu')));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove from dashboard'));
    await t.pumpAndSettle();

    expect(pins.isEmpty, isTrue);
    expect(find.byType(MmPinCard), findsNothing);
    expect(find.byKey(const ValueKey<String>('origin-block')), findsOneWidget);
  });

  testWidgets('two pinned blocks keep the order across a restart',
      (WidgetTester t) async {
    final DashboardPinsController pins =
        await _pins(<String>[PinBlocks.fieldExport, PinBlocks.coverageSummary]);
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    await t.pumpWidget(_host(
      tc: ThemeController(),
      pins: pins,
      mc: mc,
      coverage: CoverageSession(mc: mc)..start(),
    ));
    final List<String> keys = t
        .widgetList<MmPinCard>(find.byType(MmPinCard))
        .map((MmPinCard c) => (c.key! as ValueKey<String>).value)
        .toList();
    expect(keys, <String>[
      'pin-card-${PinBlocks.fieldExport}',
      'pin-card-${PinBlocks.coverageSummary}',
    ]);

    final DashboardPinsController reloaded = DashboardPinsController();
    await reloaded.load();
    expect(reloaded.pins,
        <String>[PinBlocks.fieldExport, PinBlocks.coverageSummary]);
  });

  testWidgets('the pinned section renders in all seven skins',
      (WidgetTester t) async {
    final DashboardPinsController pins =
        await _pins(<String>[PinBlocks.coverageSummary]);
    final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => FakeMeshcoreTransport());
    final CoverageSession coverage = CoverageSession(mc: mc)..start();
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
      expect(find.byType(MmPinCard), findsOneWidget, reason: preset.name);
    }
  });
}
