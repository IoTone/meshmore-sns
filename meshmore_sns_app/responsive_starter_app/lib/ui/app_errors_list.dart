// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../app/app_errors.dart';
import '../gen/app_localizations.dart';
import '../screens/diagnostics_redaction.dart';
import '../theme/mm_skin.dart';

/// The app's own error records, as rows.
///
/// Newest first, because the question a support report asks is "what happened
/// last". The age is written as elapsed time rather than a timestamp: "4 minutes
/// ago" answers "how often does this happen" at a glance, where a clock time
/// makes the reader do the subtraction.
class AppErrorsList extends StatelessWidget {
  const AppErrorsList({super.key, required this.errors, required this.previous});

  final List<AppErrorRecord> errors;

  /// True for the previous run's records: a row from a run that ended is
  /// evidence about a failure, a row from this run is a symptom of one.
  final bool previous;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime now = DateTime.now();
    final List<AppErrorRecord> newestFirst = errors.reversed.toList();
    return Padding(
      key: ValueKey<String>(
          previous ? 'diagnostics-errors-previous' : 'diagnostics-errors-current'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            previous
                ? l.diagnosticsErrorsPrevious(newestFirst.length)
                : l.diagnosticsErrorsCurrent(newestFirst.length),
            style: TextStyle(
                color: skin.color.fgMuted,
                fontSize: skin.type.sizeSm,
                fontFamily: skin.type.bodyFamily),
          ),
          if (newestFirst.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(l.diagnosticsErrorsNone,
                  style: TextStyle(
                      color: skin.color.fgMuted,
                      fontSize: skin.type.sizeSm,
                      fontFamily: skin.type.bodyFamily)),
            )
          else
            for (final AppErrorRecord r in newestFirst)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText(
                  // Masked like every other Diagnostics surface. An error
                  // message can carry a short key or a URL, and this list was
                  // the one place that printed it verbatim.
                  '${_age(now, r.at)} · ${r.where} · '
                  '${const DiagnosticsRedaction().maskSecrets(r.message)}',
                  style: TextStyle(
                      color: skin.color.fg,
                      fontSize: skin.type.sizeSm,
                      fontFamily: skin.type.monoFamily),
                ),
              ),
        ],
      ),
    );
  }

  /// Elapsed time, at the coarsest unit that is still true.
  static String _age(DateTime now, DateTime at) {
    final Duration d = now.difference(at);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
