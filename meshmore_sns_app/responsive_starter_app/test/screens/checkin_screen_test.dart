// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/checkin_screen.dart';
import 'package:meshmore_sns_app/sos/checkin.dart';
import 'package:meshmore_sns_app/sos/sos_controller.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:provider/provider.dart';

import '../meshcore/fake_transport.dart';

class _Clock {
  DateTime now = DateTime.utc(2026, 11, 5, 12);
  DateTime call() => now;
}

/// A radio that has answered with a name, which a check-in carries.
Future<MeshcoreController> _ready(FakeMeshcoreTransport fake) async {
  final MeshcoreController mc = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await mc.connect();
  fake.emit(Uint8List.fromList(
      <int>[...selfInfoFrame(), ...utf8.encode('W1ABC')]));
  await Future<void>.delayed(Duration.zero);
  return mc;
}

Widget _host(MeshcoreController mc, SosController sos, ThemeController tc) =>
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<ThemeController>.value(value: tc),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<SosController>.value(value: sos),
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
        home: const CheckinScreen(),
      ),
    );

/// The controller arms its own timers when a message goes out; draining fake
/// time past them keeps the harness invariant about this test, not the app.
Future<void> _settle(WidgetTester t) async {
  await t.pump(const Duration(seconds: 16));
  await t.pump(const Duration(seconds: 1));
}

void main() {
  late FakeMeshcoreTransport fake;
  late MeshcoreController mc;
  late _Clock clock;
  late SosController sos;
  late ThemeController tc;

  setUp(() async {
    fake = FakeMeshcoreTransport(connected: true);
    mc = await _ready(fake);
    clock = _Clock();
    sos = SosController(mc: mc, clock: clock.call, autoTick: false)..start();
    tc = ThemeController();
  });

  tearDown(() {
    sos.dispose();
    mc.dispose();
  });

  testWidgets('the surface builds in all seven skins', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    for (final MmThemePreset preset in MmThemePreset.values) {
      await tc.setPreset(preset);
      await t.pumpWidget(_host(mc, sos, tc));
      await t.pump();
      expect(t.takeException(), isNull, reason: 'preset ${preset.name}');
      // D8.5: the three intervals, and the one-message promise.
      for (final int m in CheckinScreen.intervals) {
        expect(find.byKey(ValueKey<String>('checkin-interval-$m')),
            findsOneWidget,
            reason: 'preset ${preset.name}');
      }
      expect(find.text('A check-in is one message and does not repeat.'),
          findsOneWidget);
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('one send, and the deadline it was given', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_host(mc, sos, tc));
    await t.pump();

    await t.tap(find.byKey(const ValueKey<String>('checkin-interval-30')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('checkin-send')));
    await t.pump();

    final List<Uint8List> sends =
        fake.sent.where((Uint8List f) => f.first == 0x03).toList();
    expect(sends, hasLength(1), reason: 'a check-in never repeats');
    // `0x03 <channel slot> <text>`: the payload is the text after the two
    // header bytes, not the whole frame.
    expect(utf8.decode(sends.single.sublist(2), allowMalformed: true),
        contains('[CHK:'));
    expect(sos.checkin, isNotNull);
    expect(sos.checkin!.state, CheckinState.watching);
    expect(find.byKey(const ValueKey<String>('checkin-until')), findsOneWidget);
    // Nothing sends a second copy, however much time passes.
    clock.now = clock.now.add(const Duration(minutes: 20));
    sos.pump();
    await t.pump();
    expect(fake.sent.where((Uint8List f) => f.first == 0x03), hasLength(1));
    await _settle(t);
  });

  testWidgets('the deadline passing is overdue, not a failure',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await sos.sendCheckin(within: const Duration(minutes: 15));
    await t.pumpWidget(_host(mc, sos, tc));
    await t.pump();

    clock.now = clock.now.add(const Duration(minutes: 16));
    sos.pump();
    await t.pump();

    expect(sos.checkin!.state, CheckinState.overdue);
    expect(find.byKey(const ValueKey<String>('checkin-pill')), findsOneWidget);
    expect(
        find.text('Overdue — the deadline passed and no answer came back.'),
        findsOneWidget);
    await _settle(t);
  });

  testWidgets('an answer before the deadline closes the watch',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await sos.sendCheckin(within: const Duration(minutes: 15));
    final CheckinWatch watch = sos.checkin!;
    sos.attributeInbound('[SAFE:${watch.checkin.id}] W9XYZ on my way',
        direct: false);
    await t.pumpWidget(_host(mc, sos, tc));
    await t.pump();

    expect(watch.state, CheckinState.answered);
    expect(watch.answer, CheckinAnswer.claimedOnChannel,
        reason: 'a channel name is a claim, not a key');
    expect(find.text('Answered on the channel by name only, not by their key.'),
        findsOneWidget);
    await _settle(t);
  });
}
