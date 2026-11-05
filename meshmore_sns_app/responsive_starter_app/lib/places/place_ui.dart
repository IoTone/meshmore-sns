// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import 'place.dart';

/// The icon a type token draws (`meshmore-places-spec.md` §4).
IconData placeIcon(PlaceType type) => switch (type) {
      PlaceType.hazard => Icons.warning_amber_rounded,
      PlaceType.water => Icons.water_drop_outlined,
      PlaceType.fuel => Icons.local_gas_station_outlined,
      PlaceType.med => Icons.medical_services_outlined,
      PlaceType.rally => Icons.flag_outlined,
      PlaceType.view => Icons.visibility_outlined,
      PlaceType.camp => Icons.park_outlined,
      PlaceType.look => Icons.place_outlined,
      PlaceType.other => Icons.push_pin_outlined,
    };

/// The colour a *type* draws while a report is unread. It comes from the skin's
/// own palette, so a place never introduces a literal colour; after the report
/// is opened the pin goes neutral, because knowledge the user has is not an
/// alarm.
Color placeTypeColour(MmSkin skin, PlaceType type) => switch (type) {
      PlaceType.hazard || PlaceType.med => skin.color.alert,
      PlaceType.water => skin.color.link,
      PlaceType.fuel || PlaceType.rally => skin.color.accent,
      PlaceType.view || PlaceType.camp => skin.color.ok,
      PlaceType.look || PlaceType.other => skin.color.fgMuted,
    };

/// The localised name of a type token.
String placeTypeLabel(AppLocalizations l, PlaceType type) => switch (type) {
      PlaceType.hazard => l.placeTypeHazard,
      PlaceType.water => l.placeTypeWater,
      PlaceType.fuel => l.placeTypeFuel,
      PlaceType.med => l.placeTypeMed,
      PlaceType.rally => l.placeTypeRally,
      PlaceType.view => l.placeTypeView,
      PlaceType.camp => l.placeTypeCamp,
      PlaceType.look => l.placeTypeLook,
      PlaceType.other => l.placeTypeOther,
    };

/// "4 h 12 m", "12 m", "3 d" — compact, because it sits under a pin.
String placeDurationText(Duration d) {
  final int days = d.inDays;
  final int hours = d.inHours % 24;
  final int minutes = d.inMinutes % 60;
  if (days > 0) {
    return hours == 0 ? '${days}d' : '${days}d ${hours}h';
  }
  if (hours > 0) {
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }
  if (minutes > 0) return '${minutes}m';
  return '${d.inSeconds}s';
}

/// The expiry line every surface shows (spec §12: the TTL is the feature).
String placeExpiryText(AppLocalizations l, Place place, DateTime now) {
  if (!place.isLiveAt(now)) return l.placeExpired;
  return l.placeExpiresIn(placeDurationText(place.remainingAt(now)));
}

/// The provenance phrase (spec §12 requires saying where the point came from).
String placeSourceText(AppLocalizations l, PlaceProvenance provenance) =>
    switch (provenance) {
      PlaceProvenance.gps => l.placeSourceGps,
      PlaceProvenance.phone => l.placeSourcePhone,
      PlaceProvenance.pinned => l.placeSourcePinned,
      PlaceProvenance.received => l.placeSourceReceived,
      PlaceProvenance.inferred => l.placeSourceInferred,
    };
