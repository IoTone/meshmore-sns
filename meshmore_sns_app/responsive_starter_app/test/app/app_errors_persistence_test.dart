// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/app/app_errors.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A periodic freeze used to leave nothing behind: the records were held in
/// memory, so the process died and took the only account of what had thrown with
/// it. These prove the account survives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppErrors.clear();
  });

  tearDown(AppErrors.clear);

  test('an error is written to the store, not only to memory', () async {
    AppErrors.record(StateError('the map layer would not parse'), null,
        where: 'framework');
    // The write is fire-and-forget, so the test waits for the store rather than
    // sleeping: a queued write that never lands is the bug this covers.
    await _settle();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString('mm.appErrors.v1') ?? '';
    expect(raw, contains('the map layer would not parse'));
    expect(raw, contains('framework'));
  });

  test('the previous run is readable at the next launch', () async {
    AppErrors.record(StateError('first'), null, where: 'boot');
    AppErrors.record(StateError('second'), null, where: 'async');
    await _settle();
    AppErrors.clear(); // the process dies; only the store remains

    await AppErrors.loadPrevious();
    expect(AppErrors.previous.map((AppErrorRecord r) => r.message),
        <String>['Bad state: first', 'Bad state: second']);
    expect(AppErrors.previous.map((AppErrorRecord r) => r.where),
        <String>['boot', 'async']);
    expect(AppErrors.records, isEmpty,
        reason: 'this run has not thrown yet');
  });

  test('the records keep the time they happened', () async {
    final DateTime before = DateTime.now().subtract(const Duration(seconds: 1));
    AppErrors.record(StateError('timed'), null);
    await _settle();
    AppErrors.clear();
    await AppErrors.loadPrevious();
    final DateTime at = AppErrors.previous.single.at;
    expect(at.isAfter(before), isTrue);
    expect(at.isBefore(DateTime.now().add(const Duration(seconds: 1))), isTrue);
  });

  test('a malformed file is dropped rather than thrown at launch', () async {
    // The file exists to explain a failure, so it must not become one.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mm.appErrors.v1': '{not json',
    });
    await AppErrors.loadPrevious();
    expect(AppErrors.previous, isEmpty);
  });

  test('rows that are the wrong shape are skipped, the rest kept', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mm.appErrors.v1': jsonEncode(<Object?>[
        <String, Object?>{'where': 'framework', 'message': 'kept', 'at': '2026-11-13T10:00:00.000'},
        <String, Object?>{'where': 7, 'message': 'bad where', 'at': '2026-11-13T10:00:00.000'},
        <String, Object?>{'where': 'async', 'message': 'bad time', 'at': 'yesterday'},
        'not a map',
      ]),
    });
    await AppErrors.loadPrevious();
    expect(AppErrors.previous.map((AppErrorRecord r) => r.message),
        <String>['kept']);
  });

  test('the list stays at its capacity and keeps the newest', () async {
    for (int i = 0; i < AppErrors.capacity + 5; i++) {
      AppErrors.record(StateError('e$i'), null);
    }
    expect(AppErrors.records.length, AppErrors.capacity);
    expect(AppErrors.records.last.message, contains('e${AppErrors.capacity + 4}'));
    expect(AppErrors.records.first.message, contains('e5'));
  });
}

/// Wait for the fire-and-forget write, by awaiting the write itself.
Future<void> _settle() async {
  await AppErrors.pendingWrite;
  await Future<void>.delayed(Duration.zero);
}
