// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../meshcore/discovered_node.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../tools/ping_tool.dart';
import '../../tools/tools_controller.dart';
import '../../ui/mm_components.dart';
import 'tool_pickers.dart';
import 'tool_widgets.dart';

/// R60 T2 — round-trip to one node, N times.
class PingScreen extends StatelessWidget {
  const PingScreen({super.key});

  static const List<int> counts = <int>[1, 3, 5, 10, 20];
  static const List<Duration> intervals = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
  ];

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MeshcoreController mc = context.read<MeshcoreController>();
    final PingTool t = context.read<ToolsController>().ping;
    return ToolPage(
      title: l.toolPingName,
      tool: t,
      children: <Widget>[
        ToolField(
          label: l.pingTarget,
          child: ToolPickerButton(
            text: t.targetPubKeyHex == null ? l.toolsChoose : t.targetName,
            onTap: t.running
                ? null
                : () async {
                    final DiscoveredNode? n = await pickContact(context, mc);
                    if (n != null) t.setTarget(n);
                  },
          ),
        ),
        ToolField(
          label: l.toolsCount,
          child: ToolChoice<int>(
            value: t.count,
            values: counts,
            label: (int v) => '$v',
            enabled: !t.running,
            onChanged: (int v) => t.configure(count: v),
          ),
        ),
        ToolField(
          label: l.toolsInterval,
          child: ToolChoice<Duration>(
            value: t.interval,
            values: intervals,
            label: (Duration d) => fmtDuration(l, d),
            enabled: !t.running,
            onChanged: (Duration d) => t.configure(interval: d),
          ),
        ),
        if (t.targetPubKeyHex != null)
          ToolLine(
            t.method == PingMethod.status
                ? l.pingMethodStatus
                : l.pingMethodTelemetry,
            muted: true,
          ),
        const SizedBox(height: 12),
        ToolActionRow(
          tool: t,
          onStart: t.start,
          copyText: t.attempts.isEmpty
              ? null
              : () => const JsonEncoder.withIndent('  ').convert(
                  t.report(firmware: mc.deviceInfo?.firmwareVersion)),
        ),
        ToolFailureLine(t),
        if (t.attempts.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          MmPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ToolLine(l.pingSummary(t.sent, t.replied, t.lost)),
                if (t.rttMin != null)
                  ToolLine(l.pingRtt(t.rttMin!, t.rttAvg!, t.rttMax!)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final PingAttempt a in t.attempts)
            ToolLine(
              '#${a.seq}  ${switch (a) {
                PingAttempt(replied: true, :final int rttMs?) =>
                  l.toolsMs(rttMs),
                PingAttempt(:final failure?) => toolFailureText(l, failure),
                PingAttempt(replied: false) => l.pingLost,
                _ => l.pingWaiting,
              }}',
              leading: outcomeIcon(context, a.replied),
            ),
        ],
        if (t.lastStatus != null) ...<Widget>[
          const SizedBox(height: 12),
          MmSectionHeader(l.pingLastStatus),
          _StatusPanel(t.lastStatus!),
        ],
      ],
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel(this.s);
  final RepeaterStatus s;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Duration up = Duration(seconds: s.uptimeSecs);
    return MmPanel(
      child: Column(
        children: <Widget>[
          MmReadout(label: l.statsBattery, value: '${s.batteryMilliVolts} mV'),
          MmReadout(
              label: l.statsUptime,
              value: '${up.inDays}d ${up.inHours % 24}h ${up.inMinutes % 60}m'),
          MmReadout(label: l.statsNoise, value: '${s.noiseFloorDbm} dBm'),
          MmReadout(label: l.statsLastRssi, value: '${s.lastRssi} dBm'),
          if (s.lastSnrDb != null)
            MmReadout(label: l.statsLastSnr, value: l.toolsDb(fmtDb(s.lastSnrDb!))),
          MmReadout(label: l.statsReceived, value: '${s.packetsReceived}'),
          MmReadout(label: l.statsSent, value: '${s.packetsSent}'),
          MmReadout(label: l.statsQueue, value: '${s.txQueueLen}'),
        ],
      ),
    );
  }
}
