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
import '../../ui/mm_components.dart';
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
    // The shape `showMmPicker` already uses everywhere in this app: ONE
    // shrink-wrapped ListView as the sheet's direct child, with the filter as
    // its first item. `MmSheetBody` lifts it above the keyboard, which this
    // sheet opens the moment the filter is tapped.
    builder: (BuildContext ctx) => MmSheetBody(
      child: nodes.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l.pingNoContacts),
            )
          : ContactPickerSheet(
              nodes: nodes,
              l: l,
              enabled: enabled,
              reason: reason,
            ),
    ),
  );
}

/// Channels first, then direct conversations, filtered by the same rule the
/// contact sheet uses. It is a StatefulWidget so the filter can rebuild the list
/// without rebuilding the whole sheet.
class _ConversationSheet extends StatefulWidget {
  const _ConversationSheet({
    required this.channels,
    required this.peers,
    required this.l,
    required this.pskOf,
  });

  final List<MapEntry<int, String>> channels;
  final List<DiscoveredNode> peers;
  final AppLocalizations l;
  final List<int>? Function(int idx) pskOf;

  @override
  State<_ConversationSheet> createState() => _ConversationSheetState();
}

class _ConversationSheetState extends State<_ConversationSheet> {
  final TextEditingController _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String q = _filter.text.trim().toLowerCase();
    final List<MapEntry<int, String>> channels = <MapEntry<int, String>>[
      for (final MapEntry<int, String> ch in widget.channels)
        if (q.isEmpty ||
            '#${ch.key}'.contains(q) ||
            ch.value.toLowerCase().contains(q))
          ch,
    ];
    final List<DiscoveredNode> peers = <DiscoveredNode>[
      for (final DiscoveredNode n in widget.peers)
        if (q.isEmpty ||
            n.name.toLowerCase().contains(q) ||
            n.pubKeyHex.toLowerCase().startsWith(q))
          n,
    ];
    return ListView(
      shrinkWrap: true,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            key: const ValueKey<String>('conversation-filter'),
            controller: _filter,
            onChanged: (String _) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.l.contactFilterHint,
              prefixIcon: const Icon(Icons.search, size: 18),
            ),
          ),
        ),
        if (channels.isEmpty && peers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(widget.l.contactFilterNone),
          ),
        for (final MapEntry<int, String> ch in channels)
          Builder(builder: (BuildContext ctx) {
            final ChannelScope scope = ChannelScope(ch.key);
            final ToolFailure? why = scopeRefusal(scope, widget.pskOf);
            final String label = '#${ch.key} ${ch.value}';
            return ListTile(
              enabled: why == null,
              leading: const Icon(Icons.tag),
              title: Text(label),
              subtitle:
                  why == null ? null : Text(toolFailureText(widget.l, why)),
              onTap: () => Navigator.pop(ctx, (scope, label)),
            );
          }),
        if (peers.isNotEmpty && channels.isNotEmpty) const Divider(),
        for (final DiscoveredNode n in peers)
          Builder(builder: (BuildContext ctx) {
            return ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(n.name),
              subtitle: Text(hopsLabel(widget.l, n)),
              onTap: () => Navigator.pop(
                  ctx, (DmScope(n.pubKeyHex), widget.l.soakDm(n.name))),
            );
          }),
      ],
    );
  }
}

/// The picker's filter, as a pure function so the rule can be tested without
/// building a sheet: a name matches anywhere in it (a user remembers "T-Deck"),
/// a key matches from its start (a user reads the prefix off another screen).
List<DiscoveredNode> filterContacts(
    List<DiscoveredNode> nodes, String query) {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) return nodes;
  return <DiscoveredNode>[
    for (final DiscoveredNode n in nodes)
      if (n.name.toLowerCase().contains(q) ||
          n.pubKeyHex.toLowerCase().startsWith(q))
        n,
  ];
}

/// The picker's body: a filter and the rows.
///
/// A synced radio holds a couple of hundred contacts, so the list arrived as
/// one undifferentiated scroll and finding a node meant dragging for a while.
/// The filter matches a name or the hex prefix a user reads off another screen,
/// and it is a plain `TextField` rather than a search sheet because the list is
/// right there behind it.
class ContactPickerSheet extends StatefulWidget {
  const ContactPickerSheet({
    super.key,
    required this.nodes,
    required this.l,
    this.enabled,
    this.reason,
  });

  final List<DiscoveredNode> nodes;
  final AppLocalizations l;
  final bool Function(DiscoveredNode n)? enabled;
  final String? reason;

  @override
  State<ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<ContactPickerSheet> {
  final TextEditingController _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<DiscoveredNode> get _shown =>
      filterContacts(widget.nodes, _filter.text);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = widget.l;
    final List<DiscoveredNode> shown = _shown;
    return ListView(
      shrinkWrap: true,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            key: const ValueKey<String>('contact-filter'),
            controller: _filter,
            onChanged: (String _) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              hintText: l.contactFilterHint,
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _filter.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l.actionClear,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(_filter.clear),
                    ),
            ),
          ),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l.contactFilterNone),
          )
        else
          for (final DiscoveredNode n in shown)
            Builder(builder: (BuildContext ctx) {
              final bool ok = widget.enabled?.call(n) ?? true;
              return ListTile(
                enabled: ok,
                leading: Icon(nodeTypeIcon(n.type)),
                title: Text(n.name.isEmpty
                    ? n.pubKeyHex.substring(0, 8)
                    : n.name),
                subtitle: Text(ok || widget.reason == null
                    ? '${n.pubKeyHex.substring(0, 6)} · ${hopsLabel(l, n)}'
                    : widget.reason!),
                onTap: () => Navigator.pop(ctx, n),
              );
            }),
      ],
    );
  }
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
  final List<DiscoveredNode> allPeers = includeDms
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
    // Same shape as the contact sheet, for the same measured reason: one
    // shrink-wrapped list as the sheet's direct child, lifted above the
    // keyboard its own filter opens.
    builder: (BuildContext ctx) => MmSheetBody(
      child: _ConversationSheet(
        channels: mc.channels,
        peers: allPeers,
        l: l,
        pskOf: mc.channelPsk,
      ),
    ),
  );
}
