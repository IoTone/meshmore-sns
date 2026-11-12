// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import 'package:meshcore/meshcore.dart' show SelfInfo, DeviceInfo;

import '../meshcore/mesh_network.dart';
import '../meshcore/mesh_network_store.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/region_presets.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_scaffold.dart';
import 'network_detail_screen.dart';

/// One-line radio summary, shared by the list, the detail and the confirm.
String networkSummary(AppLocalizations l, MeshNetwork n) => l.networksSummary(
      '${n.frequencyMhz}',
      '${n.bandwidthKhz}',
      '${n.spreadingFactor}',
      '${n.codingRate}',
      '${n.pathHashSize}',
    );

/// What the network shares the air with, in words. A key or a name never
/// separates radios on one frequency/bandwidth/SF, so a network on a public
/// tuple is NOT called private.
String networkReach(AppLocalizations l, MeshNetwork n) {
  final RegionPreset? p = n.overlappingPublicPreset;
  return p == null
      ? l.networksIsolated
      : l.networksShared(localizedPresetLabel(l, p.id));
}

/// Settings -> Networks: the radio settings a group of radios agree on.
class NetworksScreen extends StatefulWidget {
  const NetworksScreen({super.key});

  @override
  State<NetworksScreen> createState() => _NetworksScreenState();
}

class _NetworksScreenState extends State<NetworksScreen> {
  List<MeshNetwork>? _networks;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<MeshNetwork> n = await MeshNetworkStore.load();
    if (mounted) setState(() => _networks = n);
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(builder: (_) => page));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<MeshNetwork>? networks = _networks;
    final MeshcoreController mc = context.watch<MeshcoreController>();
    return Scaffold(
      appBar: AppBar(title: Text(l.networksTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('network-new'),
        onPressed: () => _open(const NetworkEditScreen()),
        icon: const Icon(Icons.add),
        label: Text(l.networksNew),
      ),
      body: MmScaffold(
        child: networks == null
            ? const SizedBox()
            : networks.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(context.skin.space.sectionGap),
                    // The muted tier, not ink at 60 %: that alpha is 3.9:1 on
                    // paper, under AA, and an empty state is the only thing on
                    // the screen when it shows.
                    child: Text(l.networksEmpty,
                        style: TextStyle(
                            color: context.skin.color.fgMuted)),
                  )
                : ListView(
                    padding: context.skin.space.padScreen,
                    children: <Widget>[
                      for (final MeshNetwork n in networks)
                        ListTile(
                          key: Key('network-${n.id}'),
                          title: Text(n.name),
                          subtitle: Text(
                              '${networkSummary(l, n)}\n${networkReach(l, n)}'),
                          isThreeLine: true,
                          trailing: networkIsCurrent(mc, n)
                              ? Icon(Icons.radio_button_checked,
                                  color: cs.primary)
                              : const Icon(Icons.chevron_right),
                          onTap: () => _open(NetworkDetailScreen(id: n.id)),
                        ),
                    ],
                  ),
      ),
    );
  }
}

/// Whether the connected radio is already on [n].
bool networkIsCurrent(MeshcoreController mc, MeshNetwork n) {
  final si = mc.selfInfo;
  final di = mc.deviceInfo;
  if (si == null || di == null) return false;
  return n.matches(
    frequencyMhz: si.frequencyMhz,
    bandwidthKhz: si.bandwidthKhz,
    spreadingFactor: si.spreadingFactor,
    pathHashSize: di.pathHashMode + 1,
  );
}

/// Create a network: a name, radio settings copied from a preset, a path hash
/// size, and optionally a private frequency.
class NetworkEditScreen extends StatefulWidget {
  const NetworkEditScreen({super.key});

  @override
  State<NetworkEditScreen> createState() => _NetworkEditScreenState();
}

class _NetworkEditScreenState extends State<NetworkEditScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _freq = TextEditingController();
  late RegionPreset _preset = presetById('us_canada') ?? kRegionPresets.first;
  late int _hash = _preset.pathHashSize ?? 1;
  bool _private = false;
  String? _nameError;
  String? _freqError;

  /// Start from what the radio is actually doing.
  ///
  /// A network records the settings a group of radios already agrees on, so the
  /// honest default is the connected radio's own tuple rather than a preset
  /// chosen for the reader. When that tuple is a published preset the preset is
  /// selected, so its label and the public-overlap test still apply. Nothing
  /// user-visible is randomised: a frequency nobody chose is a network nobody
  /// can join.
  @override
  void initState() {
    super.initState();
    final MeshcoreController? mc =
        Provider.of<MeshcoreController?>(context, listen: false);
    final SelfInfo? si = mc?.selfInfo;
    final DeviceInfo? di = mc?.deviceInfo;
    if (si == null) return;
    for (final RegionPreset p in kRegionPresets) {
      if (p.frequencyMhz == si.frequencyMhz &&
          p.bandwidthKhz == si.bandwidthKhz &&
          p.spreadingFactor == si.spreadingFactor &&
          p.codingRate == si.codingRate) {
        _preset = p;
        break;
      }
    }
    if (di != null) _hash = di.pathHashMode + 1;
  }

  @override
  void dispose() {
    _name.dispose();
    _freq.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String name = _name.text.trim();
    String? nameError;
    String? freqError;
    if (name.isEmpty) nameError = l.networksNameRequired;

    double freq = _preset.frequencyMhz;
    if (_private) {
      final double? f = double.tryParse(_freq.text.trim());
      if (f == null || f < 150 || f > 2500) {
        freqError = l.networksFrequencyInvalid;
      } else {
        freq = f;
      }
    }
    MeshNetwork? net;
    if (nameError == null && freqError == null) {
      net = MeshNetwork(
        id: 'n${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        frequencyMhz: freq,
        bandwidthKhz: _preset.bandwidthKhz,
        spreadingFactor: _preset.spreadingFactor,
        codingRate: _preset.codingRate,
        txPowerDbm: _preset.txPowerDbm,
        pathHashSize: _hash,
      );
      final RegionPreset? clash = net.overlappingPublicPreset;
      if (_private && clash != null) {
        freqError =
            l.networksFrequencyPublic(localizedPresetLabel(l, clash.id));
      }
    }
    if (nameError != null || freqError != null || net == null) {
      setState(() {
        _nameError = nameError;
        _freqError = freqError;
      });
      return;
    }
    final List<MeshNetwork> all = await MeshNetworkStore.load();
    await MeshNetworkStore.save(<MeshNetwork>[...all, net]);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TextStyle muted =
        TextStyle(color: context.skin.color.fgMuted);
    return Scaffold(
      appBar: AppBar(title: Text(l.networksNew)),
      body: MmScaffold(
        child: ListView(
          padding: context.skin.space.padScreen,
          children: <Widget>[
            TextField(
              key: const Key('network-name'),
              controller: _name,
              decoration: InputDecoration(
                  labelText: l.networksName, errorText: _nameError),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('network-preset'),
              isExpanded: true,
              initialValue: _preset.id,
              decoration: InputDecoration(labelText: l.networksPreset),
              items: <DropdownMenuItem<String>>[
                for (final RegionPreset p in kRegionPresets)
                  DropdownMenuItem<String>(
                    value: p.id,
                    child: Text(localizedPresetLabel(l, p.id),
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (String? id) {
                final RegionPreset? p = id == null ? null : presetById(id);
                if (p == null) return;
                setState(() {
                  _preset = p;
                  _hash = p.pathHashSize ?? _hash;
                });
              },
            ),
            const SizedBox(height: 16),
            Text(l.networksPathHash,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              key: const Key('network-hash'),
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 1, label: Text('1')),
                ButtonSegment<int>(value: 2, label: Text('2')),
                ButtonSegment<int>(value: 3, label: Text('3')),
              ],
              selected: <int>{_hash},
              onSelectionChanged: (Set<int> s) =>
                  setState(() => _hash = s.first),
            ),
            SwitchListTile(
              key: const Key('network-private'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.networksPrivateSwitch),
              subtitle: Text(l.networksPrivateHelp, style: muted),
              value: _private,
              onChanged: (bool v) => setState(() {
                _private = v;
                _freqError = null;
              }),
            ),
            if (_private)
              TextField(
                key: const Key('network-frequency'),
                controller: _freq,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: l.networksFrequency, errorText: _freqError),
              ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('network-save'),
              onPressed: _save,
              child: Text(l.networksSave),
            ),
          ],
        ),
      ),
    );
  }
}
