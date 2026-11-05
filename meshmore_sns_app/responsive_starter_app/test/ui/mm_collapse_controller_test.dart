// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/ui/mm_collapse_controller.dart';
import 'package:meshmore_sns_app/ui/mm_collapsible.dart';

const Set<String> _known = <String>{'a', 'b'};

Widget _host(MmCollapseController c,
        {String id = 'a', String title = 'Group'}) =>
    ChangeNotifierProvider<MmCollapseController>.value(
      value: c,
      child: MaterialApp(
        home: Scaffold(
          body: MmCollapsibleSection(
            id: id,
            title: title,
            children: const <Widget>[Text('inside')],
          ),
        ),
      ),
    );

Future<MmCollapseController> _fresh() async {
  final MmCollapseController c = MmCollapseController(known: _known);
  await c.load();
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets(
      'a folded group is still folded after a remount and a '
      'reload from prefs', (WidgetTester t) async {
    MmCollapseController c = await _fresh();
    await t.pumpWidget(_host(c));
    expect(find.text('inside'), findsOneWidget, reason: 'default open');

    await t.tap(find.text('GROUP'));
    await t.pump();
    expect(find.text('inside'), findsNothing);

    // Leave the screen, drop the controller, rebuild from prefs alone.
    await t.pumpWidget(const SizedBox());
    c = await _fresh();
    await t.pumpWidget(_host(c));
    expect(find.text('inside'), findsNothing,
        reason: 'persisted closed, on the very first frame');
  });

  testWidgets('two ids are independent', (WidgetTester t) async {
    final MmCollapseController c = await _fresh();
    await c.setOpen('a', false);
    expect(c.isOpen('a'), isFalse);
    expect(c.isOpen('b'), isTrue);
    await t.pumpWidget(_host(c, id: 'b'));
    expect(find.text('inside'), findsOneWidget);
  });

  test('default is open when nothing is stored', () async {
    final MmCollapseController c = await _fresh();
    expect(c.isOpen('a'), isTrue);
    expect(
        (await SharedPreferences.getInstance())
            .getString(MmCollapseController.prefsKey),
        isNull,
        reason: 'a fresh install stores nothing');
  });

  test('corrupt, non-object, unknown and non-bool values fall back', () {
    expect(MmCollapseController.decode('{not json', _known), isEmpty);
    expect(MmCollapseController.decode('[1,2]', _known), isEmpty);
    expect(MmCollapseController.decode('', _known), isEmpty);
    expect(
        MmCollapseController.decode(
            '{"a":false,"b":"no","gone":false}', _known),
        <String, bool>{'a': false},
        reason: 'unknown id dropped, non-bool ignored, valid kept');
  });

  test('a removed id is pruned from storage on the next write', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MmCollapseController.prefsKey: '{"gone":false,"a":false}',
    });
    final MmCollapseController c = await _fresh();
    await c.setOpen('b', false);
    final String raw = (await SharedPreferences.getInstance())
        .getString(MmCollapseController.prefsKey)!;
    expect(raw.contains('gone'), isFalse);
    expect(raw.contains('"a":false'), isTrue);
  });

  testWidgets('the id, not the localised title, is the key',
      (WidgetTester t) async {
    final MmCollapseController c = await _fresh();
    await t.pumpWidget(_host(c, title: 'Group'));
    await t.tap(find.text('GROUP'));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(_host(c, title: '\u30b0\u30eb\u30fc\u30d7'));
    expect(find.text('inside'), findsNothing,
        reason: 'same id, different (Japanese) title: same state');
  });

  testWidgets('the onChanged callback still fires', (WidgetTester t) async {
    final MmCollapseController c = await _fresh();
    final List<bool> seen = <bool>[];
    await t.pumpWidget(ChangeNotifierProvider<MmCollapseController>.value(
      value: c,
      child: MaterialApp(
        home: Scaffold(
          body: MmCollapsibleSection(
            id: 'a',
            title: 'G',
            onChanged: seen.add,
            children: const <Widget>[Text('x')],
          ),
        ),
      ),
    ));
    await t.tap(find.text('G'));
    await t.pump();
    expect(seen, <bool>[false]);
  });

  testWidgets('a duplicate id on screen is caught in debug',
      (WidgetTester t) async {
    final MmCollapseController c = await _fresh();
    final List<String> errors = <String>[];
    final void Function(FlutterErrorDetails)? old = FlutterError.onError;
    FlutterError.onError =
        (FlutterErrorDetails d) => errors.add(d.exceptionAsString());
    addTearDown(() => FlutterError.onError = old);
    await t.pumpWidget(ChangeNotifierProvider<MmCollapseController>.value(
      value: c,
      child: MaterialApp(
        home: Scaffold(
          body: Column(children: const <Widget>[
            MmCollapsibleSection(id: 'a', title: 'One', children: <Widget>[]),
            MmCollapsibleSection(id: 'a', title: 'Two', children: <Widget>[]),
          ]),
        ),
      ),
    ));
    expect(
        errors.any((String e) => e.contains('duplicate MmCollapsibleSection')),
        isTrue);
    // A build-time throw cascades into layout errors; drain them.
    while (t.takeException() != null) {}
  });

  test(
      'every id a screen uses is registered, and every registered id is '
      'used', () {
    final RegExp use =
        RegExp(r'MmCollapsibleSection\(\s*id:\s*MmGroupIds\.(\w+)');
    final Set<String> used = <String>{};
    for (final FileSystemEntity f
        in Directory('lib').listSync(recursive: true)) {
      if (f is File &&
          f.path.endsWith('.dart') &&
          !f.path.endsWith('mm_collapsible.dart')) {
        for (final RegExpMatch m in use.allMatches(f.readAsStringSync())) {
          used.add(m.group(1)!);
        }
      }
    }
    final Map<String, String> byName = <String, String>{
      'locAutoPublish': MmGroupIds.locAutoPublish,
      'locBeacon': MmGroupIds.locBeacon,
      'locManual': MmGroupIds.locManual,
      'devRegion': MmGroupIds.devRegion,
      'devRadio': MmGroupIds.devRadio,
      'devIdentity': MmGroupIds.devIdentity,
      'devOther': MmGroupIds.devOther,
      'devDevice': MmGroupIds.devDevice,
      'persPreset': MmGroupIds.persPreset,
      'persAccessibility': MmGroupIds.persAccessibility,
      'persType': MmGroupIds.persType,
      'persAudio': MmGroupIds.persAudio,
      'dashRadio': MmGroupIds.dashRadio,
      'dashLocation': MmGroupIds.dashLocation,
      'dashRecent': MmGroupIds.dashRecent,
      'dashBattery': MmGroupIds.dashBattery,
    };
    expect(used, byName.keys.toSet(), reason: 'screens vs the id list');
    expect(byName.values.toSet(), MmGroupIds.all);
    expect(MmGroupIds.all, hasLength(byName.length), reason: 'no duplicates');
  });
}
