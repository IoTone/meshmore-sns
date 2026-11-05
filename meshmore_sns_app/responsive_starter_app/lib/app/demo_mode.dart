// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Radio-free mode: the app opens without trying to reach a companion, and
/// says so.
///
/// The offline path has to be a first-class choice rather than an error state:
/// a user with no radio, a refused Bluetooth permission, or a look at the app
/// before buying hardware is not running a degraded product. What this is
/// *not* is a simulation. Nothing here invents a peer, a message or a signal
/// strength; the radio surfaces stay empty and honest, and the app-bar chip
/// names the mode so an empty fabric is never mistaken for a quiet mesh.
///
/// Persisted as one bool so the choice survives a launch. Leaving the mode
/// takes a callback rather than knowing about the radio, so the caller can ask
/// an already-paired companion to reconnect without a relaunch.
class DemoMode extends ChangeNotifier {
  DemoMode({bool? initial, bool? loaded})
      : _enabled = initial ?? false,
        _loaded = loaded ?? initial != null;

  factory DemoMode.preloaded({required bool enabled}) =>
      DemoMode(initial: enabled, loaded: true);

  static const String _key = 'mm.demoMode';

  bool _enabled;
  bool _loaded;

  bool get loaded => _loaded;
  bool get enabled => _enabled;

  Future<void> load() async {
    if (_loaded) return;
    final SharedPreferences p = await SharedPreferences.getInstance();
    _enabled = p.getBool(_key) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value, {VoidCallback? onDisabled}) async {
    if (_enabled == value) return;
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
    _enabled = value;
    notifyListeners();
    if (!value) onDisabled?.call();
  }
}
