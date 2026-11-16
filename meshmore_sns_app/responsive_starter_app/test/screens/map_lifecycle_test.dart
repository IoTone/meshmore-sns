// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/map_screen.dart';

import '../meshcore/fake_transport.dart';

/// What the map leaves behind when the reader leaves it.
///
/// The owner reports the app periodically stops responding, and the map is the
/// screen that is opened and left most often. Two things outlived it:
///
///  * `MapController` was never disposed. flutter_map's implementation owns a
///    broadcast `StreamController` and an `AnimationController`
///    (`MapControllerImpl.dispose`, flutter_map 7.0.2), and a live
///    `AnimationController` is a ticker that keeps asking for frames.
///  * The warm-up loop and the three debounce timers had to be cancelled, which
///    they were — this file holds that too, so a future edit cannot quietly
///    drop one.
class _Net {
  Future<FetchResult> call(Uri url,
          {String? etag, int? ifModifiedSinceMs, int? maxBytes}) async =>
      FetchResult(FetchStatus.ok,
          bytes: Uint8List(1000), maxAge: const Duration(hours: 1));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('meshmore/compass'), (MethodCall c) async => null);
  });

  Future<MeshcoreController> pump(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    late final Directory dir;
    late final MapsController maps;
    await t.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('maplife');
      maps = MapsController(
        rootDir: () async => dir,
        fetcher: _Net().call,
        prefsKey: 'maps.life.test.v1',
        pace: Duration.zero,
      );
      await maps.load();
    });
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    addTearDown(mc.dispose);
    await t.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<MapsController>.value(value: maps),
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<PlaceStore>.value(value: PlaceStore()),
          Provider<PlaceReportBudget>(
              create: (_) => PlaceReportBudget(clock: DateTime.now)),
        ],
        child: const Scaffold(body: MapScreen()),
      ),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    return mc;
  }

  testWidgets('leaving the map closes the controller it owns',
      (WidgetTester t) async {
    await pump(t);
    final FlutterMap map = t.widget<FlutterMap>(find.byType(FlutterMap));
    final MapController controller = map.mapController!;

    // The screen goes away, which is what a tab switch or a theme change does.
    // The long pump is for the binding, not the assertion: the controller's own
    // retry and pace timers are still winding down, and a pending timer fails
    // the test at teardown rather than here.
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));

    // A closed broadcast stream completes a new listener immediately. An
    // undisposed controller keeps the stream open for the life of the process.
    final Completer<void> closed = Completer<void>();
    controller.mapEventStream.listen((MapEvent _) {}, onDone: closed.complete);
    await t.pump();
    expect(closed.isCompleted, isTrue,
        reason: 'the map controller outlived the screen that owned it');
  });

  testWidgets('leaving the map leaves no ticker asking for frames',
      (WidgetTester t) async {
    await pump(t);
    // A live AnimationController — the one inside MapController — registers a
    // transient frame callback. Zero here means nothing is still animating.
    await t.pumpWidget(const SizedBox());
    await t.pump();
    expect(t.binding.transientCallbackCount, 0,
        reason: 'something is still scheduling frames after the map is gone');
  });

  testWidgets('leaving the map leaves no pending timer', (WidgetTester t) async {
    // The three debounces (view save, warm-up, bubble tick) are cancelled in
    // dispose. A pending timer fails the test binding at teardown, so this case
    // is the assertion: it pumps past every window and then tears down.
    await pump(t);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
    expect(t.takeException(), isNull);
  });
}
