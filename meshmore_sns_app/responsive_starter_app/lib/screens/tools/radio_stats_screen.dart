// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../tools/radio_stats_tool.dart';
import '../../tools/tools_controller.dart';
import '../../ui/mm_components.dart';
import 'tool_widgets.dart';

/// R60 T1 — what the radio itself has seen.
class RadioStatsScreen extends StatefulWidget {
  const RadioStatsScreen({super.key});

  @override
  State<RadioStatsScreen> createState() => _RadioStatsScreenState();
}

class _RadioStatsScreenState extends State<RadioStatsScreen> {
  late final RadioStatsTool _tool = context.read<ToolsController>().stats;

  @override
  void initState() {
    super.initState();
    // Fresh numbers on arrival; harmless offline (it says why).
    if (_tool.mc.isReady && !_tool.running) _tool.fetch();
  }

  @override
  void dispose() {
    // Auto-refresh is for while you're looking.
    if (_tool.auto) _tool.setAuto(false);
    super.dispose();
  }

  static String _uptime(int s) {
    final Duration d = Duration(seconds: s);
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }

  static String _delta(int now, int? before) {
    if (before == null || now == before) return '$now';
    final int d = now - before;
    return '$now  (${d > 0 ? '+' : ''}$d)';
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final RadioStatsTool t = _tool;
    return ToolPage(
      title: l.toolStatsName,
      tool: t,
      body: (BuildContext context) => <Widget>[
        // A wrap, not a row: at the 200 % text floor "Refresh" and "Auto"
        // together are wider than 320 dp, and the switch must stay reachable.
        // On a normal phone both fit on one line, so this changes nothing
        // there.
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(l.statsRefresh),
              onPressed: t.running || !t.mc.isReady ? null : t.fetch,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // "Auto (every 5 s)" alone is wider than the row at 200 %,
                // so the label takes what is left and wraps; the switch keeps
                // its tap target.
                Flexible(child: Text(l.statsAuto, softWrap: true)),
                Switch(
                  value: t.auto,
                  onChanged: t.mc.isReady ? t.setAuto : null,
                ),
              ],
            ),
          ],
        ),
        ToolFailureLine(t),
        const SizedBox(height: 12),
        if (t.radio == null && t.core == null && t.packets == null)
          ToolLine(l.statsNotFetched, muted: true),
        if (t.radio != null) ...<Widget>[
          MmSectionHeader(l.statsSectionRadio),
          MmPanel(
            child: Column(
              children: <Widget>[
                MmReadout(
                    label: l.statsNoise,
                    value: '${t.radio!.noiseFloorDbm} dBm',
                    emphasize: true),
                MmReadout(label: l.statsLastRssi, value: '${t.radio!.lastRssi} dBm'),
                MmReadout(
                    label: l.statsLastSnr,
                    value: l.toolsDb(fmtDb(t.radio!.lastSnrDb))),
                MmReadout(label: l.statsTxAir, value: _uptime(t.radio!.txAirSecs)),
                MmReadout(label: l.statsRxAir, value: _uptime(t.radio!.rxAirSecs)),
                if (t.txDutyCyclePercent != null)
                  MmReadout(
                      label: l.statsDuty,
                      value: '${t.txDutyCyclePercent!.toStringAsFixed(2)} %'),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (t.packets != null) ...<Widget>[
          MmSectionHeader(l.statsSectionPackets),
          Builder(builder: (BuildContext context) {
            final PacketStats p = t.packets!;
            final PacketStats? b = t.previousPackets;
            return MmPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  MmReadout(
                      label: l.statsReceived,
                      value: _delta(p.received, b?.received)),
                  ToolLine(l.statsSplit(p.receivedFlood, p.receivedDirect),
                      muted: true),
                  MmReadout(label: l.statsSent, value: _delta(p.sent, b?.sent)),
                  ToolLine(l.statsSplit(p.sentFlood, p.sentDirect), muted: true),
                  if (p.receiveErrors != null)
                    MmReadout(
                        label: l.statsRxErrors,
                        value: _delta(p.receiveErrors!, b?.receiveErrors)),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
        ],
        if (t.core != null) ...<Widget>[
          MmSectionHeader(l.statsSectionCore),
          MmPanel(
            child: Column(
              children: <Widget>[
                MmReadout(label: l.statsUptime, value: _uptime(t.core!.uptimeSecs)),
                MmReadout(label: l.statsQueue, value: '${t.core!.queueLen}'),
                MmReadout(
                    label: l.statsErrFlags,
                    value: '0x${t.core!.errFlags.toRadixString(16).padLeft(4, '0')}'),
                MmReadout(
                    label: l.statsBattery,
                    value: '${t.core!.batteryMilliVolts} mV'),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
