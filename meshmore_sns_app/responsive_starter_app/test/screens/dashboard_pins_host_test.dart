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
import 'package:meshmore_sns_app/screens/dashboards/dashboard_host.dart';
import 'package:meshmore_sns_app/shell/shell_view_request.dart';
import 'package:meshmore_sns_app/sos/sos_controller.dart';
import 'package:meshmore_sns_app/telemetry/coverage_session.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/dashboard_pins_controller.dart';
import 'package:meshmore_sns_app/ui/mm_pin_card.dart';
import 'package:meshmore_sns_app/ui/pin_blocks.dart';

import '../meshcore/fake_transport.dart';

/// The owner's request is a feature, so it exists in every skin or the app has
/// a skin-dependent capability. This builds the real host under all seven
/// presets with one pin and asserts the card is there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('a pinned card appears on every skin\'s dashboard',
      (WidgetTester t) async {
    for (final MmThemePreset preset in MmThemePreset.values) {
      final MeshcoreController mc = MeshcoreController(
          transportFactory: () async => FakeMeshcoreTransport());
      final DashboardPinsController pins = DashboardPinsController();
      await pins.load();
      await pins.pin(PinBlocks.coverageSummary);

      await t.pumpWidget(
        MultiProvider(
          providers: <SingleChildWidget>[
            ChangeNotifierProvider<ThemeController>.value(
                value: ThemeController()..setPreset(preset)),
            ChangeNotifierProvider<DashboardPinsController?>.value(value: pins),
            ChangeNotifierProvider<MeshcoreController>.value(value: mc),
            ChangeNotifierProvider<SosController>.value(
                value: SosController(mc: mc, autoTick: false)),
            ChangeNotifierProvider<CoverageSession>.value(
                value: CoverageSession(mc: mc)..start()),
            ChangeNotifierProvider<PlaceStore>.value(value: PlaceStore()),
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
            home: const Scaffold(body: DashboardHost()),
          ),
        ),
      );
      await t.pump();
      expect(t.takeException(), isNull, reason: preset.name);
      expect(find.byType(MmPinCard), findsOneWidget, reason: preset.name);
    }
  });
}
