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
import '../ui/mm_components.dart';
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
                      // The other half of "who else is in this conversation": a
                      // network is the radio tuple, not a key. See the same line
                      // on Settings -> Channels.
                      Padding(
                        padding: EdgeInsets.only(
                            bottom: context.skin.space.rowGap),
                        child: Text(l.networksIntro,
                            style: TextStyle(
                                color: context.skin.color.fgMuted,
                                fontSize: context.skin.type.sizeSm)),
                      ),
                      SizedBox(height: context.skin.space.sectionGap),
                      MmSectionHeader(l.networksTitle),
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
  const NetworkEditScreen({super.key, this.initial});

  /// The network being edited, or null to create one.
  ///
  /// A network's settings are a written-down agreement and they change: a
  /// frequency typo used to mean deleting the network, which threw away its
  /// members and their history. Editing keeps the id and the members.
  final MeshNetwork? initial;

  @override
  State<NetworkEditScreen> createState() => _NetworkEditScreenState();
}

class _NetworkEditScreenState extends State<NetworkEditScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _freq = TextEditingController();
  late RegionPreset _preset = presetById('us_canada') ?? kRegionPresets.first;
  late int _hash = _preset.pathHashSize ?? 1;
  // The three radio fields and the power, carried explicitly once the reader
  // touches them: a preset fills them in, and any change makes the tuple the
  // reader's own rather than the preset's.
  late double _bandwidth = _preset.bandwidthKhz;
  late int _sf = _preset.spreadingFactor;
  late int _cr = _preset.codingRate;
  late int _tx = _preset.txPowerDbm;
  bool _custom = false;
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
    final MeshNetwork? edit = widget.initial;
    if (edit != null) {
      _name.text = edit.name;
      _freq.text = edit.frequencyMhz.toString();
      _private = edit.isolatedFromPublicMesh;
      _hash = edit.pathHashSize;
      _bandwidth = edit.bandwidthKhz;
      _sf = edit.spreadingFactor;
      _cr = edit.codingRate;
      _tx = edit.txPowerDbm;
      final RegionPreset? p = edit.overlappingPublicPreset;
      _custom = p == null;
      if (p != null) _preset = p;
      return;
    }
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

    // A name is how a reader tells two networks apart in a list, so two with the
    // same one are one network with two copies: refuse the second rather than
    // making the reader find out later.
    final List<MeshNetwork> existing = await MeshNetworkStore.load();
    if (nameError == null &&
        existing.any((MeshNetwork n) =>
            n.id != widget.initial?.id &&
            n.name.toLowerCase() == name.toLowerCase())) {
      nameError = l.networksNameTaken;
    }

    // The frequency starts at the preset's and is overridden below when the
    // reader typed one (a private network, or a custom tuple).
    double freq = _preset.frequencyMhz;
    if (_private || _custom) {
      final double? f = double.tryParse(_freq.text.trim());
      if (f == null || f < 150 || f > 2500) {
        freqError = l.networksFrequencyInvalid;
      } else {
        freq = f;
      }
    }
    MeshNetwork? net;
    if (nameError == null && freqError == null) {
      final MeshNetwork candidate = MeshNetwork(
        id: widget.initial?.id ?? 'n${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        frequencyMhz: freq,
        bandwidthKhz: _bandwidth,
        spreadingFactor: _sf,
        codingRate: _cr,
        txPowerDbm: _tx,
        pathHashSize: _hash,
        members: widget.initial?.members ?? const <NetworkMember>[],
      );
      final RegionPreset? clash = candidate.overlappingPublicPreset;
      // A frequency the reader typed, or a switch that claims privacy, has to
      // stand on its own: a tuple that lands on a public preset is not isolated
      // whatever the switch says, and the honest answer is that the frequency
      // cannot deliver privacy rather than a saved network that is public in
      // fact. Only a network that simply copies a preset is exempt, because it
      // never claimed otherwise.
      if ((_custom || _private) && clash != null) {
        freqError =
            l.networksFrequencyPublic(localizedPresetLabel(l, clash.id));
      }
      net = candidate;
    }
    if (nameError != null || freqError != null || net == null) {
      setState(() {
        _nameError = nameError;
        _freqError = freqError;
      });
      return;
    }
    final List<MeshNetwork> all = await MeshNetworkStore.load();
    await MeshNetworkStore.save(<MeshNetwork>[
      for (final MeshNetwork n in all)
        if (n.id != net.id) n,
      net,
    ]);
    if (mounted) Navigator.of(context).pop();
  }

  /// The transmit powers the field offers: every step the firmware accepts, plus
  /// whatever the loaded network or a preset already holds.
  List<int> _txChoices() {
    final Set<int> all = <int>{
      for (int dbm = -9; dbm <= 30; dbm += 3) dbm,
      _tx,
      if (widget.initial != null) widget.initial!.txPowerDbm,
      for (final RegionPreset p in kRegionPresets) p.txPowerDbm,
    };
    final List<int> out = all.toList()..sort();
    return out;
  }

  /// The bandwidths the field offers: the radio's own widths and every value a
  /// shipped preset uses, so a preset can always be shown in the control that
  /// describes it.
  static List<double> _bandwidthChoices() {
    final Set<double> all = <double>{
      7.8, 10.4, 15.6, 20.8, 31.25, 41.7, 62.5, 125, 250, 500,
      for (final RegionPreset p in kRegionPresets) p.bandwidthKhz,
    };
    final List<double> out = all.toList()..sort();
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TextStyle muted =
        TextStyle(color: context.skin.color.fgMuted);
    return Scaffold(
      appBar: AppBar(title: Text(l.networksNew)),
      body: MmScaffold(
        // The form scrolls, the save does not. The advanced section made this
        // list taller than a phone, and a save button at the end of a scroll is
        // a save button a reader has to hunt for — the app's other editors keep
        // their action row in reach.
        child: Column(
          children: <Widget>[
            Expanded(
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
                  // A preset is a whole tuple: choosing one replaces every radio
                  // field with it, and clears the custom flag because the tuple
                  // is now the preset's.
                  _bandwidth = p.bandwidthKhz;
                  _sf = p.spreadingFactor;
                  _cr = p.codingRate;
                  _tx = p.txPowerDbm;
                  _custom = false;
                  _private = false;
                  _freq.text = '';
                });
              },
            ),
            const SizedBox(height: 16),
            // The tuple itself, not just a preset label. A community network
            // that is not one of the shipped presets is the common case on a
            // busy mesh, and it used to be impossible to write down: the preset
            // decided bandwidth, spreading and coding rate, and there was no
            // field to disagree with it.
            Text(l.networksAdvanced,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<double>(
                    key: const Key('network-bandwidth'),
                    isExpanded: true,
                    initialValue: _bandwidth,
                    decoration:
                        InputDecoration(labelText: l.networksBandwidth),
                    // Every bandwidth this build can hold: the LoRa widths a
                    // radio offers, plus whatever the shipped presets use. A
                    // fixed list without the presets' own values meant a preset
                    // whose bandwidth was not in it (22 kHz) could not be shown
                    // in its own field, and the form threw before it drew.
                    items: <DropdownMenuItem<double>>[
                      for (final double bw in _bandwidthChoices())
                        DropdownMenuItem<double>(
                            value: bw, child: Text('${bw}kHz')),
                    ],
                    onChanged: (double? v) {
                      if (v == null) return;
                      setState(() {
                        _bandwidth = v;
                        _custom = true;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const Key('network-sf'),
                    isExpanded: true,
                    initialValue: _sf,
                    decoration: InputDecoration(labelText: l.networksSpreading),
                    items: <DropdownMenuItem<int>>[
                      for (int sf = 5; sf <= 12; sf++)
                        DropdownMenuItem<int>(value: sf, child: Text('SF$sf')),
                    ],
                    onChanged: (int? v) {
                      if (v == null) return;
                      setState(() {
                        _sf = v;
                        _custom = true;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const Key('network-cr'),
                    isExpanded: true,
                    initialValue: _cr,
                    decoration:
                        InputDecoration(labelText: l.networksCodingRate),
                    items: <DropdownMenuItem<int>>[
                      for (int cr = 5; cr <= 8; cr++)
                        DropdownMenuItem<int>(value: cr, child: Text('CR$cr')),
                    ],
                    onChanged: (int? v) {
                      if (v == null) return;
                      setState(() {
                        _cr = v;
                        _custom = true;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const Key('network-tx'),
                    isExpanded: true,
                    initialValue: _tx,
                    decoration:
                        InputDecoration(labelText: l.networksTxPower),
                    // Every power a preset or a radio may already hold. The
                    // list stepped by three from -9, which skipped 22 — the
                    // figure two shipped presets use — so opening the form on
                    // one of them threw before it drew.
                    items: <DropdownMenuItem<int>>[
                      for (final int dbm in _txChoices())
                        DropdownMenuItem<int>(
                            value: dbm, child: Text('$dbm dBm')),
                    ],
                    onChanged: (int? v) {
                      if (v == null) return;
                      setState(() => _tx = v);
                    },
                  ),
                ),
              ],
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
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  context.skin.space.screenEdge,
                  context.skin.space.rowGap,
                  context.skin.space.screenEdge,
                  context.skin.space.sectionGap),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('network-save'),
                  onPressed: _save,
                  child: Text(
                      widget.initial == null ? l.networksSave : l.networksEdit),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
