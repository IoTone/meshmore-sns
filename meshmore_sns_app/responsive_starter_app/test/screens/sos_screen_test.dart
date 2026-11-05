// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/sos_screen.dart';
import 'package:meshmore_sns_app/sos/sos_controller.dart';
import 'package:meshmore_sns_app/sos/sos_engine.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:provider/provider.dart';

import '../meshcore/fake_transport.dart';

class _Clock {
  DateTime now = DateTime.utc(2026, 11, 5, 12);
  DateTime call() => now;
}

/// A radio that has answered with a name, which an alarm needs to carry.
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
        home: const SosScreen(),
      ),
    );

/// The controller arms its own timers when a message goes out: a three-second
/// meshbook save and a fifteen-second delivery window. They are genuine pending
/// timers, so a widget test that ends before they fire trips the harness
/// invariant rather than the app; draining fake time past both leaves the
/// test's own assertions untouched.
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
      // §10 item 1: what repeats, before anything is armed.
      expect(find.text('This repeats for up to one hour.'), findsOneWidget,
          reason: 'preset ${preset.name}');
      // §10 items 2 and 3: where it goes, and that nobody is notified.
      expect(find.textContaining('Channel '), findsOneWidget);
      expect(
          find.text('Nobody is notified unless they are in radio range.'),
          findsOneWidget);
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('releasing the hold early sends nothing and says so',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_host(mc, sos, tc));
    await t.pump();

    final Offset at = t.getCenter(find.byKey(const ValueKey<String>('sos-hold')));
    final TestGesture g = await t.startGesture(at);
    await t.pump(const Duration(seconds: 1));
    expect(sos.state, SosState.arming, reason: 'the hold is in progress');
    await g.up();
    await t.pump();

    expect(sos.state, SosState.idle);
    expect(find.text('Released too early — nothing was sent.'), findsOneWidget);
    expect(fake.sent.where((Uint8List f) => f.first == 0x03), isEmpty);
  });

  // A screen reader cannot press and hold, and the semantic action used to be
  // an empty closure: the alarm was reachable by finger only. This drives the
  // action a screen reader would, and expects the same alarm a finger raises.
  testWidgets('a screen reader can raise the alarm through the hold control',
      (WidgetTester t) async {
    final SemanticsHandle handle = t.ensureSemantics();
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_host(mc, sos, tc));
    await t.pump();

    final Finder hold = find.byKey(const ValueKey<String>('sos-hold'));
    final SemanticsNode node = t.getSemantics(hold);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
        reason: 'the control advertises an action a screen reader can perform');

    t.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, SemanticsAction.tap);
    await t.pump(const Duration(milliseconds: 150));
    expect(sos.state, SosState.arming,
        reason: 'the semantic action starts the same hold');

    clock.now = clock.now.add(SosEngine.hold);
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 2));
    expect(sos.state, SosState.active);
    expect(find.byKey(const ValueKey<String>('sos-active')), findsOneWidget);
    expect(fake.sent.where((Uint8List f) => f.first == 0x03), hasLength(1));

    handle.dispose();
    await _settle(t);
  });

  testWidgets('a held press raises the alarm, and the countdown is shown',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_host(mc, sos, tc));
    await t.pump();

    final Offset at = t.getCenter(find.byKey(const ValueKey<String>('sos-hold')));
    final TestGesture g = await t.startGesture(at);
    // The tap-down arrives after the recognizer's deadline, and that is when
    // the engine records the hold's start. The clock has to move after it, as
    // it would on a phone, or the engine would see the hold begin three
    // seconds late and refuse the confirm.
    await t.pump(const Duration(milliseconds: 150));
    expect(sos.state, SosState.arming);
    clock.now = clock.now.add(SosEngine.hold);
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 2));
    await g.up();
    await t.pump();

    expect(sos.state, SosState.active);
    // The pill is uppercased by the skin, so it is named by key, not by case.
    expect(find.byKey(const ValueKey<String>('sos-active')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sos-next')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sos-im-safe')), findsOneWidget);
    expect(fake.sent.where((Uint8List f) => f.first == 0x03), hasLength(1));
    await _settle(t);
  });

  testWidgets('cancelling mid-run stops the next send, and says nothing was sent',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    expect(sos.arm(words: 'trail washed out'), isNull);
    clock.now = clock.now.add(SosEngine.hold);
    expect(sos.confirm(), isNull);
    expect(fake.sent.where((Uint8List f) => f.first == 0x03), hasLength(1));

    await t.pumpWidget(_host(mc, sos, tc));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('sos-cancel')));
    await t.pump();

    expect(sos.state, SosState.cancelled);
    expect(find.byKey(const ValueKey<String>('sos-ended-pill')), findsOneWidget);
    // §8's `--cancel-->` says nothing on air: the second send at 60 s never
    // happens, whatever the clock does afterwards.
    final int sentBefore = fake.sent.where((Uint8List f) => f.first == 0x03).length;
    clock.now = clock.now.add(const Duration(seconds: 600));
    sos.pump();
    await t.pump();
    expect(fake.sent.where((Uint8List f) => f.first == 0x03),
        hasLength(sentBefore));
    await _settle(t);
  });

  testWidgets('a channel ACK reads as claimed and the alarm keeps running',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    expect(sos.arm(words: 'trail washed out'), isNull);
    clock.now = clock.now.add(SosEngine.hold);
    expect(sos.confirm(), isNull);

    sos.attributeInbound(
        'SEEN1: [ACK:${sos.request!.id}] W9XYZ on my way', direct: false);
    await t.pumpWidget(_host(mc, sos, tc));
    await t.pump();

    expect(find.byKey(const ValueKey<String>('sos-active')), findsOneWidget);
    expect(
        find.textContaining('claims to have seen this, on the channel'),
        findsOneWidget);
    expect(sos.state, SosState.active, reason: 'a claim stops nothing');
    await _settle(t);
  });

  testWidgets('a direct ACK from an addressed key reads as seen and stops it',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final List<int> key = List<int>.generate(32, (int i) => i);
    sos.setDestination(contactKeysHex: <String>[
      key.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(),
    ]);
    expect(sos.arm(words: 'trail washed out'), isNull);
    clock.now = clock.now.add(SosEngine.hold);
    expect(sos.confirm(), isNull);

    sos.attributeInbound('[ACK:${sos.request!.id}] W1TGT', direct: true, fromKey: key);
    await t.pumpWidget(_host(mc, sos, tc));
    await t.pump();

    expect(sos.state, SosState.acknowledged);
    expect(find.textContaining('has seen this, by direct message'),
        findsOneWidget);
    // §10 item 5's cousin: an ended alarm says it is over, not that help came.
    expect(find.textContaining('Help is on the way'), findsNothing);
    await _settle(t);
  });

  testWidgets('expiry says the alarm stopped repeating and is not resolved',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    expect(sos.arm(words: 'trail washed out'), isNull);
    clock.now = clock.now.add(SosEngine.hold);
    expect(sos.confirm(), isNull);
    clock.now = clock.now.add(const Duration(seconds: 3601));
    sos.pump();
    expect(sos.state, SosState.expired);

    await t.pumpWidget(_host(mc, sos, tc));
    await t.pump();
    expect(find.text('The alarm has stopped repeating. It is not resolved.'),
        findsOneWidget);
    await _settle(t);
  });
}
