// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/field/gpx_export_action.dart';
import 'package:meshmore_sns_app/field/position_history.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/own_location.dart';
import 'package:meshmore_sns_app/util/share.dart';

/// The trail export is only an export if it leaves through the share seam and
/// the file it hands over is a GPX a mapping app can read. Both halves are
/// pinned here: an action that writes a private path is the defect this
/// replaces.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> calls = <MethodCall>[];
  DateTime now = DateTime.utc(2026, 11, 5, 12);
  late Directory tmp;


  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    calls.clear();
    now = DateTime.utc(2026, 11, 5, 12);
    tmp = Directory.systemTemp.createTempSync('gpx-export-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Share.channel,
            (MethodCall call) async {
      calls.add(call);
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Share.channel, null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  PositionRecorder recorder({bool withTrail = true}) {
    final PositionRecorder r = PositionRecorder(
      persist: false,
      autoTick: false,
      clock: () => now,
    );
    if (!withTrail) return r;
    r.record(const OwnLocation(
      latitude: 38.9200,
      longitude: -104.7732,
      source: OwnLocationSource.deviceReported,
      altitudeMeters: 2012.5,
    ));
    now = now.add(const Duration(minutes: 2));
    r.record(const OwnLocation(
      latitude: 38.9240,
      longitude: -104.7700,
      source: OwnLocationSource.deviceReported,
    ));
    return r;
  }

  Widget host(PositionRecorder r) => ChangeNotifierProvider<PositionRecorder>.value(
        value: r,
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
            body: Builder(
              builder: (BuildContext context) => Center(
                child: TrailGpxAction(clock: () => now, directory: tmp),
              ),
            ),
          ),
        ),
      );

  testWidgets('the trail leaves as a GPX through the share seam',
      (WidgetTester t) async {
    await t.pumpWidget(host(recorder()));
    // The export writes a real file, and a fake-async harness does not advance
    // real IO on its own, so the tap and the wait both run in the real zone.
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey<String>('gpx-export')));
      // Poll for the share call instead of sleeping a fixed 200 ms: the file
      // write is real IO, and a loaded machine can outrun a guessed delay.
      final Stopwatch sw = Stopwatch()..start();
      while (calls.isEmpty && sw.elapsed < const Duration(seconds: 10)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await t.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'shareFile');
    final Map<Object?, Object?> args =
        calls.single.arguments as Map<Object?, Object?>;
    expect(args['mime'], 'application/gpx+xml');
    final String path = args['path']! as String;
    expect(path, endsWith('.gpx'));

    final File file = File(path);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    expect(file.existsSync(), isTrue);
    final String body = file.readAsStringSync();
    // Written in the clear, one track with one segment, and one point per
    // sample: the shape a mapping app expects.
    expect(body, contains('<gpx version="1.1"'));
    expect(body, contains('<trkseg>'));
    expect('<trkpt'.allMatches(body).length, 2);
    expect(body, contains('lat="38.920000"'));
    // The altitude only appears where the source had one.
    expect('<ele>'.allMatches(body).length, 1);
  });

  testWidgets('an empty trail is refused, not shared as an empty file',
      (WidgetTester t) async {
    await t.pumpWidget(host(recorder(withTrail: false)));
    await t.tap(find.byKey(const ValueKey<String>('gpx-export')));
    await t.pumpAndSettle();

    expect(calls, isEmpty);
    expect(find.textContaining('No trail recorded yet'), findsOneWidget);
  });
}
