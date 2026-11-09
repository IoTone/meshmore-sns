// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../geofence/geofence_controller.dart';
import '../geofence/geofence_store.dart';
import '../meshcore/meshcore_controller.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';

/// Settings → Location → Geofences.
///
/// A fence is a circle on the map that reports one thing: you entered it, or
/// you left. The ±5 % hysteresis is not a hidden implementation detail, so the
/// screen states it: a fence fires once per stay, and walking along its edge
/// does not produce a stream of events.
class GeofencesScreen extends StatefulWidget {
  const GeofencesScreen({super.key});

  /// Radii offered. A fence is for a place a person recognises (a car park, a
  /// camp, a trailhead), so the list starts small and ends at a small town.
  static const List<int> radii = <int>[100, 250, 500, 1000, 2000];

  @override
  State<GeofencesScreen> createState() => _GeofencesScreenState();
}

class _GeofencesScreenState extends State<GeofencesScreen> {
  int _radius = 250;
  bool _adding = false;

  Future<void> _addHere(GeofenceController fences) async {
    final MeshcoreController mc = context.read<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final own = mc.ownLocation;
    if (own == null) return;
    setState(() => _adding = true);
    await fences.addFence(
      label: l.geofenceDefaultName(fences.fences.length + 1),
      latitude: own.latitude,
      longitude: own.longitude,
      radiusMeters: _radius.toDouble(),
    );
    if (!mounted) return;
    setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final GeofenceController fences = context.watch<GeofenceController>();
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final bool hasFix = mc.ownLocation != null;

    return Scaffold(
      appBar: AppBar(title: Text(l.geofenceTitle)),
      body: MmScaffold(
        child: ListView(
          padding: EdgeInsets.all(skin.space.step(5)),
          children: <Widget>[
            Text(
              l.geofenceExplainer,
              key: const ValueKey<String>('geofence-explainer'),
              style: TextStyle(
                  color: skin.color.fgMuted,
                  fontSize: skin.type.sizeBody,
                  height: 1.5),
            ),
            SizedBox(height: skin.space.step(4)),
            MmSectionHeader(l.geofenceAddSection),
            Wrap(
              spacing: skin.space.step(2),
              children: <Widget>[
                for (final int r in GeofencesScreen.radii)
                  ChoiceChip(
                    key: ValueKey<String>('geofence-radius-$r'),
                    label: Text(l.geofenceRadius(r)),
                    selected: _radius == r,
                    onSelected: (_) => setState(() => _radius = r),
                  ),
              ],
            ),
            SizedBox(height: skin.space.step(3)),
            if (!hasFix)
              Text(l.geofenceNeedsFix,
                  key: const ValueKey<String>('geofence-needs-fix'),
                  style:
                      TextStyle(
                          color: skin.color.alertInk,
                          fontSize: skin.type.sizeBody))
            else
              MmAction(
                key: const ValueKey<String>('geofence-add-here'),
                icon: Icons.add_location_alt_outlined,
                label: l.geofenceAddHere,
                onPressed: _adding ? null : () => _addHere(fences),
              ),
            SizedBox(height: skin.space.step(5)),
            MmSectionHeader(l.geofenceListSection),
            if (fences.fences.isEmpty)
              Text(l.geofenceEmpty,
                  key: const ValueKey<String>('geofence-empty'),
                  style: TextStyle(
                      color: skin.color.fgMuted, fontSize: skin.type.sizeSm))
            else
              for (final StoredGeofence f in fences.fences)
                _FenceRow(
                  fence: f,
                  inside: fences.isInside(f.id),
                  onDelete: () => fences.removeFence(f.id),
                ),
            if (fences.alerts.isNotEmpty) ...<Widget>[
              SizedBox(height: skin.space.step(5)),
              MmSectionHeader(l.geofenceEventsSection),
              for (final GeofenceAlert a in fences.alerts.reversed.take(10))
                Text(
                  a.isEntry
                      ? l.geofenceEntered(a.fence.label)
                      : l.geofenceLeft(a.fence.label),
                  key: ValueKey<String>(
                      'geofence-event-${a.fence.id}-${a.at.millisecondsSinceEpoch}'),
                  style: TextStyle(
                      color: skin.color.fg, fontSize: skin.type.sizeBody),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FenceRow extends StatelessWidget {
  const _FenceRow({
    required this.fence,
    required this.inside,
    required this.onDelete,
  });

  final StoredGeofence fence;
  final bool inside;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: skin.space.step(2)),
      child: Row(
        children: <Widget>[
          Icon(
            inside ? Icons.place : Icons.place_outlined,
            size: 20,
            color: inside ? skin.color.accent : skin.color.fgMuted,
          ),
          SizedBox(width: skin.space.step(2)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(fence.label,
                    key: ValueKey<String>('geofence-label-${fence.id}'),
                    style: TextStyle(
                        color: skin.color.fg, fontSize: skin.type.sizeBody)),
                Text(
                  inside ? l.geofenceInsideNow : l.geofenceOutsideNow,
                  style: TextStyle(
                      color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey<String>('geofence-delete-${fence.id}'),
            tooltip: l.geofenceDelete,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
