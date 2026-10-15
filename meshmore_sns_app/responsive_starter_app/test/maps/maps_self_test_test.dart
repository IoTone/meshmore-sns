// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/maps_self_test.dart';
import 'package:meshmore_sns_app/screens/maps/maps_self_test_screen.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

const String _geo = '{"type":"FeatureCollection","features":[{"type":"Feature",'
    '"properties":{},"geometry":{"type":"LineString",'
    '"coordinates":[[-119.2,40.78],[-119.21,40.79]]}}]}';

/// A well-behaved server: PNG tiles with ETags, 304s when asked.
Future<FetchResult> _goodServer(Uri u,
    {String? etag, int? ifModifiedSinceMs}) async {
  if (u.path.endsWith('.geojson')) {
    return FetchResult(FetchStatus.ok,
        bytes: Uint8List.fromList(utf8.encode(_geo)));
  }
  if (etag != null) {
    return FetchResult(FetchStatus.notModified, etag: etag);
  }
  final Uint8List png = Uint8List(2000)
    ..setAll(0, <int>[0x89, 0x50, 0x4E, 0x47]);
  return FetchResult(FetchStatus.ok, bytes: png, etag: '"t"');
}

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = await Directory.systemTemp.createTemp('selftest');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('against a well-behaved server every check passes, and the '
      'sandbox is cleaned up', () async {
    final MapsSelfTest st = MapsSelfTest(
      sandbox: Directory('${dir.path}/sb'),
      fetcher: _goodServer,
      retryFloor: const Duration(seconds: 1),
    );
    await st.run();
    expect(st.report(), contains('RESULT: PASS'), reason: st.report());
    expect(st.passed, isTrue);
    expect(st.pointLabel, startsWith('Black Rock City'));
    expect(Directory('${dir.path}/sb').existsSync(), isFalse);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('maps.selftest.v1'), isNull);
    // The user's own state key is never written.
    expect(prefs.getString('maps.state.v1'), isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('own location inside the US is used as the test point', () async {
    final MapsSelfTest st = MapsSelfTest(
      sandbox: Directory('${dir.path}/sb'),
      fetcher: _goodServer,
      retryFloor: const Duration(seconds: 1),
      lat: 37.77,
      lon: -122.42,
    );
    await st.run();
    expect(st.pointLabel, 'own location');
    expect(st.passed, isTrue, reason: st.report());
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('no network: fails loudly, never hangs', () async {
    final MapsSelfTest st = MapsSelfTest(
      sandbox: Directory('${dir.path}/sb'),
      fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs}) async =>
          const FetchResult(FetchStatus.failed),
      retryFloor: const Duration(seconds: 1),
    );
    await st.run();
    expect(st.passed, isFalse);
    expect(st.checks[SelfCheckId.reach.index].state, CheckState.fail);
    expect(st.checks[SelfCheckId.pack.index].detail, contains('offline'));
    expect(st.report(), contains('RESULT: FAIL'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a server that ignores ETags still passes, and says so', () async {
    final MapsSelfTest st = MapsSelfTest(
      sandbox: Directory('${dir.path}/sb'),
      fetcher: (Uri u, {String? etag, int? ifModifiedSinceMs}) =>
          _goodServer(u),
      retryFloor: const Duration(seconds: 1),
    );
    await st.run();
    expect(st.checks[SelfCheckId.revalidate.index].detail,
        contains('server ignored ETag'));
    expect(st.passed, isTrue, reason: st.report());
  }, timeout: const Timeout(Duration(minutes: 2)));

  for (final Locale loc in const <Locale>[Locale('en'), Locale('ja')]) {
    testWidgets('screen lists every check and the result '
        '(${loc.languageCode})', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      late final MapsSelfTest st;
      await t.runAsync(() async {
        st = MapsSelfTest(
          sandbox: Directory('${dir.path}/sb'),
          fetcher: _goodServer,
          retryFloor: const Duration(seconds: 1),
        );
        await st.run();
      });
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>(
              create: (_) => ThemeController()),
        ],
        child: MaterialApp(
          locale: loc,
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: MapsSelfTestScreen(test: st),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      if (loc.languageCode == 'en') {
        expect(find.text('All checks passed'), findsOneWidget);
        expect(find.text('Copy report'), findsOneWidget);
        expect(find.text('Map servers reachable'), findsOneWidget);
      }
      expect(find.byIcon(Icons.check_circle), findsWidgets);
      expect(find.byIcon(Icons.cancel), findsNothing);
    });
  }
}
