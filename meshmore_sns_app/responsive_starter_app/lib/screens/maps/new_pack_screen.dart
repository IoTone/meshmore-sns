// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../maps/map_source.dart';
import '../../maps/maps_controller.dart';
import '../../maps/tile_math.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../ui/mm_scaffold.dart';
import '../tools/tool_widgets.dart';
import 'maps_screen.dart';

/// R61 — choose a source, an area and a zoom range; see the cost
/// before anything downloads.
class NewPackScreen extends StatefulWidget {
  const NewPackScreen({super.key});

  static const List<double> radiiKm = <double>[1, 2, 5, 10, 25, 50];
  static const List<int> zooms = <int>[
    6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17
  ];

  @override
  State<NewPackScreen> createState() => _NewPackScreenState();
}

class _NewPackScreenState extends State<NewPackScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _latLon = TextEditingController();
  String? _sourceId;
  bool _useMine = true;
  double _radiusKm = 5;
  int _minZ = 10;
  int _maxZ = 15;
  int _keep = 0;
  bool _busy = false;
  PackRefusal? _refused;

  @override
  void dispose() {
    _name.dispose();
    _latLon.dispose();
    super.dispose();
  }

  (double, double)? _parseLatLon(String s) {
    final List<String> parts = s.split(RegExp(r'[,\s]+'))
      ..removeWhere((String p) => p.isEmpty);
    if (parts.length != 2) return null;
    final double? lat = double.tryParse(parts[0]);
    final double? lon = double.tryParse(parts[1]);
    if (lat == null || lon == null || lat.abs() > 85 || lon.abs() > 180) {
      return null;
    }
    return (lat, lon);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MapsController maps = context.watch<MapsController>();
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final List<MapSource> packable =
        maps.sources.where((MapSource s) => s.allowsPacks).toList();
    final MapSource? source = packable.isEmpty
        ? null
        : packable.firstWhere((MapSource s) => s.id == _sourceId,
            orElse: () => packable.first);

    final double? myLat = mc.ownLocation?.latitude;
    final double? myLon = mc.ownLocation?.longitude;
    final bool haveMine = myLat != null && myLon != null;
    final bool mine = _useMine && haveMine;
    final (double, double)? centre =
        mine ? (myLat, myLon) : _parseLatLon(_latLon.text);

    final int maxZ =
        source == null ? _maxZ : _maxZ.clamp(_minZ, source.maxNativeZoom);
    final GeoBox? box =
        centre == null ? null : GeoBox.around(centre.$1, centre.$2, _radiusKm);
    final PackRefusal? check = source == null || box == null
        ? null
        : maps.checkPack(
            name: _name.text,
            source: source,
            box: box,
            minZoom: _minZ,
            maxZoom: maxZ);
    // An empty name just keeps the button off; no need to nag.
    final PackRefusal? shown =
        _refused ?? (check == PackRefusal.noName ? null : check);

    return Scaffold(
      appBar: AppBar(title: Text(l.mapsAddPack)),
      body: MmScaffold(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: <Widget>[
            if (!maps.online) ...<Widget>[
              ToolNotice(text: l.mapsOffline, icon: Icons.cloud_off),
              const SizedBox(height: 12),
            ],
            if (source == null)
              ToolNotice(text: l.newPackNoSource, icon: Icons.info_outline)
            else ...<Widget>[
              TextField(
                controller: _name,
                enabled: !_busy,
                decoration: InputDecoration(labelText: l.newPackName),
                onChanged: (_) => setState(() => _refused = null),
              ),
              const SizedBox(height: 8),
              ToolField(
                label: l.newPackSource,
                child: ToolChoice<String>(
                  value: source.id,
                  values: <String>[for (final MapSource s in packable) s.id],
                  label: (String id) =>
                      packable.firstWhere((MapSource s) => s.id == id).name,
                  enabled: !_busy,
                  onChanged: (String id) => setState(() {
                    _sourceId = id;
                    _refused = null;
                  }),
                ),
              ),
              ToolField(
                label: l.newPackCenter,
                child: haveMine
                    ? Row(children: <Widget>[
                        Checkbox(
                          value: _useMine,
                          onChanged: _busy
                              ? null
                              : (bool? v) =>
                                  setState(() => _useMine = v ?? true),
                        ),
                        Flexible(
                            child: Text(l.newPackMyLocation,
                                overflow: TextOverflow.ellipsis)),
                      ])
                    : Text(l.newPackNoLocation,
                        style: const TextStyle(fontSize: 12)),
              ),
              if (!mine)
                TextField(
                  controller: _latLon,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                      signed: true, decimal: true),
                  decoration: InputDecoration(
                      labelText: l.newPackLatLon, hintText: '40.7861, -119.2065'),
                  onChanged: (_) => setState(() => _refused = null),
                ),
              ToolField(
                label: l.newPackRadius,
                child: ToolChoice<double>(
                  value: _radiusKm,
                  values: NewPackScreen.radiiKm,
                  label: (double km) => '${km.toStringAsFixed(0)} km',
                  enabled: !_busy,
                  onChanged: (double v) => setState(() {
                    _radiusKm = v;
                    _refused = null;
                  }),
                ),
              ),
              ToolField(
                label: l.newPackZoomFrom,
                child: ToolChoice<int>(
                  value: _minZ,
                  values: NewPackScreen.zooms,
                  label: (int z) => '$z',
                  enabled: !_busy,
                  onChanged: (int z) => setState(() {
                    _minZ = z;
                    if (_maxZ < z) _maxZ = z;
                    _refused = null;
                  }),
                ),
              ),
              ToolField(
                label: l.newPackZoomTo,
                child: ToolChoice<int>(
                  value: maxZ,
                  values: <int>[
                    for (final int z in NewPackScreen.zooms)
                      if (z >= _minZ && z <= source.maxNativeZoom) z
                  ],
                  label: (int z) => '$z',
                  enabled: !_busy,
                  onChanged: (int z) => setState(() {
                    _maxZ = z;
                    _refused = null;
                  }),
                ),
              ),
              ToolField(
                label: l.newPackKeep,
                child: ToolChoice<int>(
                  value: _keep,
                  values: MapsController.keepChoicesDays,
                  label: (int d) => keepLabel(l, d),
                  enabled: !_busy,
                  onChanged: (int d) => setState(() => _keep = d),
                ),
              ),
              const SizedBox(height: 8),
              if (box != null)
                ToolLine(l.newPackEstimate(
                    tileCount(box, _minZ, maxZ),
                    fmtBytes(maps.estimateBytes(source, box, _minZ, maxZ)))),
              if (shown != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ToolNotice(
                      text: packRefusalText(l, shown),
                      icon: Icons.error_outline),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: Text(_busy ? l.mapsWorking : l.newPackCreate),
                  onPressed: _busy || box == null || check != null
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          final PackRefusal? why = await maps.createPack(
                            name: _name.text,
                            source: source,
                            box: box,
                            minZoom: _minZ,
                            maxZoom: maxZ,
                            keepDays: _keep,
                          );
                          if (!context.mounted) return;
                          if (why == null) {
                            Navigator.of(context).pop();
                          } else {
                            setState(() {
                              _busy = false;
                              _refused = why;
                            });
                          }
                        },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
