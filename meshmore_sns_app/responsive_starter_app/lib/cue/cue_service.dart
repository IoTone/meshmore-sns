// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/services.dart';

import '../theme/mm_tokens.dart';
import '../theme/theme_controller.dart';

/// Event categories the app dispatches as cues (R12). Audible packs
/// (per-theme, R12 brief) and haptic mappings derive from these.
enum CueKind {
  /// A channel message arrived (anonymous-source by protocol).
  messageIn,

  /// A DM arrived (sender attributable by pubkey prefix).
  dmIn,

  /// A new node joined the fabric (advert / first contact).
  discovery,

  /// A re-advert heard from a node we already knew — ambient mesh life,
  /// distinct from `discovery` (a *new* node) and rate-limited so a busy
  /// fabric doesn't machine-gun it.
  advert,

  /// We sent something (send confirmation cue).
  send,

  /// App came up — played once on the splash/boot as the shell mounts.
  boot,

  /// Swiped forward to the next top-level view (PageView, →).
  navNext,

  /// Swiped back to the previous top-level view (PageView, ←).
  navPrev,

  /// The radio link came up (`ready`).
  linkUp,

  /// The radio link went away or is reconnecting.
  linkDown,

  /// Critical: device error / handshake failure.
  alert,

  /// Long-running task **kicked off** (scan / advert / connect attempt).
  scanStart,

  /// Long-running task **succeeded** (scan window elapsed, advert
  /// acknowledged, etc.).
  taskOk,

  /// Long-running task **failed** (send threw, scan timed out without
  /// any inbound, connect attempt failed). Less harsh than `alert`;
  /// alert is reserved for protocol-level critical errors.
  taskError,

  // ---- R58 signature slots ------------------------------------
  // These are not events like the rest of the enum; they are the
  // five *renderings* a peer's DM arrival can take instead of
  // [dmIn]. They live here rather than in a parallel enum so a
  // signature travels the existing path for free: `assetPathFor`
  // already yields `audio/<pack>/sig3.wav` from `kind.name`, the
  // generator writes exactly those filenames, and the two tests
  // that sweep `CueKind.values` extend their coverage without
  // being touched. Dispatch a signature with
  // [CueService.playSignature], never as a bare event.
  sig1,
  sig2,
  sig3,
  sig4,
  sig5,
}

/// The signature slots, in order. Empty-safe to index for UI.
const List<CueKind> kSignatureSlots = <CueKind>[
  CueKind.sig1,
  CueKind.sig2,
  CueKind.sig3,
  CueKind.sig4,
  CueKind.sig5,
];

/// True when [k] is a signature slot rather than an event cue.
bool isSignature(CueKind k) => kSignatureSlots.contains(k);

/// Pluggable audio backend. The default uses built-in system sounds —
/// per-theme asset packs (R12: "Mission Control" / "Velocity" / etc.)
/// plug in by implementing this interface once their assets exist.
abstract class AudioPack {
  Future<void> play(CueKind kind);

  /// Start a **looping** cue that sustains until [stopLoop] — used for
  /// the scanning drone, which should run for the whole scan window, not
  /// fire once. Packs that can't loop (system sounds) no-op.
  Future<void> startLoop(CueKind kind);

  /// Stop whatever [startLoop] started.
  Future<void> stopLoop();
}

/// Pluggable haptic backend.
abstract class HapticBackend {
  Future<void> play(CueKind kind);
}

/// Default audio: the two built-in `SystemSound` types. Cheap, asset-
/// free, present on every platform. Per-concept packs (audioplayers +
/// short WAVs per theme) supersede this when authored.
class SystemSoundAudioPack implements AudioPack {
  const SystemSoundAudioPack();
  @override
  Future<void> play(CueKind kind) async {
    try {
      final SystemSoundType s = (kind == CueKind.alert ||
              kind == CueKind.linkDown ||
              kind == CueKind.taskError)
          ? SystemSoundType.alert
          : SystemSoundType.click;
      await SystemSound.play(s);
    } catch (_) {
      // No platform / no audio output — silent, by design.
    }
  }

  // System sounds are one-shot — there's nothing to loop, so the
  // scanning drone simply stays silent on this fallback pack.
  @override
  Future<void> startLoop(CueKind kind) async {}
  @override
  Future<void> stopLoop() async {}
}

/// A single haptic pulse intensity. Multi-pulse patterns sequence these
/// with a short gap, so a theme can have a "double-tap" or "triple" feel —
/// the **haptic is part of the skin**, not just the sound (R12 deepening).
enum HapticHit { selection, light, medium, heavy }

/// Cues grouped by haptic intent. Each theme maps these tiers to its own
/// pattern, so the *feel* of "a DM arrived" or "critical" differs per skin.
enum _HTier { ambient, dm, arrival, positive, negative, critical, nav }

_HTier _tierOf(CueKind k) => switch (k) {
      CueKind.messageIn || CueKind.advert => _HTier.ambient,
      CueKind.dmIn => _HTier.dm,
      CueKind.discovery => _HTier.arrival,
      CueKind.linkUp ||
      CueKind.taskOk ||
      CueKind.send ||
      CueKind.boot =>
        _HTier.positive,
      CueKind.linkDown || CueKind.taskError => _HTier.negative,
      CueKind.alert => _HTier.critical,
      CueKind.navNext ||
      CueKind.navPrev ||
      CueKind.scanStart =>
        _HTier.nav,
      // Signatures never actually reach here -- [hapticPatternFor]
      // intercepts them first and resolves a per-slot rhythm. The arm
      // exists to keep this switch exhaustive, and `dm` is the honest
      // fallback: a signature *is* a DM arrival, just a named one.
      CueKind.sig1 ||
      CueKind.sig2 ||
      CueKind.sig3 ||
      CueKind.sig4 ||
      CueKind.sig5 =>
        _HTier.dm,
    };

// Per-theme haptic "feel". SEELE grave/single, NERV terse multi-tick,
// AG-HUD snappy doubles, Hyperlocal soft/calm (never heavy), DR Pop punchy
// rhythmic, Recon crisp-minimal (it's built to run silent → haptic carries
// the parity, so it stays distinct but light).
const Map<_HTier, List<HapticHit>> _seeleHaptics = <_HTier, List<HapticHit>>{
  _HTier.ambient: <HapticHit>[HapticHit.medium],
  _HTier.dm: <HapticHit>[HapticHit.heavy],
  _HTier.arrival: <HapticHit>[HapticHit.medium, HapticHit.medium],
  _HTier.positive: <HapticHit>[HapticHit.medium],
  _HTier.negative: <HapticHit>[HapticHit.heavy],
  _HTier.critical: <HapticHit>[HapticHit.heavy, HapticHit.heavy],
  _HTier.nav: <HapticHit>[HapticHit.selection],
};
const Map<_HTier, List<HapticHit>> _nervHaptics = <_HTier, List<HapticHit>>{
  _HTier.ambient: <HapticHit>[HapticHit.selection],
  _HTier.dm: <HapticHit>[HapticHit.light, HapticHit.light],
  _HTier.arrival: <HapticHit>[
    HapticHit.light,
    HapticHit.light,
    HapticHit.light
  ],
  _HTier.positive: <HapticHit>[HapticHit.medium],
  _HTier.negative: <HapticHit>[HapticHit.heavy],
  _HTier.critical: <HapticHit>[
    HapticHit.heavy,
    HapticHit.heavy,
    HapticHit.heavy
  ],
  _HTier.nav: <HapticHit>[HapticHit.selection],
};
const Map<_HTier, List<HapticHit>> _agHudHaptics = <_HTier, List<HapticHit>>{
  _HTier.ambient: <HapticHit>[HapticHit.light],
  _HTier.dm: <HapticHit>[HapticHit.medium, HapticHit.light],
  _HTier.arrival: <HapticHit>[HapticHit.medium, HapticHit.medium],
  _HTier.positive: <HapticHit>[HapticHit.medium, HapticHit.medium],
  _HTier.negative: <HapticHit>[HapticHit.heavy],
  _HTier.critical: <HapticHit>[HapticHit.heavy, HapticHit.heavy],
  _HTier.nav: <HapticHit>[HapticHit.selection],
};
const Map<_HTier, List<HapticHit>> _hyperHaptics = <_HTier, List<HapticHit>>{
  _HTier.ambient: <HapticHit>[HapticHit.light],
  _HTier.dm: <HapticHit>[HapticHit.medium],
  _HTier.arrival: <HapticHit>[HapticHit.medium],
  _HTier.positive: <HapticHit>[HapticHit.light],
  _HTier.negative: <HapticHit>[HapticHit.medium],
  _HTier.critical: <HapticHit>[HapticHit.medium, HapticHit.medium],
  _HTier.nav: <HapticHit>[HapticHit.selection],
};
const Map<_HTier, List<HapticHit>> _drPopHaptics = <_HTier, List<HapticHit>>{
  _HTier.ambient: <HapticHit>[HapticHit.light, HapticHit.light],
  _HTier.dm: <HapticHit>[HapticHit.medium, HapticHit.medium],
  _HTier.arrival: <HapticHit>[HapticHit.medium, HapticHit.light],
  _HTier.positive: <HapticHit>[HapticHit.medium, HapticHit.medium],
  _HTier.negative: <HapticHit>[HapticHit.heavy],
  _HTier.critical: <HapticHit>[
    HapticHit.heavy,
    HapticHit.heavy,
    HapticHit.heavy
  ],
  _HTier.nav: <HapticHit>[HapticHit.light],
};
const Map<_HTier, List<HapticHit>> _reconHaptics = <_HTier, List<HapticHit>>{
  _HTier.ambient: <HapticHit>[HapticHit.selection],
  _HTier.dm: <HapticHit>[HapticHit.selection, HapticHit.selection],
  _HTier.arrival: <HapticHit>[HapticHit.medium],
  _HTier.positive: <HapticHit>[HapticHit.medium],
  _HTier.negative: <HapticHit>[HapticHit.medium],
  _HTier.critical: <HapticHit>[HapticHit.heavy],
  _HTier.nav: <HapticHit>[HapticHit.selection],
};
// No theme wired (e.g. the default const backend in tests) — a neutral
// profile close to the app's prior flat mapping.
const Map<_HTier, List<HapticHit>> _defaultHaptics = <_HTier, List<HapticHit>>{
  _HTier.ambient: <HapticHit>[HapticHit.light],
  _HTier.dm: <HapticHit>[HapticHit.medium],
  _HTier.arrival: <HapticHit>[HapticHit.medium],
  _HTier.positive: <HapticHit>[HapticHit.medium],
  _HTier.negative: <HapticHit>[HapticHit.heavy],
  _HTier.critical: <HapticHit>[HapticHit.heavy],
  _HTier.nav: <HapticHit>[HapticHit.selection],
};

const Map<MmThemePreset, Map<_HTier, List<HapticHit>>> _hapticProfiles =
    <MmThemePreset, Map<_HTier, List<HapticHit>>>{
  MmThemePreset.seele: _seeleHaptics,
  MmThemePreset.nerv: _nervHaptics,
  MmThemePreset.agHud: _agHudHaptics,
  MmThemePreset.hyperlocal: _hyperHaptics,
  MmThemePreset.drPop: _drPopHaptics,
  MmThemePreset.recon: _reconHaptics,
};

// ---- R58 signature rhythms ------------------------------------
//
// A signature must be recognisable through a pocket, and that is a
// far tighter budget than sound. `HapticHit` offers four intensities,
// but a person holding a conversation elsewhere reliably distinguishes
// only a handful of *rhythms* -- so the slot count is set here, not by
// how many tones the synth can make.
//
// Each slot is a CONTOUR of strong/weak beats. The theme supplies what
// "strong" and "weak" mean in its own vocabulary, exactly as it does
// for the tier patterns, so a signature keeps its identity across a
// theme switch while its expression changes.
//
// Capped at three beats: a burst of inbound messages must not queue
// into one continuous buzz. And no slot may be ONE beat either --
// several themes already spend their single-beat patterns on `ambient`
// or `dm`, so a one-beat signature cannot be told from an ordinary
// channel message or an unsigned DM in those packs. That is why `sig1`
// is a double rather than the obvious single thump.
enum _SigBeat { strong, weak }

const Map<CueKind, List<_SigBeat>> _sigContours =
    <CueKind, List<_SigBeat>>{
  CueKind.sig1: <_SigBeat>[_SigBeat.strong, _SigBeat.strong],
  CueKind.sig2: <_SigBeat>[_SigBeat.weak, _SigBeat.strong],
  CueKind.sig3: <_SigBeat>[_SigBeat.strong, _SigBeat.weak],
  CueKind.sig4: <_SigBeat>[_SigBeat.weak, _SigBeat.weak, _SigBeat.weak],
  CueKind.sig5: <_SigBeat>[_SigBeat.weak, _SigBeat.weak],
};

/// (strong, weak) per theme -- the theme's own reading of the contour.
///
/// These are not free choices. Each theme has already spent part of the
/// `HapticHit` vocabulary on `ambient` and `dm`, and a signature may
/// not land on either: colliding with `dm` would make a signed peer
/// feel exactly like an unsigned one, which defeats the whole feature.
/// [signatureCollisions] enforces it and a test sweeps every pack.
///
/// The pairs below are the most in-character legal option per theme --
/// SEELE grave, NERV and AG-HUD terse, Hyperlocal never heavy, DR Pop
/// punchy, Recon crisp. **DR Pop has only two legal pairs at all**
/// (its `ambient` and `dm` already occupy both same-intensity doubles),
/// which is the clearest signal that this vocabulary is close to full.
/// A sixth slot would not fit; see the note on slot count above.
const Map<MmThemePreset, (HapticHit, HapticHit)> _sigIntensities =
    <MmThemePreset, (HapticHit, HapticHit)>{
  MmThemePreset.seele: (HapticHit.heavy, HapticHit.medium),
  MmThemePreset.nerv: (HapticHit.medium, HapticHit.selection),
  MmThemePreset.agHud: (HapticHit.medium, HapticHit.selection),
  MmThemePreset.hyperlocal: (HapticHit.medium, HapticHit.light),
  MmThemePreset.drPop: (HapticHit.heavy, HapticHit.selection),
  MmThemePreset.recon: (HapticHit.medium, HapticHit.light),
};
const (HapticHit, HapticHit) _defaultSigIntensity =
    (HapticHit.medium, HapticHit.light);

List<HapticHit> _signaturePattern(MmThemePreset? preset, CueKind slot) {
  final (HapticHit strong, HapticHit weak) =
      _sigIntensities[preset] ?? _defaultSigIntensity;
  return <HapticHit>[
    for (final _SigBeat b in _sigContours[slot]!)
      b == _SigBeat.strong ? strong : weak,
  ];
}

/// Signature slots that are indistinguishable **as rendered** under
/// [preset] -- either from each other, or from the two patterns a user
/// meets in the same breath: `ambient` (a channel message) and `dm`
/// (a DM from a peer with no signature).
///
/// The guard deliberately compares resolved renderings rather than slot
/// ids. Two slots that are obviously different as tones can collapse to
/// the same rhythm once a theme maps them, and the rhythm is the half
/// that has to work from a pocket.
///
/// Returns a human-readable description per collision; empty means the
/// pack is clean. Exercised for every preset in the cue tests.
List<String> signatureCollisions(MmThemePreset? preset) {
  final List<String> out = <String>[];
  final Map<CueKind, List<HapticHit>> rendered =
      <CueKind, List<HapticHit>>{
    for (final CueKind s in kSignatureSlots)
      s: _signaturePattern(preset, s),
  };
  bool same(List<HapticHit> a, List<HapticHit> b) =>
      a.length == b.length &&
      List<int>.generate(a.length, (int i) => i)
          .every((int i) => a[i] == b[i]);

  for (int i = 0; i < kSignatureSlots.length; i++) {
    for (int j = i + 1; j < kSignatureSlots.length; j++) {
      final CueKind a = kSignatureSlots[i];
      final CueKind b = kSignatureSlots[j];
      if (same(rendered[a]!, rendered[b]!)) {
        out.add('${a.name} == ${b.name}');
      }
    }
  }
  final Map<_HTier, List<HapticHit>> prof =
      _hapticProfiles[preset] ?? _defaultHaptics;
  for (final CueKind s in kSignatureSlots) {
    if (same(rendered[s]!, prof[_HTier.ambient]!)) {
      out.add('${s.name} == ambient (a channel message)');
    }
    if (same(rendered[s]!, prof[_HTier.dm]!)) {
      out.add('${s.name} == dm (an unsigned peer)');
    }
  }
  return out;
}

/// The per-theme haptic pattern for a cue (pure — exported for tests).
/// `preset == null` → the neutral default profile.
///
/// Signature slots resolve to their own per-slot rhythm; every other
/// cue resolves through its tier as before.
List<HapticHit> hapticPatternFor(MmThemePreset? preset, CueKind kind) =>
    isSignature(kind)
        ? _signaturePattern(preset, kind)
        : (_hapticProfiles[preset] ?? _defaultHaptics)[_tierOf(kind)]!;

/// Default haptic: per-theme `HapticFeedback` patterns (system-respecting:
/// silent/vibrate modes are honoured by the OS). Reads `theme.preset` at
/// play time, so a theme switch changes the *feel* immediately — mirroring
/// how [AssetAudioPack] changes the sound. With no [theme] it uses the
/// neutral default profile.
class SystemHapticBackend implements HapticBackend {
  const SystemHapticBackend({
    this.theme,
    this.stepGap = const Duration(milliseconds: 70),
  });

  /// Read for the active preset; null → neutral default patterns.
  final ThemeController? theme;

  /// Spacing between pulses in a multi-hit pattern (double/triple taps).
  final Duration stepGap;

  @override
  Future<void> play(CueKind kind) async {
    final List<HapticHit> pattern = hapticPatternFor(theme?.preset, kind);
    try {
      for (int i = 0; i < pattern.length; i++) {
        if (i > 0) await Future<void>.delayed(stepGap);
        await _fire(pattern[i]);
      }
    } catch (_) {
      // No platform / no actuator — silent.
    }
  }

  Future<void> _fire(HapticHit h) => switch (h) {
        HapticHit.selection => HapticFeedback.selectionClick(),
        HapticHit.light => HapticFeedback.lightImpact(),
        HapticHit.medium => HapticFeedback.mediumImpact(),
        HapticHit.heavy => HapticFeedback.heavyImpact(),
      };
}

/// Dispatches an event → (theme-driven audio) + (always-on haptic),
/// with visual parity expected at the call site (R12/R13). Gating:
/// audio plays only when `theme.audioMaster` is true AND
/// `theme.visualHapticOnly` is false; haptic plays for every cue and
/// the OS honours silent/vibrate.
class CueService {
  CueService({
    required this.theme,
    AudioPack? audio,
    HapticBackend? haptic,
  })  : audio = audio ?? const SystemSoundAudioPack(),
        haptic = haptic ?? const SystemHapticBackend();

  final ThemeController theme;
  final AudioPack audio;
  final HapticBackend haptic;

  Future<void> play(CueKind kind) async {
    if (theme.audioMaster && !theme.visualHapticOnly) {
      unawaited(audio.play(kind));
    }
    unawaited(haptic.play(kind));
  }

  /// Play a peer's signature (R58) **instead of** [CueKind.dmIn].
  ///
  /// Substitution, never addition. `_HTier.dm` already fires a
  /// per-theme pattern for every DM; playing that *and* a signature
  /// produces mush and destroys both identities -- the signature stops
  /// being recognisable and the ordinary DM feel stops being ordinary.
  /// So this is a plain [play] of the slot, and the caller must not
  /// also play `dmIn`.
  ///
  /// A null [slot] means the peer has no signature, and the ordinary
  /// `dmIn` is played -- so call sites can stay branch-free.
  Future<void> playSignature(CueKind? slot) {
    assert(slot == null || isSignature(slot),
        'playSignature expects a signature slot, got $slot');
    return play(slot ?? CueKind.dmIn);
  }

  /// Begin the sustained scanning drone (loops [CueKind.scanStart] for
  /// the duration of the scan). Audio honours the same gate as [play];
  /// a single light haptic marks the start regardless.
  Future<void> startScanHum() async {
    if (theme.audioMaster && !theme.visualHapticOnly) {
      unawaited(audio.startLoop(CueKind.scanStart));
    }
    unawaited(haptic.play(CueKind.scanStart));
  }

  /// End the scanning drone. Idempotent — safe to call even if no hum
  /// is playing (e.g. audio was muted when the scan began).
  Future<void> stopScanHum() async {
    unawaited(audio.stopLoop());
  }
}
