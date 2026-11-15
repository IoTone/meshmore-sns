// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mm_skin.dart';
import 'mm_tokens.dart';
import '../util/prefs.dart';

/// User-customizable appearance & accessibility (R14 / R12 / R13).
///
/// Holds the active theme preset (default **D / SEELE**), a font-size
/// scale layered on top of the OS text scale, and the accessibility /
/// audio preference flags. Persisted via `shared_preferences`; the
/// rest of the app reads only this (single source of truth).
class ThemeController extends ChangeNotifier {
  static const String _kPreset = 'mm.preset';
  static const String _kFontScale = 'mm.fontScale';
  static const String _kHighContrast = 'mm.highContrast';
  static const String _kReduceMotion = 'mm.reduceMotion';
  static const String _kAudioMaster = 'mm.audioMaster';
  static const String _kVisualHapticOnly = 'mm.visualHapticOnly';
  static const String _kCueVolume = 'mm.cueVolume';

  // STUDIO is the default a fresh install opens on: the quiet, sans-face,
  // square-control skin. The technical presets (SEELE, NERV, AG-HUD, RECON,
  // Dr Pop, Hyperlocal) are a deliberate choice in Personalisation.
  MmThemePreset _preset = MmThemePreset.studio;
  double _fontScale = 1.0;
  bool _highContrast = false;
  bool _reduceMotion = false;
  bool _audioMaster = true; // audible alerts ON by default; quick-mute
  // available from the dashboard (was off by default pre-R12 revision).
  bool _visualHapticOnly = false;

  /// How loud a cue plays, 0-1, on top of the phone's own media volume. One
  /// on a fresh install: the packs are normalised to a -1.5 dBFS peak, and a
  /// cue is worth hearing without the owner hunting for a slider. It exists
  /// because the media volume is not ours to set — the phone's own 3/15 is a
  /// choice about *everything* that plays, so the app needs its own trim.
  double _cueVolume = 1.0;

  /// The operating system's own accessibility switches, mirrored in here.
  ///
  /// The app has a switch for each, and so does Android. Honouring only the app's
  /// meant a reader who turned on "Remove animations" in system settings still
  /// got a sweeping radar, a rising toast and pulsing markers, and one who turned
  /// on high contrast still got the quiet skin. Set from `MediaQuery` at the root
  /// (`main.dart`), never persisted: they are the platform's, not ours.
  bool _osReduceMotion = false;
  bool _osHighContrast = false;

  /// True when either the app's switch or the platform's is on.
  bool get reduceMotion => _reduceMotion || _osReduceMotion;
  bool get highContrast => _highContrast || _osHighContrast;

  /// The platform's reduce-motion setting changed. No-op when it did not
  /// change, so a rebuild per frame cannot notify in a loop.
  void setOsReduceMotion(bool v) {
    if (v == _osReduceMotion) return;
    _osReduceMotion = v;
    notifyListeners();
  }

  void setOsHighContrast(bool v) {
    if (v == _osHighContrast) return;
    _osHighContrast = v;
    notifyListeners();
  }

  MmThemePreset get preset => _preset;
  double get fontScale => _fontScale;
  bool get audioMaster => _audioMaster;
  bool get visualHapticOnly => _visualHapticOnly;
  double get cueVolume => _cueVolume;

  MmTokens get tokens => kMmPresets[_preset]!;

  /// Forced to the high-contrast SEELE token set when [highContrast]
  /// is on, regardless of the chosen preset. The active skin's display
  /// face is applied app-wide so every screen reads in the brand type.
  ThemeData get theme {
    final MmSkin skin =
        mmSkinFor(_highContrast ? MmThemePreset.seele : _preset);
    final ThemeData base = buildMmTheme(skin.color,
        fontFamily: skin.type.displayFamily, shape: skin.shape);
    if (!reduceMotion) return base;
    // Reduce motion is about the whole app, not the two views that remembered to
    // ask: a ripple that spreads across a control and a page that slides in are
    // both motion. No ink, and a page transition that draws nothing.
    return base.copyWith(
      splashFactory: NoSplash.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: _NoTransitionBuilder(),
          TargetPlatform.iOS: _NoTransitionBuilder(),
          TargetPlatform.linux: _NoTransitionBuilder(),
          TargetPlatform.macOS: _NoTransitionBuilder(),
          TargetPlatform.windows: _NoTransitionBuilder(),
          TargetPlatform.fuchsia: _NoTransitionBuilder(),
        },
      ),
    );
  }

  /// Load persisted preferences. Safe to call once at startup.
  Future<void> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    _preset = presetFromId(p.getString(_kPreset));
    _fontScale = Prefs.readDouble(p, _kFontScale, fallback: 1.0).clamp(0.8, 1.6);
    _highContrast = Prefs.readBool(p, _kHighContrast);
    _reduceMotion = Prefs.readBool(p, _kReduceMotion);
    _audioMaster = Prefs.readBool(p, _kAudioMaster, fallback: true);
    _visualHapticOnly = Prefs.readBool(p, _kVisualHapticOnly);
    _cueVolume = Prefs.readDouble(p, _kCueVolume, fallback: 1.0).clamp(0.0, 1.0);
    notifyListeners();
  }

  Future<void> _save(Future<void> Function(SharedPreferences p) write) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await write(p);
  }

  Future<void> setPreset(MmThemePreset v) async {
    if (v == _preset) return;
    _preset = v;
    notifyListeners();
    await _save((SharedPreferences p) async {
      await Prefs.setString(p, _kPreset, v.name);
    });
  }

  Future<void> setFontScale(double v) async {
    final double c = v.clamp(0.8, 1.6);
    if (c == _fontScale) return;
    _fontScale = c;
    notifyListeners();
    await _save((SharedPreferences p) => Prefs.setDouble(p, _kFontScale, c));
  }

  Future<void> setHighContrast(bool v) async {
    _highContrast = v;
    notifyListeners();
    await _save((SharedPreferences p) => Prefs.setBool(p, _kHighContrast, v));
  }

  Future<void> setReduceMotion(bool v) async {
    _reduceMotion = v;
    notifyListeners();
    await _save((SharedPreferences p) => Prefs.setBool(p, _kReduceMotion, v));
  }

  Future<void> setAudioMaster(bool v) async {
    _audioMaster = v;
    notifyListeners();
    await _save((SharedPreferences p) => Prefs.setBool(p, _kAudioMaster, v));
  }

  Future<void> setVisualHapticOnly(bool v) async {
    _visualHapticOnly = v;
    // Mutually reinforcing: visual+haptic-only implies audio off.
    if (v) _audioMaster = false;
    notifyListeners();
    await _save((SharedPreferences p) async {
      await Prefs.setBool(p, _kVisualHapticOnly, v);
      if (v) await Prefs.setBool(p, _kAudioMaster, false);
    });
  }

  Future<void> setCueVolume(double v) async {
    final double c = v.clamp(0.0, 1.0);
    if (c == _cueVolume) return;
    _cueVolume = c;
    notifyListeners();
    await _save((SharedPreferences p) => Prefs.setDouble(p, _kCueVolume, c));
  }
}

/// A page transition that draws the new page and nothing else.
///
/// The route still takes its own transition duration, but nothing moves and
/// nothing fades, so the page appears at once. Used only when motion is reduced.
class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
