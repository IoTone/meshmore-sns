// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/mesh_network.dart';
import '../meshcore/mesh_network_store.dart';
import '../meshcore/meshcore_controller.dart';
import '../ui/mm_components.dart';
import '../ui/mm_confirm.dart';
import '../ui/mm_scaffold.dart';
import 'networks_screen.dart';

/// One network: its settings, its members, and the action that puts the
/// connected radio on it.
class NetworkDetailScreen extends StatefulWidget {
  const NetworkDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<NetworkDetailScreen> createState() => _NetworkDetailScreenState();
}

class _NetworkDetailScreenState extends State<NetworkDetailScreen> {
  MeshNetwork? _net;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<MeshNetwork> all = await MeshNetworkStore.load();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _net = all.where((MeshNetwork n) => n.id == widget.id).firstOrNull;
    });
  }

  Future<void> _replace(MeshNetwork? next) async {
    final List<MeshNetwork> all = await MeshNetworkStore.load();
    await MeshNetworkStore.save(<MeshNetwork>[
      for (final MeshNetwork n in all)
        if (n.id != widget.id) n else if (next != null) next,
    ]);
    await _load();
  }

  /// A yes/no question about this network. [destructive] is for the delete:
  /// applying a network is a change, deleting one is a loss.
  Future<bool> _confirm(String title, String body, String yes,
      {bool destructive = false}) {
    final AppLocalizations l = AppLocalizations.of(context);
    return mmConfirm(
      context,
      title: title,
      body: body,
      cancelLabel: l.networksCancel,
      confirmLabel: yes,
      destructive: destructive,
    );
  }

  void _toast(String text) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(text),
      ));

  Future<void> _apply(MeshNetwork n, MeshcoreController mc) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String summary = networkSummary(l, n);
    final bool ok = await _confirm(
      l.networksApplyTitle(n.name),
      n.isolatedFromPublicMesh
          ? l.networksApplyBodyIsolated(summary)
          : l.networksApplyBodyShared(summary),
      l.networksApplyConfirm,
    );
    if (!ok || !mounted) return;
    try {
      for (final Uint8List f in n.framesToApply()) {
        await mc.send(f);
      }
      _toast(l.networksApplied);
    } catch (e) {
      _toast(l.networksApplyFailed('$e'));
    }
  }

  Future<void> _addMember(MeshNetwork n, MeshcoreController mc) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final Set<String> have =
        n.members.map((NetworkMember m) => m.publicKeyHex).toSet();
    final List<Contact> candidates = <Contact>[
      for (final Contact c in mc.syncedContacts)
        if (!have.contains(_hex(c.publicKey))) c,
    ];
    if (candidates.isEmpty) {
      _toast(l.networksNoContacts);
      return;
    }
    final Contact? picked = await showModalBottomSheet<Contact>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext s) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final Contact c in candidates)
              ListTile(
                key: Key('pick-${_hex(c.publicKey).substring(0, 8)}'),
                title: Text(c.name.isEmpty
                    ? _hex(c.publicKey).substring(0, 8)
                    : c.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(s, c),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _replace(n.copyWith(members: <NetworkMember>[
      ...n.members,
      NetworkMember(
        publicKeyHex: _hex(picked.publicKey),
        label: picked.name.isEmpty
            ? _hex(picked.publicKey).substring(0, 8)
            : picked.name,
      ),
    ]));
  }

  static String _hex(List<int> b) =>
      b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final MeshNetwork? n = _net;
    if (n == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.networksTitle)),
        body: _loaded ? const SizedBox() : const SizedBox(),
      );
    }
    final bool current = networkIsCurrent(mc, n);
    final TextStyle muted =
        TextStyle(color: cs.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: Text(n.name)),
      body: MmScaffold(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(networkSummary(l, n),
                key: const Key('network-summary'),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(networkReach(l, n),
                key: const Key('network-reach'),
                style: n.isolatedFromPublicMesh
                    ? muted
                    : TextStyle(color: cs.error)),
            if (current) ...<Widget>[
              const SizedBox(height: 8),
              Text(l.networksCurrent, key: const Key('network-current')),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('network-apply'),
              onPressed: mc.isReady ? () => _apply(n, mc) : null,
              child: Text(l.networksApply),
            ),
            if (!mc.isReady)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l.networksApplyNeedsRadio, style: muted),
              ),
            const SizedBox(height: 24),
            Text(l.networksMembers(n.members.length),
                style: Theme.of(context).textTheme.titleSmall),
            if (n.members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l.networksNoMembers, style: muted),
              ),
            for (final NetworkMember m in n.members)
              ListTile(
                key: Key('member-${m.shortKey}'),
                contentPadding: EdgeInsets.zero,
                title: Text(m.label),
                subtitle: Text(m.shortKey),
                trailing: MmAction(
                  label: l.networksRemoveMember,
                  dense: true,
                  onPressed: () => _replace(n.copyWith(members: <NetworkMember>[
                    for (final NetworkMember o in n.members)
                      if (o.publicKeyHex != m.publicKeyHex) o,
                  ])),
                ),
              ),
            MmAction(
              key: const Key('network-add-member'),
              onPressed: () => _addMember(n, mc),
              icon: Icons.person_add_alt,
              label: l.networksAddMember,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              key: const Key('network-delete'),
              onPressed: () async {
                final NavigatorState nav = Navigator.of(context);
                final bool ok = await _confirm(
                  l.networksDeleteTitle(n.name),
                  l.networksDeleteBody,
                  l.networksDeleteConfirm,
                  destructive: true,
                );
                if (!ok) return;
                await _replace(null);
                nav.pop();
              },
              child: Text(l.networksDelete),
            ),
          ],
        ),
      ),
    );
  }
}
