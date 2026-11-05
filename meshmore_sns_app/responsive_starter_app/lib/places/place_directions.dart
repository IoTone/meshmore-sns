// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'place.dart';

/// One way to open a pin in another app
/// (`meshmore-places-spec.md` §10, decision D8.10).
@immutable
final class DirectionsTarget {
  const DirectionsTarget({
    required this.labelKey,
    required this.uri,
    required this.generic,
  });

  /// Which string names this target; the sheet resolves it, so this file holds
  /// no user-facing English.
  final DirectionsTargetName labelKey;

  final Uri uri;

  /// True for the platform-neutral `geo:` intent, which is tried first because
  /// every map app on Android may claim it.
  final bool generic;
}

/// The target names in the decided order.
enum DirectionsTargetName { genericGeo, osmand, organic, google, apple }

/// Whether the platform can open a URI, and opening it.
///
/// Split from the ladder so the order can be tested without launching an
/// intent: a test drives a fake probe and asserts the sequence, which is the
/// part that can be wrong.
abstract interface class DirectionsProbe {
  Future<bool> canOpen(Uri uri);
  Future<bool> open(Uri uri);
}

/// The real probe over `url_launcher`. On Android 11+ a scheme is only found
/// when the manifest declares it in `<queries>`, which it does for these four:
/// without that, every third-party target silently disappears and the ladder
/// degrades to `geo:`.
final class SystemDirectionsProbe implements DirectionsProbe {
  const SystemDirectionsProbe();

  @override
  Future<bool> canOpen(Uri uri) async {
    try {
      return await canLaunchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

/// The ladder for one place, built in the decided order (D8.10): the generic
/// `geo:` intent first, then OsmAnd, Organic Maps, Google Maps and Apple Maps
/// where installed. The label rides in `q=` so a target that shows a pin also
/// shows what it is.
///
/// When nothing is installed the caller copies the coordinates instead of
/// failing: a place with no directions app is still a place.
@immutable
final class PlaceDirections {
  const PlaceDirections._(this.place);

  factory PlaceDirections.of(Place place) => PlaceDirections._(place);

  final Place place;

  String get _lat => place.latitude.toStringAsFixed(place.decimals);
  String get _lon => place.longitude.toStringAsFixed(place.decimals);
  String get _label => Uri.encodeComponent(place.label);

  /// The coordinates as a person would paste them.
  String get coordinatesText => '$_lat,$_lon';

  List<DirectionsTarget> get targets => <DirectionsTarget>[
        DirectionsTarget(
          labelKey: DirectionsTargetName.genericGeo,
          generic: true,
          uri: Uri.parse('geo:$_lat,$_lon?q=$_lat,$_lon($_label)'),
        ),
        DirectionsTarget(
          labelKey: DirectionsTargetName.osmand,
          generic: false,
          uri: Uri.parse('osmand://map?lat=$_lat&lon=$_lon&z=16'),
        ),
        DirectionsTarget(
          labelKey: DirectionsTargetName.organic,
          generic: false,
          uri: Uri.parse('om://$_lat,$_lon?n=$_label'),
        ),
        DirectionsTarget(
          labelKey: DirectionsTargetName.google,
          generic: false,
          uri: Uri.parse('https://www.google.com/maps?q=$_lat,$_lon($_label)'),
        ),
        DirectionsTarget(
          labelKey: DirectionsTargetName.apple,
          generic: false,
          uri: Uri.parse('https://maps.apple.com/?ll=$_lat,$_lon&q=$_label'),
        ),
      ];

  /// The first target the platform can open, or null when none can.
  Future<DirectionsTarget?> firstAvailable(DirectionsProbe probe) async {
    for (final DirectionsTarget t in targets) {
      if (await probe.canOpen(t.uri)) return t;
    }
    return null;
  }

  /// Opens the pin: the first available target, else the coordinates on the
  /// clipboard, which always works.
  Future<DirectionsOutcome> open(
    DirectionsProbe probe, {
    Future<void> Function(String text)? copy,
  }) async {
    final DirectionsTarget? target = await firstAvailable(probe);
    if (target != null && await probe.open(target.uri)) {
      return DirectionsOutcome.opened(target.labelKey);
    }
    await (copy ?? _copyToClipboard)(coordinatesText);
    return const DirectionsOutcome.copied();
  }

  static Future<void> _copyToClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

/// What happened when the user asked for directions.
@immutable
final class DirectionsOutcome {
  const DirectionsOutcome.opened(DirectionsTargetName this.target)
      : copied = false;

  const DirectionsOutcome.copied()
      : target = null,
        copied = true;

  /// The target that opened, or null when the coordinates were copied.
  final DirectionsTargetName? target;

  final bool copied;
}
