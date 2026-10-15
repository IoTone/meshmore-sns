// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../meshcore/discovered_node.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../theme/mm_skin.dart';
import '../../tools/tools_controller.dart';
import '../../tools/trace_tool.dart';
import '../../ui/mm_components.dart';
import 'tool_pickers.dart';
import 'tool_widgets.dart';

/// R60 T3 — per-hop SNR along a repeater chain.
class TraceScreen extends StatefulWidget {
  const TraceScreen({super.key});

  @override
  State<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends State<TraceScreen> {
  bool _manual = false;
  bool _roundTrip = true;
  DiscoveredNode? _node;
  final TextEditingController _manualCtrl = TextEditingController();

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  List<int>? get _path => _manual
      ? parseManualPath(_manualCtrl.text)
      : (_node == null ? null : tracePathFor(_node!, roundTrip: _roundTrip));

  static String _hex(List<int> p) =>
      p.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(',');

  /// A hop's display name: the repeater whose key starts with it.
  static String _hopName(MeshcoreController mc, int hash) {
    final String h = hash.toRadixString(16).padLeft(2, '0');
    for (final DiscoveredNode n in mc.nodes) {
      if ((n.type == kAdvTypeRepeater || n.type == kAdvTypeRoom) &&
          n.pubKeyHex.startsWith(h)) {
        return '$h ${n.name}';
      }
    }
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final TraceTool t = context.read<ToolsController>().trace;
    final List<int>? path = _path;
    return ToolPage(
      title: l.toolTraceName,
      tool: t,
      children: <Widget>[
        SegmentedButton<bool>(
          segments: <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: false, label: Text(l.traceToNode)),
            ButtonSegment<bool>(value: true, label: Text(l.traceManual)),
          ],
          selected: <bool>{_manual},
          onSelectionChanged: t.running
              ? null
              : (Set<bool> s) => setState(() => _manual = s.first),
        ),
        const SizedBox(height: 8),
        if (!_manual) ...<Widget>[
          ToolField(
            label: l.pingTarget,
            child: ToolPickerButton(
              text: _node?.name ?? l.toolsChoose,
              onTap: t.running
                  ? null
                  : () async {
                      final DiscoveredNode? n = await pickContact(
                        context,
                        mc,
                        enabled: (DiscoveredNode n) => tracePathFor(n) != null,
                        reason: l.traceNoRoute,
                      );
                      if (n != null) setState(() => _node = n);
                    },
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.traceRoundTrip),
            value: _roundTrip,
            onChanged: t.running
                ? null
                : (bool v) => setState(() => _roundTrip = v),
          ),
        ] else
          TextField(
            controller: _manualCtrl,
            enabled: !t.running,
            decoration: InputDecoration(
              isDense: true,
              hintText: l.traceManualHint,
              errorText: _manualCtrl.text.isNotEmpty && path == null
                  ? l.traceInvalid
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        if (path != null) ToolLine(l.tracePath(_hex(path)), muted: true),
        if (!_manual && _node == null)
          ToolLine(l.traceNoRepeaters, muted: true),
        const SizedBox(height: 12),
        ToolActionRow(
          tool: t,
          startLabel: l.traceRun,
          onStart: path == null
              ? null
              : () => t.trace(path,
                  label: _manual ? _hex(path) : (_node?.name ?? '')),
        ),
        if (!_manual && _node != null && !t.running)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text(l.traceReset),
              onPressed: mc.isReady
                  ? () async {
                      final ScaffoldMessengerState sm =
                          ScaffoldMessenger.of(context);
                      if (await t.resetPath(_node!.pubKeyHex)) {
                        sm.showSnackBar(
                            SnackBar(content: Text(l.traceResetDone)));
                      }
                    }
                  : null,
            ),
          ),
        ToolFailureLine(t),
        for (final TraceRun r in t.runs) ...<Widget>[
          const SizedBox(height: 12),
          _RunPanel(run: r, hopName: (int h) => _hopName(mc, h)),
        ],
      ],
    );
  }
}

class _RunPanel extends StatelessWidget {
  const _RunPanel({required this.run, required this.hopName});
  final TraceRun run;
  final String Function(int hash) hopName;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final TraceResult? r = run.result;
    final String time =
        '${run.at.hour.toString().padLeft(2, '0')}:${run.at.minute.toString().padLeft(2, '0')}:${run.at.second.toString().padLeft(2, '0')}';
    final List<Widget> rows = <Widget>[];
    if (r != null) {
      final int hs = r.hashSize;
      final (int, double)? weak = run.weakest;
      for (int i = 0; i < r.hopSnrsDb.length; i++) {
        final int hash = r.pathHashes[i * hs];
        rows.add(_HopRow(
          label: hopName(hash),
          snr: r.hopSnrsDb[i],
          weakest: weak?.$1 == i,
        ));
      }
      rows.add(_HopRow(
        label: l.traceToUs,
        snr: r.finalSnrDb,
        weakest: weak?.$1 == r.hopSnrsDb.length,
      ));
      if (weak != null) {
        final String who = weak.$1 == r.hopSnrsDb.length
            ? l.traceToUs
            : hopName(r.pathHashes[weak.$1 * hs]);
        rows.add(ToolLine(l.traceWeakest(who, fmtDb(weak.$2)), muted: true));
      }
    }
    return MmPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ToolLine(
            '$time  ${run.label}${run.rttMs == null ? '' : '  · ${l.toolsMs(run.rttMs!)}'}',
            leading: outcomeIcon(
                context, run.done ? (r != null) : null),
          ),
          if (run.lost) ToolLine(l.traceNoAnswer, muted: true),
          if (run.failure != null)
            ToolLine(toolFailureText(l, run.failure!), muted: true),
          ...rows,
          if (r == null && !run.done)
            LinearProgressIndicator(
                color: skin.color.accent, backgroundColor: skin.color.line),
        ],
      ),
    );
  }
}

/// Hash · name · bar · SNR. The bar spans −20…+15 dB.
class _HopRow extends StatelessWidget {
  const _HopRow({
    required this.label,
    required this.snr,
    required this.weakest,
  });
  final String label;
  final double snr;
  final bool weakest;

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final double frac = ((snr + 20) / 35).clamp(0.02, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: skin.type.monoFamily,
                    fontSize: 12,
                    color: skin.color.fg)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 6,
                color: weakest ? skin.color.alert : skin.color.accent,
                backgroundColor: skin.color.line,
              ),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '${weakest ? '▼ ' : ''}${fmtDb(snr)} dB',
              textAlign: TextAlign.end,
              style: TextStyle(
                  fontFamily: skin.type.monoFamily,
                  fontSize: 12,
                  color: skin.color.fg),
            ),
          ),
        ],
      ),
    );
  }
}
