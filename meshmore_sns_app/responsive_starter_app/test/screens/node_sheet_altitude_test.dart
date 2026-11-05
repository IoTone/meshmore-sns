// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

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
import 'package:meshcore/meshcore.dart';
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

NodeDetailSheet _sheet() => NodeDetailSheet(
      node: _node(),
      distanceMeters: null,
      isFavourite: false,
      isKnown: true,
      cameFromDm: false,
      onToggleFavourite: () {},
    );

/// One `0x8B` telemetry push carrying a temperature and no altitude.
///
/// Layout: opcode, one reserved byte, the six-byte pubkey prefix, then a
/// CayenneLPP payload of `channel, type, value…` entries. A sensor-only node
/// answers exactly like this, which is the case the row has to describe.
Uint8List _telemetryU8({double? altitudeMeters}) {
  final Uint8List pub6 =
      Uint8List.fromList(List<int>.generate(6, (int i) => 0xcd));
  final BytesBuilder lpp = BytesBuilder();
  // Temperature, channel 1: 0x67 with a signed 16-bit tenths-of-a-degree.
  lpp.add(<int>[1, 0x67, 0x00, 0xfa]); // 25.0 °C
  if (altitudeMeters != null) {
    // GPS, channel 2: 0x88 with lat/lon in ten-thousandths of a degree and
    // altitude in centimetres. Altitude is only ever carried here, which is
    // why a sensor node without a fix has none.
    final int lat = (39.5 * 10000).round();
    final int lon = (-105.0 * 10000).round();
    final int alt = (altitudeMeters * 100).round();
    lpp.add(<int>[
      2,
      0x88,
      (lat >> 16) & 0xff, (lat >> 8) & 0xff, lat & 0xff,
      (lon >> 16) & 0xff, (lon >> 8) & 0xff, lon & 0xff,
      (alt >> 16) & 0xff, (alt >> 8) & 0xff, alt & 0xff,
    ]);
  }
  return Uint8List.fromList(<int>[0x8b, 0x00, ...pub6, ...lpp.toBytes()]);
}

Widget _app(MeshcoreController mc, Widget home) {
  final ThemeController theme = ThemeController();
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

/// Builds the controller pair, delivers one telemetry push, then opens the
/// sheet so the section renders with a value already in place.
Future<MeshcoreController> _pumpWithTelemetry(
  WidgetTester t, {
  required Uint8List frame,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await t.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
  final MeshcoreController mc = MeshcoreController(
    transportFactory: () async => fake,
    connection: MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await mc.connect();
  fake.emit(frame);
  await t.pumpWidget(_app(mc, Scaffold(body: _sheet())));
  await t.pump();
  return mc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a sensor node with no fix says the altitude was not reported',
      (WidgetTester t) async {
    final MeshcoreController mc = await _pumpWithTelemetry(t, frame: _telemetryU8());

    expect(find.text('altitude'), findsOneWidget,
        reason: 'the row stays: "not asked yet" and "no fix" are different '
            'facts and the sheet has to carry the difference');
    expect(find.text('not reported'), findsOneWidget);
    expect(find.text('temperature'), findsOneWidget,
        reason: 'the rest of the telemetry still renders');
    mc.dispose();
    await t.pump();
  });

  testWidgets('an altitude that did arrive is shown in metres',
      (WidgetTester t) async {
    final MeshcoreController mc =
        await _pumpWithTelemetry(t, frame: _telemetryU8(altitudeMeters: 1609.0));

    expect(find.text('1609.0 m'), findsOneWidget);
    expect(find.text('not reported'), findsNothing);
    mc.dispose();
    await t.pump();
  });
}
