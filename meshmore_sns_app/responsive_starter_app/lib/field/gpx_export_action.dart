// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../util/share.dart';
import '../ui/mm_components.dart';
import 'gpx.dart';
import 'position_history.dart';

/// Offers the recorded trail as a GPX file the user can hand to a mapping app.
///
/// The file is written in the clear on purpose: a GPX that had to be decrypted
/// before a map app could read it would defeat the only reason to export one.
/// The explainer beside this action says so, because the message store is
/// sealed and it would be reasonable to assume this is too.
class TrailGpxAction extends StatefulWidget {
  const TrailGpxAction({super.key, this.clock, this.directory});

  /// Injected so a test can pin the file name and the metadata timestamp.
  final DateTime Function()? clock;

  /// Where the file is written. Production leaves this null and the writer asks
  /// the platform for the temporary directory, which is a share root; a test
  /// passes its own so the write needs no platform.
  final Directory? directory;

  @override
  State<TrailGpxAction> createState() => _TrailGpxActionState();
}

class _TrailGpxActionState extends State<TrailGpxAction> {
  bool _busy = false;

  Future<void> _export() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime Function() clock = widget.clock ?? DateTime.now;
    final List<PositionSample> trail = context.read<PositionRecorder>().rows;
    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(context);
    if (trail.isEmpty) {
      messenger?.showSnackBar(SnackBar(content: Text(l.gpxExportEmpty)));
      return;
    }
    setState(() => _busy = true);
    final File file = await GpxTrack.write(trail,
        clock: clock,
        name: l.gpxExportTrackName,
        directory: widget.directory);
    if (!mounted) return;
    setState(() => _busy = false);
    // The temporary directory is a FileProvider root, so the receiving app can
    // read the file through the URI the platform side builds.
    final bool shared = await Share.file(file.path,
        mime: 'application/gpx+xml', subject: l.gpxExportTrackName);
    await Clipboard.setData(ClipboardData(text: file.path));
    if (!mounted) return;
    messenger?.showSnackBar(SnackBar(
        content:
            Text(shared ? l.gpxExportShared : l.gpxExportDone(file.path))));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return MmAction(
      key: const ValueKey<String>('gpx-export'),
      icon: Icons.route,
      label: l.gpxExportAction,
      onPressed: _busy ? null : _export,
    );
  }
}
