// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:meshmore_sns_app/bot/bot_controller.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/gen/app_localizations_en.dart';
import 'package:meshmore_sns_app/gen/app_localizations_ja.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/own_location.dart';
import 'package:meshmore_sns_app/screens/diagnostics_screen.dart';
import 'package:meshmore_sns_app/tools/tools_controller.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

/// R69 — strings that used to be hard-coded English must resolve to
/// Japanese. Units and acronyms that are the same in every language.
const Set<String> _allowed = <String>{
  'MHz',
  'kHz',
  'dBm',
  'PSK',
  'GPS',
  'SF',
  'CR',
  'CHG',
  'XYZ'
};

/// Latin-letter runs of 2+ letters left in [s] after removing the
/// allow-list. A digit stands in for substituted placeholders.
List<String> _latinRuns(String s) => <String>[
      for (final RegExpMatch m in RegExp(r'[A-Za-z]{2,}').allMatches(s))
        if (!_allowed.contains(m.group(0))) m.group(0)!
    ];

void main() {
  final AppLocalizationsJa ja = AppLocalizationsJa();
  final AppLocalizationsEn en = AppLocalizationsEn();
  const String p = '1';

  final Map<String, (String, String)> pairs = <String, (String, String)>{
    'deviceManageChannels': (en.deviceManageChannels, ja.deviceManageChannels),
    'deviceActiveChannelSub': (
      en.deviceActiveChannelSub(p),
      ja.deviceActiveChannelSub(p)
    ),
    'devicePathHashMismatch': (
      en.devicePathHashMismatch(p, p),
      ja.devicePathHashMismatch(p, p)
    ),
    'locationSourceDevice': (en.locationSourceDevice, ja.locationSourceDevice),
    'locationSourcePhone': (en.locationSourcePhone, ja.locationSourcePhone),
    'locationSourceNone': (en.locationSourceNone, ja.locationSourceNone),
    'batteryChargingShort': (en.batteryChargingShort, ja.batteryChargingShort),
    'elevationSelfTelemetry': (
      en.elevationSelfTelemetry,
      ja.elevationSelfTelemetry
    ),
    'elevationSelfAlt': (en.elevationSelfAlt(p), ja.elevationSelfAlt(p)),
    'elevationSelfAltUnknown': (
      en.elevationSelfAltUnknown,
      ja.elevationSelfAltUnknown
    ),
    'elevationSelfTemp': (en.elevationSelfTemp(p), ja.elevationSelfTemp(p)),
    'elevationPolling': (en.elevationPolling, ja.elevationPolling),
    'elevationTapToUpdate': (en.elevationTapToUpdate, ja.elevationTapToUpdate),
    'nodesClearSearch': (en.nodesClearSearch, ja.nodesClearSearch),
    'settingsNotifDeniedPermanent': (
      en.settingsNotifDeniedPermanent,
      ja.settingsNotifDeniedPermanent
    ),
    'settingsNotifDeniedTransient': (
      en.settingsNotifDeniedTransient,
      ja.settingsNotifDeniedTransient
    ),
    'deviceAdvertPropagatesHint': (
      en.deviceAdvertPropagatesHint,
      ja.deviceAdvertPropagatesHint
    ),
    'diagnosticsSectionConnection': (
      en.diagnosticsSectionConnection,
      ja.diagnosticsSectionConnection
    ),
    'diagnosticsStateLine': (
      en.diagnosticsStateLine(p),
      ja.diagnosticsStateLine(p)
    ),
    'diagnosticsStateDisconnected': (
      en.diagnosticsStateDisconnected,
      ja.diagnosticsStateDisconnected
    ),
    'diagnosticsStateHandshaking': (
      en.diagnosticsStateHandshaking,
      ja.diagnosticsStateHandshaking
    ),
    'diagnosticsStateReady': (
      en.diagnosticsStateReady,
      ja.diagnosticsStateReady
    ),
    'diagnosticsStateReconnecting': (
      en.diagnosticsStateReconnecting,
      ja.diagnosticsStateReconnecting
    ),
    'diagnosticsStateFailed': (
      en.diagnosticsStateFailed,
      ja.diagnosticsStateFailed
    ),
    'diagnosticsConnectingSuffix': (
      en.diagnosticsConnectingSuffix,
      ja.diagnosticsConnectingSuffix
    ),
    'diagnosticsDeviceLine': (
      en.diagnosticsDeviceLine(p, p, p),
      ja.diagnosticsDeviceLine(p, p, p)
    ),
    'diagnosticsBatteryLine': (
      en.diagnosticsBatteryLine(p, p),
      ja.diagnosticsBatteryLine(p, p)
    ),
    'diagnosticsChargingSuffix': (
      en.diagnosticsChargingSuffix,
      ja.diagnosticsChargingSuffix
    ),
    'diagnosticsReconnectLine': (
      en.diagnosticsReconnectLine(p),
      ja.diagnosticsReconnectLine(p)
    ),
    'diagnosticsGaveUpSuffix': (
      en.diagnosticsGaveUpSuffix,
      ja.diagnosticsGaveUpSuffix
    ),
    'diagnosticsErrorLine': (
      en.diagnosticsErrorLine(p),
      ja.diagnosticsErrorLine(p)
    ),
    'actionConnect': (en.actionConnect, ja.actionConnect),
    'actionRetrySend': (en.actionRetrySend, ja.actionRetrySend),
    'diagnosticsForgetShort': (
      en.diagnosticsForgetShort,
      ja.diagnosticsForgetShort
    ),
    'diagnosticsPairedLine': (
      en.diagnosticsPairedLine(p),
      ja.diagnosticsPairedLine(p)
    ),
  };

  test('every previously-hard-coded string has Japanese with no stray English',
      () {
    for (final MapEntry<String, (String, String)> e in pairs.entries) {
      final (String enV, String jaV) = e.value;
      expect(jaV, isNot(enV), reason: '${e.key}: JA must differ from EN');
      expect(_latinRuns(jaV), isEmpty,
          reason: '${e.key} -> "$jaV" still has English words');
    }
  });

  test(
      'OwnLocation.localizedSourceLabel follows the locale; sourceLabel '
      'stays English for logs', () {
    const OwnLocation phone = OwnLocation(
        latitude: 1, longitude: 2, source: OwnLocationSource.phoneFix);
    expect(phone.sourceLabel, 'phone GPS');
    expect(phone.localizedSourceLabel(en), 'phone GPS');
    expect(phone.localizedSourceLabel(ja), ja.locationSourcePhone);
    expect(_latinRuns(phone.localizedSourceLabel(ja)), isEmpty);
  });

  testWidgets('Diagnostics renders the connection block in Japanese',
      (WidgetTester t) async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MultiProvider(
          providers: <SingleChildWidget>[
            ChangeNotifierProvider<MeshcoreController>.value(value: ctrl),
            ChangeNotifierProvider<BotController>(
                create: (_) => BotController()),
            // The radio-health block reads the stats tool, which the app
            // always provides on this screen.
            ChangeNotifierProvider<ToolsController>(
                create: (_) => ToolsController(ctrl)),
          ],
          child: const DiagnosticsScreen(),
        ),
      ),
    );
    expect(find.textContaining('状態: 切断'), findsOneWidget);
    // One word for one intent: the diagnostics button and the dashboard's
    // say the same thing, in the same case.
    // Japanese needs three words here and used to have one: 接続 is the
    // section header (a noun), 接続する is the action, 接続済み is the state.
    // With one word the button read as the heading and the state read as the
    // action.
    expect(find.text(ja.actionConnect), findsOneWidget);
    expect(find.text(ja.diagnosticsSectionConnection), findsOneWidget);
    expect(find.textContaining('State:'), findsNothing);
    await t.pumpWidget(const SizedBox());
    ctrl.dispose();
  });
}
