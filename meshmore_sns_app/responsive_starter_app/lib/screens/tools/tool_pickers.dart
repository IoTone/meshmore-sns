// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:meshcore/meshcore.dart';

import '../../bot/bot_scope.dart';
import '../../gen/app_localizations.dart';
import '../../meshcore/discovered_node.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../tools/mesh_tool.dart';
import '../../tools/soak_tool.dart' show scopeRefusal;
import 'tool_widgets.dart';

IconData nodeTypeIcon(int type) => switch (type) {
      kAdvTypeRepeater => Icons.cell_tower,
      kAdvTypeRoom => Icons.meeting_room_outlined,
      kAdvTypeSensor => Icons.sensors,
      _ => Icons.person_outline,
    };

String hopsLabel(AppLocalizations l, DiscoveredNode n) => n.viaFlood
    ? l.nodeDetailHopsFlood
    : switch (n.hopCount) {
        null => l.nodeDetailHopsUnknown,
        0 => l.nodeDetailHopsDirect,
        final int h => l.nodeDetailHopsViaRepeaters(h),
      };

/// Synced contacts, repeaters first, then by last heard. [enabled]
/// greys out the ones a tool can't use, with [reason] saying why.
Future<DiscoveredNode?> pickContact(
  BuildContext context,
  MeshcoreController mc, {
  bool Function(DiscoveredNode n)? enabled,
  String? reason,
}) {
  final AppLocalizations l = AppLocalizations.of(context);
  final String? own = mc.ownPubKeyHex;
  final List<DiscoveredNode> nodes = <DiscoveredNode>[
    for (final DiscoveredNode n in mc.nodes)
      if (n.pubKeyHex != own && mc.isSyncedContact(n.pubKeyHex)) n,
  ]..sort((DiscoveredNode a, DiscoveredNode b) {
      int rank(DiscoveredNode n) =>
          n.type == kAdvTypeRepeater || n.type == kAdvTypeRoom ? 0 : 1;
      final int r = rank(a).compareTo(rank(b));
      return r != 0 ? r : b.lastHeardUnix.compareTo(a.lastHeardUnix);
    });
  return showModalBottomSheet<DiscoveredNode>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * .7),
        child: nodes.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.pingNoContacts),
              )
            : ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final DiscoveredNode n in nodes)
                    Builder(builder: (BuildContext _) {
                      final bool ok = enabled?.call(n) ?? true;
                      return ListTile(
                        enabled: ok,
                        leading: Icon(nodeTypeIcon(n.type)),
                        title: Text(n.name.isEmpty
                            ? n.pubKeyHex.substring(0, 8)
                            : n.name),
                        subtitle: Text(ok || reason == null
                            ? '${n.pubKeyHex.substring(0, 6)} · ${hopsLabel(l, n)}'
                            : reason),
                        onTap: () => Navigator.pop(ctx, n),
                      );
                    }),
                ],
              ),
      ),
    ),
  );
}

/// A conversation for Soak (channels + DM contacts) or Range test
/// (channels only). Public and unknown-key slots are listed disabled
/// with the reason — the refusal is visible, not hidden (spec rule 2).
Future<(BotScope, String)?> pickConversation(
  BuildContext context,
  MeshcoreController mc, {
  bool includeDms = true,
}) {
  final AppLocalizations l = AppLocalizations.of(context);
  final String? own = mc.ownPubKeyHex;
  final List<DiscoveredNode> peers = includeDms
      ? <DiscoveredNode>[
          for (final DiscoveredNode n in mc.nodes)
            if (n.pubKeyHex != own &&
                n.type == kAdvTypeChat &&
                mc.isSyncedContact(n.pubKeyHex))
              n,
        ]
      : const <DiscoveredNode>[];
  return showModalBottomSheet<(BotScope, String)>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * .7),
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final MapEntry<int, String> ch in mc.channels)
              Builder(builder: (BuildContext _) {
                final ChannelScope scope = ChannelScope(ch.key);
                final ToolFailure? why = scopeRefusal(scope, mc.channelPsk);
                final String label = '#${ch.key} ${ch.value}';
                return ListTile(
                  enabled: why == null,
                  leading: const Icon(Icons.tag),
                  title: Text(label),
                  subtitle: why == null ? null : Text(toolFailureText(l, why)),
                  onTap: () => Navigator.pop(ctx, (scope, label)),
                );
              }),
            if (peers.isNotEmpty) const Divider(),
            for (final DiscoveredNode n in peers)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(n.name),
                subtitle: Text(hopsLabel(l, n)),
                onTap: () =>
                    Navigator.pop(ctx, (DmScope(n.pubKeyHex), l.soakDm(n.name))),
              ),
          ],
        ),
      ),
    ),
  );
}
