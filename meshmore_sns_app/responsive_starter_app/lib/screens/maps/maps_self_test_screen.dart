// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app_state_model.dart';
import '../../gen/app_localizations.dart';
import '../../maps/maps_controller.dart';
import '../../maps/maps_self_test.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../theme/mm_skin.dart';
import '../../ui/mm_components.dart';
import '../../ui/mm_scaffold.dart';
import '../tools/tool_widgets.dart';

String selfCheckTitle(AppLocalizations l, SelfCheckId id) => switch (id) {
      SelfCheckId.reach => l.selfCheckReach,
      SelfCheckId.viewCache => l.selfCheckViewCache,
      SelfCheckId.revalidate => l.selfCheckRevalidate,
      SelfCheckId.pack => l.selfCheckPack,
      SelfCheckId.update => l.selfCheckUpdate,
      SelfCheckId.eventLayer => l.selfCheckEventLayer,
      SelfCheckId.offline => l.selfCheckOffline,
      SelfCheckId.resume => l.selfCheckResume,
      SelfCheckId.guards => l.selfCheckGuards,
      SelfCheckId.expiry => l.selfCheckExpiry,
      SelfCheckId.disk => l.selfCheckDisk,
    };

/// R61 — Offline maps → Self-test. Validates the whole maps path on
/// this phone against the real servers; the report is meant to be
/// pasted into an issue.
class MapsSelfTestScreen extends StatefulWidget {
  const MapsSelfTestScreen({super.key, this.test});

  /// Injected in widget tests; built on demand otherwise.
  final MapsSelfTest? test;

  @override
  State<MapsSelfTestScreen> createState() => _MapsSelfTestScreenState();
}

class _MapsSelfTestScreenState extends State<MapsSelfTestScreen> {
  MapsSelfTest? _test;

  @override
  void initState() {
    super.initState();
    _test = widget.test;
  }

  @override
  void dispose() {
    if (widget.test == null) _test?.dispose();
    super.dispose();
  }

  MapsSelfTest _build() {
    final MapsController maps = context.read<MapsController>();
    final MeshcoreController mc = context.read<MeshcoreController>();
    final Directory? store = maps.storageDir;
    final Directory sandbox = Directory(
        '${store?.parent.path ?? Directory.systemTemp.path}/maps-selftest');
    return MapsSelfTest(
      sandbox: sandbox,
      appVersion: AppState.packageInfo?.version ?? '',
      lat: mc.ownLocation?.latitude,
      lon: mc.ownLocation?.longitude,
    );
  }

  Future<void> _run() async {
    if (_test == null) setState(() => _test = _build());
    await _test!.run();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final MapsSelfTest? t = _test;
    return Scaffold(
      appBar: AppBar(title: Text(l.mapsSelfTest)),
      body: MmScaffold(
        child: ListenableBuilder(
          listenable: t ?? Listenable.merge(const <Listenable>[]),
          builder: (BuildContext context, _) {
            final bool running = t?.running ?? false;
            final bool finished = t != null && !running && t.total != null;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: <Widget>[
                ToolLine(l.selfTestIntro, muted: true),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      icon: running
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_arrow),
                      label: Text(running ? l.selfTestRunning : l.selfTestRun),
                      onPressed: running ? null : _run,
                    ),
                    if (finished)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.copy),
                        label: Text(l.selfTestCopy),
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: t.report()));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.selfTestCopied)));
                        },
                      ),
                  ],
                ),
                if (finished) ...<Widget>[
                  const SizedBox(height: 12),
                  ToolNotice(
                    text: t.passed
                        ? l.selfTestPass
                        : l.selfTestFail(t.failures),
                    icon: t.passed ? Icons.check_circle : Icons.error_outline,
                  ),
                ],
                const SizedBox(height: 12),
                for (final SelfCheckId id in SelfCheckId.values)
                  Builder(builder: (BuildContext context) {
                    final SelfCheck? c = t?.checks[id.index];
                    final CheckState s = c?.state ?? CheckState.pending;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: MmListRow(
                        leading: _stateIcon(skin, s),
                        title: Text(selfCheckTitle(l, id)),
                        subtitle: (c?.detail ?? '').isEmpty
                            ? null
                            : Text(
                                c!.detail,
                                style: TextStyle(
                                    color: skin.color.fgMuted,
                                    fontFamily: skin.type.monoFamily,
                                    fontSize: 11),
                              ),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Shape carries the state, not just colour (R13).
  Widget _stateIcon(MmSkin skin, CheckState s) => switch (s) {
        CheckState.pending =>
          Icon(Icons.radio_button_unchecked, color: skin.color.fgMuted),
        CheckState.running => const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2)),
        CheckState.pass => Icon(Icons.check_circle, color: skin.color.accent),
        CheckState.fail => Icon(Icons.cancel, color: skin.color.alert),
        CheckState.skipped =>
          Icon(Icons.remove_circle_outline, color: skin.color.fgMuted),
      };
}
