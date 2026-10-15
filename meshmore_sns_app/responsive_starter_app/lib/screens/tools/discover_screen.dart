// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../meshcore/discovered_node.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../theme/mm_skin.dart';
import '../../tools/discover_tool.dart';
import '../../tools/tools_controller.dart';
import '../../ui/mm_components.dart';
import 'tool_widgets.dart';

/// R60 T4 — which repeaters hear us right now, both ways.
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  /// Name from contacts/adverts when the key (or prefix) is known.
  static String _name(MeshcoreController mc, String keyHex) {
    for (final DiscoveredNode n in mc.nodes) {
      if (n.pubKeyHex.startsWith(keyHex) && n.name.isNotEmpty) return n.name;
    }
    return keyHex.substring(0, 8);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MeshcoreController mc = context.read<MeshcoreController>();
    final DiscoverTool t = context.read<ToolsController>().discover;
    final MmSkin skin = context.skin;
    return ToolPage(
      title: l.toolDiscoverName,
      tool: t,
      children: <Widget>[
        ToolActionRow(tool: t, startLabel: l.discoverStart, onStart: t.start),
        ToolFailureLine(t),
        const SizedBox(height: 12),
        if (t.running) ToolLine(l.discoverListening(t.remaining.inSeconds)),
        if (!t.running && t.startedAt != null && t.found.isEmpty &&
            t.failure == null)
          ToolLine(l.discoverNone, muted: true),
        for (final DiscoveredRepeater r in t.found)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: MmPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ToolLine(_name(mc, r.keyHex),
                      leading: Icon(Icons.cell_tower,
                          size: 16, color: skin.color.accent)),
                  ToolLine('↑ ${l.discoverTheyHearUs(fmtDb(r.response.theirSnrDb))}'),
                  ToolLine('↓ ${l.discoverWeHearThem(fmtDb(r.response.ourSnrDb), r.response.ourRssi)}'),
                  if (r.asymmetric)
                    ToolLine(l.discoverAsymmetric,
                        leading: Icon(Icons.warning_amber,
                            size: 16, color: skin.color.alert)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
