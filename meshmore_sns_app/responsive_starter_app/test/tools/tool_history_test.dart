// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/meshcore/secure/sealed_document.dart';
import 'package:meshmore_sns_app/tools/mesh_tool.dart';
import 'package:meshmore_sns_app/tools/tool_history.dart';

/// The tools kept nothing, so a range test's rows left the app as a CSV the
/// reader had to paste somewhere before closing the screen. A finished run is
/// kept now, with two stated bounds, and the bounds are what these tests pin:
/// a history that silently grows without limit is a storage leak, and one that
/// silently drops a table is a lie about what was kept.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late MemoryRecordCipher cipher;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = Directory.systemTemp.createTempSync('mm_tool_history');
    cipher = MemoryRecordCipher.random();
    SealedDocument.cipherOverride = cipher;
    SealedDocument.directoryOverride = dir;
  });

  tearDown(() {
    SealedDocument.cipherOverride = null;
    SealedDocument.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  ToolRun run({
    ToolKind kind = ToolKind.range,
    int minute = 0,
    String summary = '3 beacons heard',
    String? csv = 'seq,snr_db\n1,4\n',
    ToolFailure? failure,
  }) =>
      ToolRun(
        kind: kind,
        startedAt: DateTime.utc(2026, 11, 15, 12, minute),
        endedAt: DateTime.utc(2026, 11, 15, 12, minute, 30),
        summary: summary,
        csv: csv,
        failure: failure,
      );

  test('a run survives a relaunch, newest first', () async {
    final ToolHistoryStore first = ToolHistoryStore();
    await first.load();
    await first.record(run(minute: 1, summary: 'first'));
    await first.record(run(minute: 2, summary: 'second'));

    // A second store over the same sealed record is the next launch.
    final ToolHistoryStore second = ToolHistoryStore();
    await second.load();
    expect(second.runs.map((ToolRun r) => r.summary),
        <String>['second', 'first']);
    expect(second.runs.first.csv, isNotNull);
  });

  test('the run count is bounded, oldest dropped first', () async {
    final ToolHistoryStore store = ToolHistoryStore(maxRuns: 3);
    await store.load();
    for (int i = 0; i < 5; i++) {
      await store.record(run(minute: i, summary: 'run $i'));
    }
    expect(store.runs.length, 3);
    expect(store.runs.map((ToolRun r) => r.summary),
        <String>['run 4', 'run 3', 'run 2']);
  });

  test('the CSV budget drops tables from the oldest end, never the summary',
      () async {
    // Three runs of 100 bytes each against a 150-byte budget: the newest table
    // fits, the older two lose theirs, and every summary stays.
    final String table = 'x' * 100;
    final ToolHistoryStore store = ToolHistoryStore(maxCsvBytes: 150);
    await store.load();
    for (int i = 0; i < 3; i++) {
      await store.record(run(minute: i, summary: 'run $i', csv: table));
    }
    expect(store.runs.length, 3);
    expect(store.runs.first.csv, isNotNull,
        reason: 'the newest table is the one a reader is most likely to want');
    expect(store.runs[1].csv, isNull);
    expect(store.runs[2].csv, isNull);
    expect(store.runs.map((ToolRun r) => r.summary),
        <String>['run 2', 'run 1', 'run 0']);
    expect(store.csvBytes, lessThanOrEqualTo(150));
  });

  test('a failure is kept with the run, so a short run says why', () async {
    final ToolHistoryStore store = ToolHistoryStore();
    await store.load();
    await store.record(run(failure: ToolFailure.notConnected));
    expect(store.runs.single.failure, ToolFailure.notConnected);
  });

  test('clearing empties the store and the next launch agrees', () async {
    final ToolHistoryStore store = ToolHistoryStore();
    await store.load();
    await store.record(run());
    await store.clear();
    expect(store.runs, isEmpty);

    final ToolHistoryStore next = ToolHistoryStore();
    await next.load();
    expect(next.runs, isEmpty);
  });

  test('a document this build cannot read is reported, not read as empty',
      () async {
    // A row from a later version: an unknown kind. It is skipped, and the
    // history still loads the rows it does understand.
    await SealedDocument.write(
      ToolHistoryStore.recordName,
      '[{"kind":"teleport","started":1,"ended":2,"summary":"x"}]',
    );
    final ToolHistoryStore store = ToolHistoryStore();
    await store.load();
    expect(store.runs, isEmpty);
    expect(store.sealedUnreadable, isFalse,
        reason: 'a row it cannot read is not a document it cannot open');
  });

  test('a corrupt document reads as unreadable rather than as no runs',
      () async {
    await SealedDocument.write(ToolHistoryStore.recordName, 'not json');
    final ToolHistoryStore store = ToolHistoryStore();
    await store.load();
    expect(store.runs, isEmpty);
    expect(store.sealedUnreadable, isTrue);
  });
}
