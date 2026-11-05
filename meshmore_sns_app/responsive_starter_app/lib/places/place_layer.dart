// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import 'place.dart';
import 'place_store.dart';
import 'place_ui.dart';

/// The places drawn over the map (`meshmore-places-spec.md` §10).
///
/// Three rules from the spec live here rather than in the caller:
///
/// * **A pin leaves the layer at its expiry.** [PlaceStore.live] answers, so a
///   dead report cannot be drawn by accident; it moves to the history list
///   with its final state instead.
/// * **Colour until tapped, neutral after.** An unread pin is a report the user
///   has not seen; once opened it is knowledge they have. The colour comes from
///   the type through the skin's own palette — never a literal.
/// * **Clusters below the zoom where pins would overlap.** A cluster says how
///   many places it holds and opens the map onto them.
///
/// The countdown under each pin is rebuilt on a timer, so "expires in 12 m"
/// keeps being true while the map is open.
class PlaceLayer extends StatefulWidget {
  const PlaceLayer({
    super.key,
    required this.store,
    required this.onOpen,
    required this.onClusterTap,
    this.now,
  });

  final PlaceStore store;
  final void Function(Place place) onOpen;
  final void Function(LatLng centre) onClusterTap;

  /// Test seam: a fixed clock instead of the wall clock.
  final DateTime Function()? now;

  /// Below this zoom a bucket of places becomes one marker.
  static const double clusterZoom = 14;

  @override
  State<PlaceLayer> createState() => _PlaceLayerState();
}

class _PlaceLayerState extends State<PlaceLayer> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // 30 s is enough for a badge that shows minutes, and it is the same
    // cadence the rest of the app uses for age text.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MmSkin skin = context.skin;
    final DateTime now = (widget.now ?? DateTime.now)();
    final double zoom = MapCamera.of(context).zoom;
    final List<Place> live = widget.store.live(now);
    final Map<String, List<Place>> buckets = _bucket(live, zoom);
    return MarkerLayer(
      markers: <Marker>[
        for (final MapEntry<String, List<Place>> e in buckets.entries)
          if (e.value.length == 1)
            _pin(skin, now, e.value.single, AppLocalizations.of(context))
          else
            _cluster(skin, e.value, AppLocalizations.of(context)),
      ],
    );
  }

  Marker _pin(MmSkin skin, DateTime now, Place place, AppLocalizations l) {
    final bool seen = widget.store.isSeen(place.id);
    final Color colour =
        seen ? skin.color.fgMuted : placeTypeColour(skin, place.type);
    return Marker(
      point: LatLng(place.latitude, place.longitude),
      width: 84,
      height: 56,
      alignment: Alignment.center,
      // A pin draws its own hit area, so nothing announces it to a screen
      // reader without this: the label the user gave it, and how long it lasts.
      child: Semantics(
        button: true,
        label: l.placePinSemantics(
            place.label, placeDurationText(place.remainingAt(now))),
        child: GestureDetector(
          key: ValueKey<String>('place-pin-${place.id}'),
          onTap: () {
            widget.store.markSeen(place.id);
            widget.onOpen(place);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(placeIcon(place.type), size: 24, color: colour),
              Text(
                placeDurationText(place.remainingAt(now)),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: skin.color.fgMuted,
                  fontFamily: skin.type.monoFamily,
                  fontSize: skin.type.sizeMicro,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Marker _cluster(MmSkin skin, List<Place> places, AppLocalizations l) {
    double lat = 0;
    double lon = 0;
    for (final Place p in places) {
      lat += p.latitude;
      lon += p.longitude;
    }
    final LatLng centre = LatLng(lat / places.length, lon / places.length);
    return Marker(
      point: centre,
      width: 64,
      height: 64,
      alignment: Alignment.center,
      child: Semantics(
        button: true,
        label: l.placeClusterSemantics(places.length),
        child: GestureDetector(
          key: ValueKey<String>('place-cluster-${places.first.id}'),
          onTap: () => widget.onClusterTap(centre),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: skin.color.surfaceAlt,
              border: Border.all(color: skin.color.accent),
            ),
            child: Center(
              child: Text(
                '${places.length}',
                style: TextStyle(
                  color: skin.color.fg,
                  fontFamily: skin.type.monoFamily,
                  fontSize: skin.type.sizeBody,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Groups pins that would land on top of each other. The tolerance is a
  /// fraction of the visible span, so a cluster is a screen-space idea rather
  /// than a fixed distance; at [PlaceLayer.clusterZoom] and above every place
  /// gets its own pin.
  ///
  /// Greedy rather than a fixed grid: a grid puts two places a metre apart in
  /// different cells whenever a cell boundary falls between them, which is
  /// exactly the overlap the cluster exists to remove.
  static Map<String, List<Place>> _bucket(List<Place> places, double zoom) {
    if (zoom >= PlaceLayer.clusterZoom) {
      return <String, List<Place>>{
        for (final Place p in places)
          'p:${p.id}:${p.latE6}:${p.lonE6}': <Place>[p],
      };
    }
    final double cell = 360 / math.pow(2, zoom + 1);
    final List<List<Place>> clusters = <List<Place>>[];
    for (final Place p in places) {
      List<Place>? home;
      for (final List<Place> cluster in clusters) {
        final Place first = cluster.first;
        if ((first.latitude - p.latitude).abs() <= cell &&
            (first.longitude - p.longitude).abs() <= cell) {
          home = cluster;
          break;
        }
      }
      if (home == null) {
        clusters.add(<Place>[p]);
      } else {
        home.add(p);
      }
    }
    return <String, List<Place>>{
      for (int i = 0; i < clusters.length; i++)
        'c:$i:${clusters[i].first.id}': clusters[i],
    };
  }
}
