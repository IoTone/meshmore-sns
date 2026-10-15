// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../theme/mm_skin.dart';
import '../../tools/mesh_tool.dart';
import '../../tools/tools_controller.dart';
import '../../ui/mm_components.dart';
import '../../ui/mm_scaffold.dart';
import 'tool_widgets.dart';

/// R60 — Settings → Tools (issue #7). One row per tool; the tool that
/// holds the radio wears a RUNNING pill.
class ToolsHubScreen extends StatelessWidget {
  const ToolsHubScreen({super.key});

  static (IconData, String, String) entry(AppLocalizations l, ToolKind k) =>
      switch (k) {
        ToolKind.stats => (Icons.equalizer, l.toolStatsName, l.toolStatsSub),
        ToolKind.ping => (Icons.swap_horiz, l.toolPingName, l.toolPingSub),
        ToolKind.trace => (Icons.route, l.toolTraceName, l.toolTraceSub),
        ToolKind.discover =>
          (Icons.wifi_tethering, l.toolDiscoverName, l.toolDiscoverSub),
        ToolKind.soak => (Icons.repeat, l.toolSoakName, l.toolSoakSub),
        ToolKind.range => (Icons.straighten, l.toolRangeName, l.toolRangeSub),
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ToolsController tools = context.watch<ToolsController>();
    final bool ready = context.select<MeshcoreController, bool>(
        (MeshcoreController mc) => mc.isReady);
    final MmSkin skin = context.skin;
    return Scaffold(
      appBar: AppBar(title: Text(l.toolsTitle)),
      body: MmScaffold(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          children: <Widget>[
            if (!ready)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ToolNotice(text: l.toolsOffline, icon: Icons.link_off),
              ),
            for (final ToolKind k in ToolKind.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Builder(builder: (BuildContext context) {
                  final (IconData icon, String name, String sub) =
                      entry(l, k);
                  return MmListRow(
                    leading: Icon(icon, color: skin.color.accent),
                    title: Text(name),
                    subtitle: Text(sub,
                        style: TextStyle(
                            color: skin.color.fgMuted, fontSize: 12)),
                    trailing: tools.running == k
                        ? MmStatusPill(l.toolsRunning)
                        : Icon(Icons.chevron_right,
                            color: skin.color.fgMuted),
                    onTap: () => context.push('/settings/tools/${k.name}'),
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }
}
