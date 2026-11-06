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

  Widget _row(BuildContext context, AppLocalizations l, MmSkin skin,
      ToolsController tools, ToolKind k) {
    final (IconData icon, String name, String sub) = entry(l, k);
    return Padding(
      padding: EdgeInsets.only(bottom: skin.space.rowGap),
      child: MmListRow(
        leading: Icon(icon, color: skin.color.accent),
        title: Text(name),
        subtitle: Text(sub,
            style: TextStyle(color: skin.color.fgMuted, fontSize: skin.type.sizeBody)),
        trailing: tools.running == k
            ? MmStatusPill(l.toolsRunning)
            : Icon(Icons.chevron_right, color: skin.color.fgMuted),
        onTap: () => context.push('/settings/tools/${k.name}'),
      ),
    );
  }

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
          padding: skin.space.padScreen,
          children: <Widget>[
            if (!ready)
              Padding(
                padding: EdgeInsets.only(bottom: skin.space.rowGap),
                child: ToolNotice(text: l.toolsOffline, icon: Icons.link_off),
              ),
            // Check-in is a field-safety action rather than an engineering
            // tool, and it lives here because the alarm screen carries exactly
            // one control and must not offer a second way to send (`/sos`,
            // `sos_screen.dart`). It sits first: a user looking for it is in a
            // hurry, and a tester looking for a tool is not.
            Padding(
              padding: EdgeInsets.only(bottom: skin.space.rowGap),
              child: MmListRow(
                key: const ValueKey<String>('tools-checkin'),
                leading: Icon(Icons.schedule_send, color: skin.color.accent),
                title: Text(l.checkinTitle),
                subtitle: Text(l.checkinOneMessage,
                    style: TextStyle(
                        color: skin.color.fgMuted,
                        fontSize: skin.type.sizeBody)),
                trailing: Icon(Icons.chevron_right, color: skin.color.fgMuted),
                onTap: () => context.push('/checkin'),
              ),
            ),
            // Two tools answer a question a user asks; the rest are
            // engineering, so they sit under their own label instead of in
            // the same undifferentiated list.
            for (final ToolKind k in const <ToolKind>[
              ToolKind.ping,
              ToolKind.trace,
              ToolKind.discover,
            ])
              _row(context, l, skin, tools, k),
            SizedBox(height: skin.space.sectionGap),
            MmSectionHeader(l.toolsGroupDiagnostics),
            SizedBox(height: skin.space.rowGap),
            for (final ToolKind k in const <ToolKind>[
              ToolKind.stats,
              ToolKind.range,
              ToolKind.soak,
            ])
              _row(context, l, skin, tools, k),
          ],
        ),
      ),
    );
  }
}
