// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../field/operational_export.dart';
import '../field/position_history.dart';
import '../gen/app_localizations.dart';
import '../places/place_store.dart';
import '../sos/checkin.dart';
import '../sos/sos_controller.dart';
import '../telemetry/coverage_session.dart';
import '../ui/mm_components.dart';

/// Builds one field bundle from what this session has, writes it, and puts the
/// path on the clipboard.
///
/// The window is the session: from the first recorded point to now. A user who
/// wants a different window exports again after starting a new session, which
/// is the honest version of a range picker the bundle cannot check anyway.
class FieldExportAction extends StatefulWidget {
  const FieldExportAction({super.key, this.clock});

  /// Injected so a test can pin the timestamps in the manifest.
  final DateTime Function()? clock;

  @override
  State<FieldExportAction> createState() => _FieldExportActionState();
}

class _FieldExportActionState extends State<FieldExportAction> {
  bool _busy = false;

  Future<void> _export() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime Function() clock = widget.clock ?? DateTime.now;
    setState(() => _busy = true);
    final DateTime now = clock();
    final List<PositionSample> trail =
        context.read<PositionRecorder>().rows;
    final DateTime from = trail.isEmpty ? now.subtract(const Duration(hours: 1)) : trail.first.at;
    final CoverageSession coverage = context.read<CoverageSession>();
    final Map<String, Object?> bundle = OperationalExport.build(
      trail: trail,
      places: context.read<PlaceStore>().all,
      coverage: coverage.samples,
      edges: coverage.edges(),
      from: from,
      to: now,
      now: now,
      checkin: _checkinRecord(),
    );
    final String path = (await OperationalExport.write(bundle, clock: clock)).path;
    if (!mounted) return;
    setState(() => _busy = false);
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(l.fieldExportDone(path))));
  }

  /// The check-in as a row, when one was raised this session. The text is the
  /// one the app sent; a channel answer is a claim, so it is not written as an
  /// acknowledgement.
  Map<String, Object?>? _checkinRecord() {
    final CheckinWatch? watch = context.read<SosController>().checkin;
    if (watch == null) return null;
    final Checkin c = watch.checkin;
    return <String, Object?>{
      'raisedAtMs': c.raisedAt.millisecondsSinceEpoch,
      'untilMs': c.until.millisecondsSinceEpoch,
      'id': c.id,
      'callsign': c.callsign,
      'state': watch.state.name,
      if (c.lat != null) 'lat': c.lat,
      if (c.lon != null) 'lon': c.lon,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return MmAction(
      key: const ValueKey<String>('field-export'),
      icon: Icons.save_alt,
      label: l.fieldExportAction,
      onPressed: _busy ? null : _export,
    );
  }
}
