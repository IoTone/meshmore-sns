// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../util/prefs.dart';

/// Which content blocks a user may pin to the dashboard.
///
/// An id is a fixed English token, never the localised title (so an English
/// and a Japanese user share the stored value) and never an index (so
/// reordering cannot swap two cards). The set is closed: a stored id that is
/// not listed here belongs to a removed or renamed card and is dropped on
/// load, so the stored list cannot grow without bound and a pin can never
/// become a blank card after a refactor.
///
/// Only summaries belong here. A card is a summary plus a tap-through, never
/// a second copy of a whole screen: a map, the radar, the chat and anything
/// that has to ask the radio on rebuild are deliberately absent, because a
/// dashboard that polls is worse than the tab it duplicates.
abstract final class MmPinIds {
  static const String coverageSummary = 'pin.coverageSummary';
  static const String fieldExport = 'pin.fieldExport';
  static const String radioHealth = 'pin.radioHealth';

  /// The order the pin menu offers them in.
  static const List<String> menu = <String>[
    coverageSummary,
    fieldExport,
    radioHealth,
  ];

  static const Set<String> all = <String>{
    coverageSummary,
    fieldExport,
    radioHealth,
  };
}

/// Remembers which summaries the user pinned, their order, and which of them
/// are expanded.
///
/// One store owns membership, order and expansion on purpose: expansion is
/// per card, so it cannot live in [MmCollapseController], whose closed id set
/// has a test that fails when an id is listed but no screen uses it.
///
/// Follows the app's controller convention (`ThemeController`,
/// `MmCollapseController`): a `ChangeNotifier` provided at the root, backed
/// by `shared_preferences`, with a [load] that `main()` awaits before
/// `runApp` so the first frame cannot paint unpinned and then snap.
class DashboardPinsController extends ChangeNotifier {
  DashboardPinsController({Set<String> known = MmPinIds.all}) : _known = known;

  /// One JSON object, `{"pins": ["pin.sos", ...], "open": [...]}`. JSON rather
  /// than two keys so a half-written store cannot keep pins without their
  /// order.
  static const String prefsKey = 'mm.dashboardPins.v1';

  final Set<String> _known;
  final List<String> _pins = <String>[];
  final Set<String> _open = <String>{};
  bool _loaded = false;

  bool get loaded => _loaded;

  /// Pinned ids in display order.
  List<String> get pins => List<String>.unmodifiable(_pins);

  bool get isEmpty => _pins.isEmpty;

  bool contains(String id) => _pins.contains(id);

  bool isOpen(String id) => _open.contains(id);

  Future<void> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final _PinsState s = _decode(p.getString(prefsKey), _known);
    _pins
      ..clear()
      ..addAll(s.pins);
    _open
      ..clear()
      ..addAll(s.open.where(_pins.contains));
    _loaded = true;
    notifyListeners();
  }

  /// Appends a pin. Idempotent: pinning twice keeps the first position, so a
  /// second tap in the owning screen cannot move a card.
  Future<void> pin(String id) async {
    assert(_known.contains(id), 'unregistered pin id "$id"');
    if (!_known.contains(id) || _pins.contains(id)) return;
    _pins.add(id);
    notifyListeners();
    await _save();
  }

  Future<void> unpin(String id) async {
    if (!_pins.remove(id)) return;
    _open.remove(id);
    notifyListeners();
    await _save();
  }

  Future<void> toggle(String id) => _pins.contains(id) ? unpin(id) : pin(id);

  /// Moves [id] to [to] (clamped), for the dashboard's edit mode.
  Future<void> move(String id, int to) async {
    final int at = _pins.indexOf(id);
    if (at < 0) return;
    final int target = to.clamp(0, _pins.length - 1);
    if (target == at) return;
    _pins
      ..removeAt(at)
      ..insert(target, id);
    notifyListeners();
    await _save();
  }

  Future<void> setOpen(String id, bool open) async {
    if (!_pins.contains(id)) return;
    if (open == _open.contains(id)) return;
    if (open) {
      _open.add(id);
    } else {
      _open.remove(id);
    }
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setString(p, 
      prefsKey,
      jsonEncode(<String, Object>{
        'pins': _pins,
        'open': _open.toList(growable: false),
      }),
    );
  }

  /// Corrupt input, unknown ids, duplicates and non-string entries are all
  /// dropped, so a damaged store is an empty dashboard rather than a crash.
  @visibleForTesting
  static List<String> decodePins(String? raw, Set<String> known) =>
      _decode(raw, known).pins;

  static _PinsState _decode(String? raw, Set<String> known) {
    if (raw == null || raw.isEmpty) {
      return const _PinsState(<String>[], <String>{});
    }
    try {
      final Object? j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) {
        return const _PinsState(<String>[], <String>{});
      }
      final List<String> pins = <String>[];
      final Object? rawPins = j['pins'];
      if (rawPins is List) {
        for (final Object? e in rawPins) {
          if (e is! String || !known.contains(e) || pins.contains(e)) continue;
          pins.add(e);
        }
      }
      final Set<String> open = <String>{};
      final Object? rawOpen = j['open'];
      if (rawOpen is List) {
        for (final Object? e in rawOpen) {
          if (e is String && pins.contains(e)) open.add(e);
        }
      }
      return _PinsState(pins, open);
    } catch (_) {
      return const _PinsState(<String>[], <String>{});
    }
  }
}

@immutable
final class _PinsState {
  const _PinsState(this.pins, this.open);
  final List<String> pins;
  final Set<String> open;
}
