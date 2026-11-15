// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the app does when something throws and there is nowhere to report it.
///
/// There is no crash reporter, by decision: nothing leaves the device except
/// over the radio. Without a handler a release build loses the record
/// entirely — an error inside a stream handler kills the subscription with no
/// line anywhere, and a build error paints Flutter's grey box, which tells a
/// user nothing and offers nothing.
///
/// So: keep the last few in memory for Diagnostics, print them in debug, and
/// draw one plain panel that says the view failed and can be reopened. The
/// panel reads no theme on purpose, because a build error can happen above the
/// theme's provider; it relies on `Material`'s own default text style rather
/// than a size of its own.
final class AppErrorRecord {
  const AppErrorRecord(this.where, this.message, this.at);

  /// `framework` for a build or layout error, `async` for a failed future.
  final String where;
  final String message;
  final DateTime at;

  @override
  String toString() => '$where ${at.toIso8601String()} $message';

  Map<String, Object?> toJson() => <String, Object?>{
        'where': where,
        'message': message,
        'at': at.toIso8601String(),
      };

  /// A record read back from disk. A row that cannot be read is dropped rather
  /// than thrown: the file exists to explain a failure, so it must not become
  /// one when it is malformed.
  static AppErrorRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? where = raw['where'];
    final Object? message = raw['message'];
    final Object? at = raw['at'];
    if (where is! String || message is! String || at is! String) return null;
    final DateTime? when = DateTime.tryParse(at);
    if (when == null) return null;
    return AppErrorRecord(where, message, when);
  }
}

final class AppErrors {
  AppErrors._();

  /// Enough to recognise a repeating failure without keeping a log in memory.
  static const int capacity = 20;

  /// Where the last few records survive the process.
  ///
  /// The list used to live only in memory, so a periodic freeze or a crash left
  /// nothing behind: the app died, the records died with it, and the next launch
  /// had no idea anything had gone wrong. A field report of "it keeps crashing"
  /// could not be answered from the app itself. The records are written on every
  /// error, and read back at launch into the same list the Diagnostics console
  /// shows, so the previous run's failures are still there to read.
  static const String _prefsKey = 'mm.appErrors.v1';

  static final List<AppErrorRecord> _records = <AppErrorRecord>[];

  /// Newest last. Read by the Diagnostics developer section.
  static List<AppErrorRecord> get records =>
      List<AppErrorRecord>.unmodifiable(_records);

  /// Errors read back from the previous run, newest last. Held apart from
  /// [records] so the console can say which run each line came from: a row from
  /// a run that ended badly is evidence, and a row from this run is a symptom.
  static final List<AppErrorRecord> _previous = <AppErrorRecord>[];

  static List<AppErrorRecord> get previous =>
      List<AppErrorRecord>.unmodifiable(_previous);

  static Future<void>? _pendingWrite;

  static void record(Object error, StackTrace? stack,
      {String where = 'async'}) {
    _records.add(AppErrorRecord(where, firstLine(error), DateTime.now()));
    if (_records.length > capacity) _records.removeAt(0);
    if (kDebugMode) {
      debugPrint('[app] $where error: $error');
      if (stack != null) debugPrint(stack.toString());
    }
    // Fire and forget: the caller is usually an error path that must not wait on
    // a disk write, and losing one row to a process death is the case the row
    // exists to explain.
    _pendingWrite = _persist();
    unawaited(_pendingWrite!);
  }

  static Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(<Object?>[for (final r in _records) r.toJson()]));
    } catch (_) {
      // A store that cannot be written is not worth a second failure on the
      // error path.
    } finally {
      // Nothing to clear: the write is tracked by `_pendingWrite`, which a test
      // awaits rather than polling a flag.
    }
  }

  /// Read the previous run's records, and clear them so the next launch reads
  /// this run's instead of the same rows forever.
  ///
  /// Called once at launch. Records written during this run go to the same key,
  /// so the file always describes the most recent run that got as far as writing.
  static Future<void> loadPrevious() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _previous
        ..clear()
        ..addAll(<AppErrorRecord>[
          for (final Object? row in decoded)
            if (AppErrorRecord.fromJson(row) case final AppErrorRecord r) r,
        ]);
    } catch (_) {
      // A malformed file explains nothing; it must not stop a launch.
    }
  }

  /// One line, because a surface this size cannot hold a trace and a user
  /// cannot act on one. The full error reaches the debug log only.
  static String firstLine(Object error) {
    final String text = error.toString();
    final int cut = text.indexOf('\n');
    return cut == -1 ? text : text.substring(0, cut);
  }

  @visibleForTesting
  static void clear() {
    _records.clear();
    _previous.clear();
  }

  /// The write in flight, if any. A test awaits this rather than polling a flag
  /// that could clear between the last byte and the assertion.
  @visibleForTesting
  static Future<void>? get pendingWrite => _pendingWrite;

  /// Installs the three sinks: framework errors, uncaught async errors, and the
  /// widget shown in place of a failed build.
  static void install() {
    final FlutterExceptionHandler? present = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      record(details.exception, details.stack, where: 'framework');
      present?.call(details);
    };
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      record(error, stack);
      // Handled: an unhandled async error would otherwise end the isolate.
      return true;
    };
    ErrorWidget.builder = (FlutterErrorDetails details) =>
        FailedView(message: firstLine(details.exception));
  }
}

/// The replacement for Flutter's grey box: what happened, and what to do.
///
/// Public so a test can build it without provoking a real failure.
class FailedView extends StatelessWidget {
  const FailedView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'This part of the app could not be drawn.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Go back and open it again. Diagnostics keeps the record.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // The message only helps someone reading a report, so it stays
                // quiet rather than prominent.
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
