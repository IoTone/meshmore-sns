// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../theme/mm_tokens.dart';
import '../theme/theme_controller.dart';
import 'cue_service.dart';

/// R12 — `AudioPack` that plays per-theme, per-CueKind WAV assets
/// synthesized by `brand/_audio_pack.py`. The active theme is read
/// off `ThemeController.preset` at play time, so a theme switch
/// changes the audio identity *immediately* without rebuilding the
/// service (or restarting the app).
///
/// Asset shape — `assets/audio/<preset.audioPackKey>/<CueKind.name>.wav`.
/// Eleven preset folders × nineteen cues = 209 files (every theme has its own
/// full bespoke set — none fall through to a generic motif); if a file is
/// missing at runtime (asset bundling slipped, etc.) we silently fall back
/// to the system click via [SystemSoundAudioPack].
class AssetAudioPack implements AudioPack, WarmableAudioPack {
  AssetAudioPack({
    required this.theme,
    AudioPlayer? player,
    AudioPlayer? loopPlayer,
    AudioPack? fallback,
  })  : _player = player ?? AudioPlayer(),
        _loopPlayer = loopPlayer ?? AudioPlayer(),
        _fallback = fallback ?? const SystemSoundAudioPack();

  final ThemeController theme;
  final AudioPlayer _player;
  // Separate player for the sustained scanning drone, so a one-shot cue
  // firing mid-scan (a node advert, say) doesn't cut the loop short.
  final AudioPlayer _loopPlayer;
  final AudioPack _fallback;

  /// Looped cues (the scan drone) play quieter than one-shots — they run
  /// for seconds and shouldn't dominate. Lower gain per the field brief.
  static const double _loopVolume = 0.45;

  // One-shot cues are *sonification*, not media: they must not take audio
  // focus (a cue that interrupts the owner's podcast for 100 ms is a
  // nuisance, and a denied focus request is a cue that never plays), and on
  // iOS an ambient session keeps the Ring/Silent switch authoritative.
  static final AudioContext _cueContext = AudioContext(
    android: AudioContextAndroid(
      isSpeakerphoneOn: false,
      audioMode: AndroidAudioMode.normal,
      stayAwake: false,
      contentType: AndroidContentType.sonification,
      // USAGE_MEDIA, not USAGE_ASSISTANCE_SONIFICATION, and the difference is
      // audible rather than academic: Android routes sonification to the
      // *system* stream, so a phone with touch sounds off — which is most of
      // them — plays a cue nobody hears. Media routing is the stream the volume
      // keys and the user's own expectation are about.
      //
      // The reason this was changed in the first place was audio focus, and
      // that is a separate knob: `audioFocus: none` is what keeps a cue from
      // interrupting whatever else is playing.
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.none,
    ),
    // Ambient mixes with anything already playing and obeys the Ring/Silent
    // switch, which is the iOS way of saying "this is a UI sound".
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  /// One prepared MediaPlayer, reused. `ReleaseMode.stop` keeps the loaded
  /// buffer between plays instead of tearing it down (the default release mode
  /// does exactly that, which is how two quick swipes lost the first cue).
  ///
  /// `PlayerMode.lowLatency` is deliberately **not** used, and this is the
  /// reason. In that mode audioplayers drives a `SoundPool`, which loads a
  /// source asynchronously (`audioplayers_android/.../SoundPoolPlayer.kt:93-140`
  /// sets `prepared = false` and calls `soundPool.load`), while
  /// `WrappedPlayer.play()` starts only when the player is already prepared
  /// (`WrappedPlayer.kt:211-220`). Every cue is a different WAV, so every cue
  /// needs a fresh load, and a `play()` issued straight after `setSource` is
  /// dropped in silence with no exception — no cue, no fallback, nothing in the
  /// log. A MediaPlayer's `setSource` resolves after it is prepared, so the
  /// sequence below is deterministic.
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    try {
      await _player.setAudioContext(_cueContext);
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _loopPlayer.setAudioContext(_cueContext);
      await _loopPlayer.setReleaseMode(ReleaseMode.loop);
      _ready = true;
    } catch (_) {
      // Older platform / no audio service: leave the defaults in place and
      // let `play` fail into the fallback below.
      _ready = true;
    }
  }

  /// Compose the asset path the same way the synth script lays it out.
  /// Visible for the unit test (and for anyone reading the call site).
  static String assetPathFor(MmThemePreset preset, CueKind kind) =>
      'audio/${preset.audioPackKey}/${kind.name}.wav';

  @override
  Future<void> play(CueKind kind) async {
    final MmThemePreset p = theme.preset;
    final String path = assetPathFor(p, kind);
    final double volume = theme.cueVolume;
    try {
      await _ensureReady();
      // `AssetSource` paths are rooted at `assets/` by audioplayers
      // convention; passing `audio/seele/messageIn.wav` resolves to
      // `assets/audio/seele/messageIn.wav` in the bundle.
      //
      // Three explicit steps rather than `play(...)`: `setSource` is the call
      // that resolves once the file is prepared, so `resume` cannot overtake
      // it. `play()` with a mode argument takes the same path but leaves the
      // ordering implicit, which is what made a silent drop possible.
      await _player.setVolume(volume);
      await _player.setSource(AssetSource(path));
      await _player.resume();
    } catch (_) {
      // Asset missing / platform error → graceful degrade so the cue
      // is never silently lost, just less themed.
      unawaited(_fallback.play(kind));
    }
  }

  @override
  Future<void> startLoop(CueKind kind) async {
    final String path = assetPathFor(theme.preset, kind);
    try {
      await _ensureReady();
      await _loopPlayer.stop();
      await _loopPlayer.setReleaseMode(ReleaseMode.loop);
      await _loopPlayer.setVolume(_loopVolume * theme.cueVolume);
      await _loopPlayer.play(AssetSource(path));
    } catch (_) {
      // Asset missing / platform error — the scan just runs silent.
      // (No system-sound fallback: it can't loop.)
    }
  }

  @override
  /// Decodes the cues that matter most into the low-latency player.
  ///
  /// `audioplayers` in low-latency mode keeps a SoundPool of loaded samples, but
  /// only once something has been played. Playing each cue once at zero volume
  /// is the cheapest way to fill it: the pool keeps the decode, and the audible
  /// play later is a start rather than a load.
  @override
  Future<void> warm() async {
    for (final CueKind kind in <CueKind>[
      CueKind.messageIn,
      CueKind.dmIn,
      CueKind.send,
      CueKind.navNext,
      CueKind.navPrev,
      CueKind.discovery,
      CueKind.alert,
    ]) {
      try {
        await _player.play(AssetSource(assetPathFor(theme.preset, kind)),
            volume: 0);
        await _player.stop();
      } catch (_) {
        // A missing asset is the play path's problem, not the warm-up's.
      }
    }
  }

  @override
  Future<void> stopLoop() async {
    try {
      await _loopPlayer.stop();
    } catch (_) {
      // Already stopped / disposed — nothing to do.
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _loopPlayer.dispose();
  }
}
