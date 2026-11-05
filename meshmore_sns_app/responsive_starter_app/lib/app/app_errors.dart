// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
}

final class AppErrors {
  AppErrors._();

  /// Enough to recognise a repeating failure without keeping a log in memory.
  static const int capacity = 20;

  static final List<AppErrorRecord> _records = <AppErrorRecord>[];

  /// Newest last. Read by the Diagnostics developer section.
  static List<AppErrorRecord> get records =>
      List<AppErrorRecord>.unmodifiable(_records);

  static void record(Object error, StackTrace? stack,
      {String where = 'async'}) {
    _records.add(AppErrorRecord(where, firstLine(error), DateTime.now()));
    if (_records.length > capacity) _records.removeAt(0);
    if (kDebugMode) {
      debugPrint('[app] $where error: $error');
      if (stack != null) debugPrint(stack.toString());
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
  static void clear() => _records.clear();

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
