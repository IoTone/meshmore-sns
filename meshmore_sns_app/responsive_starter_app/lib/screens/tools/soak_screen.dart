// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../bot/bot_scope.dart';
import '../../gen/app_localizations.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../tools/soak_tool.dart';
import '../../tools/tools_controller.dart';
import '../../ui/mm_components.dart';
import '../delivery_status_icon.dart';
import 'tool_pickers.dart';
import 'tool_widgets.dart';

/// R60 T5 — many sequenced messages to one conversation, counted.
class SoakScreen extends StatelessWidget {
  const SoakScreen({super.key});

  static const List<int> counts = <int>[10, 25, 50, 100, 250, 500];
  static const List<Duration> intervals = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MeshcoreController mc = context.read<MeshcoreController>();
    final SoakTool t = context.read<ToolsController>().soak;
    return ToolPage(
      title: l.toolSoakName,
      tool: t,
      children: <Widget>[
        ToolLine(l.soakPairHint, muted: true),
        const SizedBox(height: 8),
        ToolField(
          label: l.soakScope,
          child: ToolPickerButton(
            text: t.scope == null ? l.toolsChoose : t.scopeLabel,
            onTap: t.running
                ? null
                : () async {
                    final (BotScope, String)? pick =
                        await pickConversation(context, mc);
                    if (pick != null) {
                      t.configure(scope: pick.$1, scopeLabel: pick.$2);
                    }
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
            // Only intervals the scope allows (rule 1: floors are shown).
            values: <Duration>[
              for (final Duration d in intervals)
                if (d >= t.minInterval) d,
            ],
            label: (Duration d) => fmtDuration(l, d),
            enabled: !t.running,
            onChanged: (Duration d) => t.configure(interval: d),
          ),
        ),
        const SizedBox(height: 12),
        ToolActionRow(
          tool: t,
          onStart: t.start,
          copyText: t.entries.isEmpty
              ? null
              : () => t.exportReport(firmware: mc.deviceInfo?.firmwareVersion),
        ),
        ToolFailureLine(t),
        if (t.runId != null && t.entries.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          MmPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ToolLine(l.soakRun(t.runId!), muted: true),
                ToolLine(l.soakSummary(t.sent, t.delivered, t.failed)),
                ToolLine(l.soakEchoes(t.echoed, t.duplicates, t.reordered)),
                if (t.listening) ToolLine(l.soakListening, muted: true),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final SoakEntry e in t.entries.reversed.take(100))
            ToolLine(
              '#${e.seq}/${t.count}'
              '${e.ackRttMs == null ? '' : '  ${l.toolsMs(e.ackRttMs!)}'}'
              '${e.echoRttMs == null ? '' : '  · ${l.soakEcho(e.echoRttMs!)}'}'
              '${e.echoes > 1 ? '  ×${e.echoes}' : ''}',
              leading: e.delivery == null
                  ? outcomeIcon(context, null)
                  : DeliveryStatusIcon(e.delivery!, size: 16),
            ),
        ],
      ],
    );
  }
}
