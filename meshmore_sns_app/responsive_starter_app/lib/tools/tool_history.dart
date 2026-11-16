// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../meshcore/secure/sealed_document.dart';
import '../util/safe_notifier.dart';
import 'mesh_tool.dart';

/// One finished tool run, kept so the reader can compare it with the next one.
///
/// The tools used to keep nothing: a range test's rows lived in memory and left
/// the app as a CSV the reader had to paste somewhere before closing the screen.
/// So "was this repeater working last Tuesday" had no answer the app could give.
///
/// What is stored is the run's own one-line summary and the CSV it already
/// knows how to produce. Not the widget tree's rows: a run that is still open
/// has no answer yet, and a stored answer that changes after the fact cannot be
/// compared with anything.
class ToolRun {
  const ToolRun({
    required this.kind,
    required this.startedAt,
    required this.endedAt,
    required this.summary,
    this.csv,
    this.failure,
  });

  final ToolKind kind;
  final DateTime startedAt;
  final DateTime endedAt;

  /// What the run did, in one line, written by the tool that ran.
  final String summary;

  /// The run's CSV, or null when the tool has nothing tabular to say.
  final String? csv;

  /// Why it ended early, or null when it ran to the end.
  final ToolFailure? failure;

  /// Stable across processes, so a stored row can be found again.
  String get id => '${kind.name}-${startedAt.toUtc().millisecondsSinceEpoch}';

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'started': startedAt.toUtc().millisecondsSinceEpoch,
        'ended': endedAt.toUtc().millisecondsSinceEpoch,
        'summary': summary,
        if (csv != null) 'csv': csv,
        if (failure != null) 'failure': failure!.name,
      };

  /// Null for a row this build cannot read, which is skipped rather than
  /// thrown: a stored document written by a later version must not stop the
  /// history from loading.
  static ToolRun? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final ToolKind? kind = ToolKind.values.asNameMap()[raw['kind']];
    final int? started = raw['started'] as int?;
    final int? ended = raw['ended'] as int?;
    final Object? summary = raw['summary'];
    if (kind == null || started == null || ended == null || summary is! String) {
      return null;
    }
    return ToolRun(
      kind: kind,
      startedAt: DateTime.fromMillisecondsSinceEpoch(started, isUtc: true),
      endedAt: DateTime.fromMillisecondsSinceEpoch(ended, isUtc: true),
      summary: summary,
      csv: raw['csv'] is String ? raw['csv'] as String : null,
      failure: ToolFailure.values.asNameMap()[raw['failure']],
    );
  }
}

/// Every finished run, newest first, in the sealed store.
///
/// Two bounds, both stated on screen: [maxRuns] runs, and [maxCsvBytes] of CSV
/// across all of them. A run keeps its summary even when the CSV budget cannot
/// take it, because a summary is tens of bytes and the row that says what
/// happened is worth more than the table nobody copied.
///
/// A stored run is not location history and it is not a log of who said what:
/// it is what the reader's own tools reported while they watched. It is sealed
/// anyway, because a range test's rows carry the receiver's coordinates.
class ToolHistoryStore extends ChangeNotifier with SafeNotifier {
  ToolHistoryStore({this.maxRuns = 40, this.maxCsvBytes = 96 * 1024});

  /// The record name inside the sealed store.
  static const String recordName = 'tool_runs';

  final int maxRuns;
  final int maxCsvBytes;

  List<ToolRun> _runs = <ToolRun>[];
  bool _loaded = false;
  bool _sealedUnreadable = false;

  /// Newest first.
  List<ToolRun> get runs => List<ToolRun>.unmodifiable(_runs);

  bool get isEmpty => _runs.isEmpty;

  /// True when the sealed copy exists but this device cannot open it (a lost
  /// Keystore key). Shown rather than hidden: an empty history that is really an
  /// unreadable one would read as "nothing has run".
  bool get sealedUnreadable => _sealedUnreadable;

  /// Bytes the history currently holds, for the storage block's own number.
  int get csvBytes =>
      _runs.fold<int>(0, (int n, ToolRun r) => n + (r.csv?.length ?? 0));

  /// The load in flight, so two callers share one read.
  ///
  /// `ToolsController` starts a load at construction and a run can end before it
  /// finishes. Two loads would each assign [_runs] from the same document, and
  /// the second assignment could land after a run was recorded, dropping it from
  /// memory while the disk kept it. One shared future removes the race rather
  /// than narrowing it.
  Future<void>? _loading;

  Future<void> load() => _loading ??= _load().catchError((Object e) {
        // A throw out of the sealed read left the failed future cached, so
        // every later call returned it and the history never loaded again.
        _loading = null;
        throw e;
      });

  Future<void> _load() async {
    final ValueNotifier<bool> unreadable = ValueNotifier<bool>(false);
    final String? doc =
        await SealedDocument.read(recordName, sealedUnreadable: unreadable);
    _sealedUnreadable = unreadable.value;
    if (doc != null) {
      try {
        final Object? decoded = jsonDecode(doc);
        if (decoded is List) {
          _runs = <ToolRun>[
            for (final Object? e in decoded)
              if (ToolRun.fromJson(e) case final ToolRun run) run,
          ];
        }
      } catch (_) {
        // A corrupt document is reported the same way an unreadable one is:
        // it is not "no runs", and the reader is told so.
        _sealedUnreadable = true;
        _runs = <ToolRun>[];
      }
    }
    _loaded = true;
    _loading = null;
    notifyListeners();
  }

  /// Stores [run] at the head and trims to the two bounds.
  Future<void> record(ToolRun run) async {
    if (!_loaded) await load();
    _runs = <ToolRun>[run, ..._runs];
    _trim();
    await _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    _runs = <ToolRun>[];
    _sealedUnreadable = false;
    await _persist();
    notifyListeners();
  }

  /// The newest [maxRuns] runs, and from the oldest end drop runs until the CSV
  /// budget fits. A run whose CSV alone is over budget keeps its summary and
  /// loses the table, which is stated rather than silently truncated.
  void _trim() {
    if (_runs.length > maxRuns) _runs = _runs.sublist(0, maxRuns);
    int total = csvBytes;
    int i = _runs.length - 1;
    while (total > maxCsvBytes && i >= 0) {
      final ToolRun r = _runs[i];
      if (r.csv != null) {
        _runs[i] = ToolRun(
          kind: r.kind,
          startedAt: r.startedAt,
          endedAt: r.endedAt,
          summary: r.summary,
          failure: r.failure,
        );
        total -= r.csv!.length;
      }
      i--;
    }
  }

  Future<void> _persist() async {
    await SealedDocument.write(
        recordName,
        jsonEncode(<Object?>[for (final ToolRun r in _runs) r.toJson()]));
  }
}
