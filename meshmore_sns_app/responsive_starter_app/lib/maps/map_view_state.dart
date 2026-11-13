// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import 'map_centre.dart';

/// The map view the reader was looking at a moment ago.
///
/// There are two memories here, and they answer different questions.
///
/// [MapViewPrefs] is the long-term one. It survives a restart, because R90
/// decided that a deliberate basemap and a deliberate pan should not be thrown
/// away by closing the app. Do not delete it: it is the cold-start answer.
///
/// This is the short-term one. It survives a tab switch and nothing else, and it
/// exists because the resolve ladder put the phone fix above the saved view, so
/// switching to Chat and back re-centred on the reader and threw away where they
/// had panned. A view under [freshFor] now wins over the fix, and a view older
/// than that loses to it, which is what "keep it while I am using the app, forget
/// it once I have walked away" means in practice.
///
/// Nothing here is written to disk, so process death clears it by construction.
class MapViewState extends ChangeNotifier with WidgetsBindingObserver {
  MapViewState({DateTime Function()? clock, bool observeLifecycle = true})
      : _clock = clock ?? DateTime.now {
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
  }

  /// How long a remembered view stays authoritative.
  ///
  /// A minute is the owner's number: long enough to answer a message and come
  /// back, short enough that a phone in a pocket does not reopen on a place the
  /// reader has since walked away from.
  static const Duration freshFor = Duration(seconds: 60);

  final DateTime Function() _clock;

  LatLng? _centre;
  double? _zoom;
  String? _sourceId;
  DateTime? _stamp;

  /// The basemap the reader chose, while this session remembers it.
  ///
  /// Null means "nothing chosen this session", and the caller falls back to the
  /// disk preference and then to the skin's own basemap.
  String? get sourceId => _sourceId;

  /// The remembered view, or null when there is none or it has expired.
  SavedMapView? get freshView {
    final LatLng? c = _centre;
    final double? z = _zoom;
    final DateTime? at = _stamp;
    if (c == null || z == null || at == null) return null;
    if (_clock().difference(at) > freshFor) return null;
    return SavedMapView(latitude: c.latitude, longitude: c.longitude, zoom: z);
  }

  /// Whether a view is remembered and still authoritative.
  bool get isFresh => freshView != null;

  /// Remember where the camera is now.
  void remember({
    required LatLng centre,
    required double zoom,
    String? sourceId,
  }) {
    _centre = centre;
    _zoom = zoom;
    if (sourceId != null) _sourceId = sourceId;
    _stamp = _clock();
    notifyListeners();
  }

  /// Remember the basemap the reader picked, without touching the camera.
  void rememberSource(String id) {
    if (_sourceId == id) return;
    _sourceId = id;
    notifyListeners();
  }

  /// A camera another surface asked for, waiting to be taken.
  ///
  /// [remember] is a memory and this is an instruction, and they are different
  /// things. The memory answers "where was I"; the request answers "show me
  /// this", which arrives from a screen that is not the map (a fence list, a
  /// shared position) and has to survive until a map exists to obey it. It is
  /// taken once and cleared, so it can never fight a pan that happens after.
  ({LatLng centre, double zoom})? _request;

  /// Ask the map to look at [centre] at [zoom].
  void requestView({required LatLng centre, required double zoom}) {
    _request = (centre: centre, zoom: zoom);
    notifyListeners();
  }

  /// Take the pending request, if there is one.
  ///
  /// Whoever takes it owns it: the request is cleared here, so two maps — or a
  /// map and a preview — cannot both act on it.
  ({LatLng centre, double zoom})? takeRequest() {
    final ({LatLng centre, double zoom})? r = _request;
    _request = null;
    return r;
  }

  /// Forget everything. Called when the app leaves the foreground.
  void discard() {
    if (_centre == null && _zoom == null && _sourceId == null) return;
    _centre = null;
    _zoom = null;
    _sourceId = null;
    _stamp = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        discard();
      // `inactive` fires for the notification shade and for a permission
      // dialog, which are not "the reader left". Discarding there would forget
      // the view every time a system prompt appeared over the map.
      case AppLifecycleState.inactive:
      case AppLifecycleState.resumed:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
