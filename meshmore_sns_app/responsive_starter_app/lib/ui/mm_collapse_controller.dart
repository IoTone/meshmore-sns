// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../util/prefs.dart';

/// R65 — every collapsible group's stable id.
///
/// An id is a fixed English token, never the localised title (so a
/// Japanese and an English user share the same persisted state) and
/// never an index (so reordering a screen cannot swap two groups'
/// states). The set is closed: a stored id that is not listed here is a
/// removed or renamed group and is dropped on load, so the stored map
/// cannot grow without bound. Adding a group means adding its id here;
/// `test/ui/mm_collapse_controller_test.dart` fails if a screen uses an
/// id that is not listed or lists one that no screen uses.
abstract final class MmGroupIds {
  // location_settings_screen.dart
  static const String locAutoPublish = 'location.autoPublish';
  static const String locBeacon = 'location.beacon';
  static const String locManual = 'location.manual';
  // device_config_screen.dart
  static const String devRadio = 'device.radio';
  static const String devIdentity = 'device.identity';
  static const String devOther = 'device.other';
  static const String devDevice = 'device.device';
  static const String devContacts = 'device.contacts';
  // personalization_screen.dart
  static const String persPreset = 'personalization.preset';
  static const String persAccessibility = 'personalization.accessibility';
  static const String persType = 'personalization.type';
  static const String persAudio = 'personalization.audio';
  // app_settings_screen.dart — storage, so a user can fold it away.
  static const String persStorage = 'settings.storage';
  // channel_create_sheet.dart — slot and pasted key.
  static const String channelAdvanced = 'channel.advanced';

  // app_settings_screen.dart — the radio's pairing PIN.
  static const String persSecurity = 'settings.security';
  // diagnostics_screen.dart
  static const String diagnosticsDeveloper = 'diagnostics.developer';
  // dashboard_screen.dart — the monolith most skins inherit.
  static const String dashRadio = 'dashboard.radio';
  static const String dashLocation = 'dashboard.location';
  static const String dashRecent = 'dashboard.recent';
  static const String dashBattery = 'dashboard.battery';
  // studio_dashboard.dart (R68) — its own ids, not the monolith's. Both
  // layouts fill the same slot and swap in one frame when the skin changes,
  // so a shared id trips the per-screen duplicate guard for a frame; the two
  // dashboards also fold different blocks, so their state is not the same
  // state.
  static const String studioRadio = 'studio.radio';
  static const String studioLocation = 'studio.location';
  static const String studioRecent = 'studio.recent';

  static const Set<String> all = <String>{
    channelAdvanced,
    locAutoPublish,
    locBeacon,
    locManual,
    devRadio,
    devIdentity,
    devOther,
    devDevice,
    devContacts,
    diagnosticsDeveloper,
    persPreset,
    persAccessibility,
    persType,
    persAudio,
    persStorage,
    persSecurity,
    dashRadio,
    dashLocation,
    dashRecent,
    dashBattery,
    studioRadio,
    studioLocation,
    studioRecent,
  };
}

/// R65 — remembers which collapsible groups the user folded, across
/// visits and app restarts.
///
/// Follows the app's controller convention (`ThemeController`,
/// `LocaleController`): a `ChangeNotifier` provided at the root, backed by
/// `shared_preferences`, with an async [load]. One difference is on
/// purpose: `main()` awaits [load] *before* `runApp`, so the stored state
/// is already in memory when the first group is built and a folded group
/// can never paint open and then snap shut.
///
/// Only explicit user choices are stored (`id -> bool`), so a fresh
/// install stores nothing and every group takes its own default (open).
class MmCollapseController extends ChangeNotifier {
  MmCollapseController({Set<String> known = MmGroupIds.all}) : _known = known;

  /// One JSON object, `{"<id>": true|false}`.
  static const String prefsKey = 'mm.collapse.v1';

  final Set<String> _known;
  final Map<String, bool> _state = <String, bool>{};
  bool _loaded = false;

  bool get loaded => _loaded;

  /// Whether [id] is open. [fallback] applies when the user has never
  /// toggled it.
  bool isOpen(String id, {bool fallback = true}) => _state[id] ?? fallback;

  Future<void> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    _state
      ..clear()
      ..addAll(_decode(p.getString(prefsKey), _known));
    _loaded = true;
    notifyListeners();
  }

  Future<void> setOpen(String id, bool open) async {
    assert(_known.contains(id), 'unregistered collapsible id "$id"');
    if (_state[id] == open) return;
    _state[id] = open;
    notifyListeners();
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setString(p, prefsKey, jsonEncode(_state));
  }

  /// Corrupt input, unknown ids and non-bool values are all ignored, so
  /// the affected group simply falls back to its default.
  @visibleForTesting
  static Map<String, bool> decode(String? raw, Set<String> known) =>
      _decode(raw, known);

  static Map<String, bool> _decode(String? raw, Set<String> known) {
    if (raw == null || raw.isEmpty) return <String, bool>{};
    try {
      final Object? j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return <String, bool>{};
      return <String, bool>{
        for (final MapEntry<String, dynamic> e in j.entries)
          if (known.contains(e.key) && e.value is bool) e.key: e.value as bool,
      };
    } catch (_) {
      return <String, bool>{};
    }
  }
}
