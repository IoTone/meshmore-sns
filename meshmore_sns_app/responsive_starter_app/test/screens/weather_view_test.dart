// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/weather_view.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

Widget _host(MeshcoreController mc) => ChangeNotifierProvider<MeshcoreController>.value(
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
        home: const Scaffold(body: WeatherView()),
      ),
    );

void main() {
  testWidgets('W2 the weather view takes its text sizes from the ladder',
      (WidgetTester t) async {
    // The migration replaced the section headers (11 -> sizeSm), the summary
    // statistics (22 -> size(22), no role) and the microclimate bubble's label
    // and detail. The empty state is the shared GridNotice now: one sentence
    // at sizeBody and one smaller line naming which of the two causes it is.
    // Only the no-telemetry state renders without a sensor frame, so those are
    // what is asserted here.
    final MmType type = mmSkinFor(MmThemePreset.seele).type;
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    addTearDown(mc.dispose);
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_host(mc));
    await t.pump();

    Text header = t.widget<Text>(find.text('MEASURED (sensors)'));
    expect(header.style?.fontSize, type.sizeSm);
    expect(header.style?.fontSize, 11);

    Text empty = t.widget<Text>(find.text(
        'No nodes are reporting environment data yet.'));
    expect(empty.style?.fontSize, type.sizeBody);
    Text diag =
        t.widget<Text>(find.textContaining('has not answered a telemetry'));
    expect(diag.style?.fontSize, type.sizeSm);
    // The empty state carries the action that fixes it.
    expect(find.text('Turn on node telemetry'), findsOneWidget);

    await t.pumpWidget(const SizedBox());
  });
}
