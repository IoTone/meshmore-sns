// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../bot/bot_scope.dart';
import '../../gen/app_localizations.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../tools/range_test_tool.dart';
import '../../tools/tools_controller.dart';
import '../../ui/mm_components.dart';
import '../../util/geo.dart' as geo;
import 'tool_pickers.dart';
import 'tool_widgets.dart';

/// R60 T6 — Meshtastic-style range test on a private channel.
class RangeTestScreen extends StatelessWidget {
  const RangeTestScreen({super.key});

  static const List<Duration> intervals = <Duration>[
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];
  static const List<int> counts = <int>[10, 50, 100, 250, 1000];

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MeshcoreController mc = context.read<MeshcoreController>();
    final RangeTestTool t = context.read<ToolsController>().range;
    final bool sender = t.mode == RangeMode.sender;
    return ToolPage(
      title: l.toolRangeName,
      tool: t,
      children: <Widget>[
        ToolLine(l.rangeHint, muted: true),
        const SizedBox(height: 8),
        SegmentedButton<RangeMode>(
          segments: <ButtonSegment<RangeMode>>[
            ButtonSegment<RangeMode>(
                value: RangeMode.sender,
                icon: const Icon(Icons.podcasts),
                label: Text(l.rangeSender)),
            ButtonSegment<RangeMode>(
                value: RangeMode.receiver,
                icon: const Icon(Icons.hearing),
                label: Text(l.rangeReceiver)),
          ],
          selected: <RangeMode>{t.mode},
          onSelectionChanged: t.running
              ? null
              : (Set<RangeMode> s) => t.configure(mode: s.first),
        ),
        const SizedBox(height: 8),
        ToolField(
          label: l.rangeChannel,
          child: ToolPickerButton(
            text: t.channelIdx == null ? l.toolsChoose : t.channelLabel,
            onTap: t.running
                ? null
                : () async {
                    final (BotScope, String)? pick =
                        await pickConversation(context, mc, includeDms: false);
                    if (pick != null && pick.$1 is ChannelScope) {
                      t.configure(
                        channelIdx: (pick.$1 as ChannelScope).idx,
                        channelLabel: pick.$2,
                      );
                    }
                  },
          ),
        ),
        if (sender) ...<Widget>[
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
        ],
        const SizedBox(height: 12),
        ToolActionRow(
          tool: t,
          onStart: t.start,
          copyLabel: l.rangeCopyCsv,
          copyText: !sender && t.rows.isNotEmpty ? t.exportCsv : null,
        ),
        ToolFailureLine(t),
        const SizedBox(height: 12),
        if (sender && t.startedAt != null)
          ToolLine(l.rangeBeacons(t.beaconsSent)),
        if (!sender && t.startedAt != null) ...<Widget>[
          MmPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ToolLine(l.rangeSummary(t.received, t.lost)),
                if (t.bestSnrDb != null)
                  ToolLine(l.rangeBest(fmtDb(t.bestSnrDb!))),
                if (t.farthestM != null)
                  ToolLine(l.rangeFarthest(geo.formatDistance(t.farthestM)!)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final RangeRow r in t.rows.take(200))
            ToolLine(
              '#${r.seq}  '
              '${r.snrDb == null ? '' : '${fmtDb(r.snrDb!)} dB  '}'
              '${r.flood ? '${l.rangeFlood}  ' : ''}'
              '${geo.formatDistance(r.distanceM) ?? ''}',
            ),
        ],
      ],
    );
  }
}
