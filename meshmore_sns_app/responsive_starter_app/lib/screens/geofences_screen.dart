// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../geofence/geofence_controller.dart';
import '../geofence/geofence_create_sheet.dart';
import '../geofence/geofence_store.dart';
import '../maps/geofence_fit.dart';
import '../maps/map_view_state.dart';
import '../meshcore/meshcore_controller.dart';
import '../shell/shell_view_request.dart';
import '../places/place_create_sheet.dart';
import '../places/place_wiring.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import '../ui/mm_confirm.dart';
import '../ui/mm_scaffold.dart';
import '../util/mm_format.dart';

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

  /// The fence the map's label named, if the screen was opened from one.
  ///
  /// Read once: the fence stays marked for as long as the screen is open, so a
  /// reader who scrolls away and back does not lose the thing they came for.
  String? _focused;

  /// The search text. Only shown once there are more than a few fences: a
  /// search field over two rows is furniture.
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_focused != null) return;
    // The screen is also built outside a router (the skin tests render it as a
    // plain `MaterialApp` home), where there is no route to read a query from.
    if (GoRouter.maybeOf(context) == null) return;
    final String? id = GoRouterState.of(context).uri.queryParameters['id'];
    if (id != null && id.isNotEmpty) _focused = id;
  }

  /// The app-scoped view memory, however it was registered.
  ///
  /// `Provider.of<X?>` does not match a provider registered as `X` — the lookup
  /// that reads only the nullable spelling returns null in the app and works in
  /// whichever harness happens to use the nullable one. This tries the real
  /// registration first.
  static MapViewState? _viewState(BuildContext context) {
    try {
      return Provider.of<MapViewState>(context, listen: false);
    } on ProviderNotFoundException {
      try {
        return Provider.of<MapViewState?>(context, listen: false);
      } on ProviderNotFoundException {
        return null;
      }
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The fences the list should show, with the one the map named first.
  List<StoredGeofence> _visible(GeofenceController fences) {
    final String q = _search.text.trim().toLowerCase();
    final List<StoredGeofence> rows = <StoredGeofence>[
      for (final StoredGeofence f in fences.fences)
        if (q.isEmpty || f.label.toLowerCase().contains(q)) f,
    ];
    final String? focused = _focused;
    if (focused == null) return rows;
    final int at = rows.indexWhere((StoredGeofence f) => f.id == focused);
    if (at <= 0) return rows;
    // Opening a fence puts it at the top rather than scrolling to it: the list
    // is at most twenty rows, and "the first row is the one you asked for" needs
    // no scroll maths that break at a different text size.
    final StoredGeofence first = rows[at];
    rows.removeAt(at);
    return <StoredGeofence>[first, ...rows];
  }

  Future<void> _edit(GeofenceController fences, StoredGeofence fence) async {
    final ({String label, double radiusMeters})? made =
        await showModalBottomSheet<({String label, double radiusMeters})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => GeofenceCreateSheet(
        latitude: fence.latitude,
        longitude: fence.longitude,
        initialRadiusMeters: fence.radiusMeters,
        initialLabel: fence.label,
        editing: true,
        polygon: fence.polygon,
        // A drawn fence's corners are dragged on the map, so the sheet hands
        // the reader there instead of pretending a slider can express a corner.
        onReshape: () {
          _viewState(context)?.requestReshapeFence(fence.id);
          context.read<ShellViewRequest?>()?.openMap();
        },
      ),
    );
    if (made == null) return;
    await fences.updateFence(
      id: fence.id,
      label: made.label,
      radiusMeters: made.radiusMeters,
    );
  }

  /// Ask the shell for the map, with every fence in view.
  void _showAll(GeofenceController fences) {
    final Size size = MediaQuery.sizeOf(context);
    final ({LatLng centre, double zoom})? fit = fitGeofences(
      fences.fences,
      viewportPx: math.min(size.width, size.height),
    );
    if (fit == null) return;
    // The map takes the instruction and the shell switches to it. Both before
    // the pop, so the tab is already the map when this screen goes away.
    _viewState(context)?.requestView(centre: fit.centre, zoom: fit.zoom);
    // Registered as nullable in `main.dart`, so this spelling is the right one.
    context.read<ShellViewRequest?>()?.openMap();
    Navigator.of(context).pop();
  }

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
          padding: skin.space.padScreen,
          children: <Widget>[
            MmSectionHeader(l.geofenceAddSection),
            // A header is a label, not a container: without this the chips sat
            // against it while every other page leaves a row gap under one.
            SizedBox(height: skin.space.rowGap),
            Wrap(
              spacing: skin.space.step(2),
              children: <Widget>[
                for (final int r in GeofencesScreen.radii)
                  MmChoiceChip(
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
            Row(
              children: <Widget>[
                Expanded(child: MmSectionHeader(l.geofenceListSection)),
                // A list of fences is a list of places, and a list does not
                // answer "where are they". This is the one control that turns
                // the list back into the map it came from.
                if (fences.fences.isNotEmpty)
                  MmAction(
                    key: const ValueKey<String>('geofence-show-all'),
                    icon: Icons.map_outlined,
                    label: l.geofenceShowAll,
                    dense: true,
                    onPressed: () => _showAll(fences),
                  ),
              ],
            ),
            SizedBox(height: skin.space.rowGap),
            if (fences.fences.length > 3)
              Padding(
                padding: EdgeInsets.only(top: skin.space.step(2)),
                child: TextField(
                  key: const ValueKey<String>('geofence-search'),
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: l.geofenceSearchHint,
                    isDense: true,
                  ),
                ),
              ),
            if (fences.fences.isEmpty)
              // The one thing a reader cannot infer from an empty list: a fence
              // fires once on the way in and once on the way out, so walking its
              // edge does not produce a stream of alerts.
              Text(l.geofenceExplainer,
                  key: const ValueKey<String>('geofence-explainer'),
                  style: TextStyle(
                      color: skin.color.fgMuted,
                      fontSize: skin.type.sizeBody,
                      height: 1.5))
            else if (_visible(fences).isEmpty)
              Text(l.geofenceNoMatches,
                  key: const ValueKey<String>('geofence-no-matches'),
                  style: TextStyle(
                      color: skin.color.fgMuted, fontSize: skin.type.sizeSm))
            else
              for (final StoredGeofence f in _visible(fences))
                _FenceRow(
                  fence: f,
                  inside: fences.isInside(f.id),
                  focused: f.id == _focused,
                  onEdit: () => _edit(fences, f),
                  // Deleting a fence takes its crossings with it, and the same
                  // app asks before it resets a channel or restarts a radio.
                  // This was one tap with no question.
                  onDelete: () async {
                    final bool ok = await mmConfirm(
                      context,
                      title: l.geofenceDeleteConfirmTitle,
                      body: l.geofenceDeleteConfirmBody,
                      cancelLabel: l.actionCancel,
                      confirmLabel: l.geofenceDelete,
                      destructive: true,
                    );
                    if (ok) await fences.removeFence(f.id);
                  },
                  // A fence and a place are the same fact twice: a centre, a
                  // name, and how much ground it covers. A fence the crew should
                  // also see as a pin is one tap from being one.
                  onSaveAsPlace: () => PlaceCreateSheet.show(
                    context,
                    latitude: f.latitude,
                    longitude: f.longitude,
                    composer: placeComposerOf(context),
                    initialLabel: f.label,
                  ),
                ),
            if (fences.alerts.isNotEmpty) ...<Widget>[
              SizedBox(height: skin.space.step(5)),
              Row(
                children: <Widget>[
                  Expanded(child: MmSectionHeader(l.geofenceEventsSection)),
                  // The log is evidence, and evidence you cannot destroy is a
                  // liability. Deleting a fence clears its own crossings; this
                  // clears the history of the fences that remain.
                  MmAction(
                    key: const ValueKey<String>('geofence-clear-log'),
                    label: l.geofenceClearLog,
                    dense: true,
                    onPressed: () async {
                      final bool ok = await mmConfirm(
                        context,
                        title: l.geofenceClearLogConfirmTitle,
                        body: l.geofenceClearLogConfirmBody,
                        cancelLabel: l.actionCancel,
                        confirmLabel: l.geofenceClearLog,
                        destructive: true,
                      );
                      if (ok) await fences.clearAlerts();
                    },
                  ),
                ],
              ),
              // Newest first, with the time, because a crossing without a time
              // is an anecdote and the log is meant to answer "what happened
              // last night". The list is the store's own cap, so a morning after
              // is a scroll rather than a memory.
              for (final GeofenceAlert a in fences.alerts.reversed.take(40))
                Padding(
                  padding: EdgeInsets.only(bottom: skin.space.step(1)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: skin.space.step(9) * 2,
                        child: Text(
                          geofenceStamp(context, a.at),
                          style: TextStyle(
                            color: skin.color.fgMuted,
                            fontFamily: skin.type.monoFamily,
                            fontSize: skin.type.sizeSm,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          a.isEntry
                              ? l.geofenceEntered(a.fence.label)
                              : l.geofenceLeft(a.fence.label),
                          key: ValueKey<String>(
                              'geofence-event-${a.fence.id}-${a.at.millisecondsSinceEpoch}'),
                          style: TextStyle(
                              color: skin.color.fg,
                              fontSize: skin.type.sizeBody),
                        ),
                      ),
                    ],
                  ),
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
    required this.focused,
    required this.onEdit,
    required this.onDelete,
    required this.onSaveAsPlace,
  });

  final StoredGeofence fence;
  final bool inside;

  /// True when the map's own label opened this fence. It is marked rather than
  /// scrolled to, and it is first in the list, so the reader sees the one they
  /// tapped without hunting for it.
  final bool focused;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSaveAsPlace;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    return Container(
      key: ValueKey<String>('geofence-row-${fence.id}'),
      padding: EdgeInsets.symmetric(vertical: skin.space.step(2)),
      decoration: focused
          ? BoxDecoration(
              border: Border(
                left: BorderSide(color: skin.color.accent, width: 3),
              ),
            )
          : null,
      child: Row(
        children: <Widget>[
          Icon(
            // A drawn fence is a shape, not a point, and the row says which it
            // is before the reader opens it.
            fence.isPolygon
                ? (inside ? Icons.pentagon : Icons.pentagon_outlined)
                : (inside ? Icons.place : Icons.place_outlined),
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
                  fence.isPolygon
                      ? '${inside ? l.geofenceInsideNow : l.geofenceOutsideNow}'
                          ' · ${l.geofenceCorners(fence.polygon!.length)}'
                      : (inside ? l.geofenceInsideNow : l.geofenceOutsideNow),
                  key: ValueKey<String>('geofence-shape-${fence.id}'),
                  style: TextStyle(
                      color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
                ),
                if (focused)
                  Text(
                    l.geofenceFocused,
                    key: ValueKey<String>('geofence-focused-${fence.id}'),
                    style: TextStyle(
                        color: skin.color.accent, fontSize: skin.type.sizeSm),
                  ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey<String>('geofence-edit-${fence.id}'),
            tooltip: l.geofenceEdit,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: ValueKey<String>('geofence-as-place-${fence.id}'),
            tooltip: l.geofenceSaveAsPlace,
            onPressed: onSaveAsPlace,
            icon: const Icon(Icons.push_pin_outlined),
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

/// The time a crossing happened, in the reader's clock.
///
/// Today is the common case and gets the time alone. Anything older carries the
/// day, because a log read the next morning must not put yesterday's crossings
/// in the same column as this morning's.
String geofenceStamp(BuildContext context, DateTime at) {
  final DateTime now = DateTime.now();
  final String time = MmFormat.clock(at, prefs: context.formatPrefs);
  final bool today = at.year == now.year && at.month == now.month && at.day == now.day;
  if (today) return time;
  final String day =
      MaterialLocalizations.of(context).formatShortMonthDay(at);
  return '$day $time';
}
