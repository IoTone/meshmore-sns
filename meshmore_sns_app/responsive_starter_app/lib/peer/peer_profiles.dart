// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cue/cue_service.dart' show CueKind, isSignature;

/// R58 — whether inbound DMs from one peer are spoken aloud.
///
/// Tri-state rather than a bool so "follow the global switch" stays
/// expressible: a peer the user has never thought about must keep
/// tracking the global setting, while an explicit choice outranks it
/// in **both** directions (same shape as R24's per-channel overrides).
enum PeerSpeechMode {
  /// No opinion — follow `TtsController.enabled`. The default, and the
  /// state of every peer the user has not configured.
  inherit,

  /// Speak this peer even when the global switch is off. This is the
  /// point of the feature: one favourite radio you always hear.
  always,

  /// Never speak this peer, even when the global switch is on.
  never;

  static PeerSpeechMode fromId(String? id) => switch (id) {
        'always' => PeerSpeechMode.always,
        'never' => PeerSpeechMode.never,
        _ => PeerSpeechMode.inherit,
      };

  String get id => name;
}

/// Everything the user has said about one peer (R58).
///
/// Every field defaults to *inherit*, expressed as the field's null or
/// `inherit` value. A profile where nothing is set is [isEmpty] and is
/// never persisted — an override is an act of attention, like a
/// favourite, so peers the user has ignored cost zero bytes.
///
/// `voice`, `pitchOffset`, `rateOffset` and `announceName` are still
/// design (see R58 in the spec); the record is versioned so adding them
/// will not need another migration.
@immutable
class PeerProfile {
  const PeerProfile({
    this.speak = PeerSpeechMode.inherit,
    this.signature,
  });

  /// Whether inbound DMs from this peer are spoken.
  final PeerSpeechMode speak;

  /// The peer's signature slot, or null to use the pack's ordinary
  /// `dmIn`. Always one of `kSignatureSlots` when non-null.
  final CueKind? signature;

  bool get isEmpty => speak == PeerSpeechMode.inherit && signature == null;

  PeerProfile copyWith({
    PeerSpeechMode? speak,
    CueKind? signature,
    bool clearSignature = false,
  }) =>
      PeerProfile(
        speak: speak ?? this.speak,
        signature: clearSignature ? null : (signature ?? this.signature),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        if (speak != PeerSpeechMode.inherit) 'speak': speak.id,
        if (signature != null) 'sig': signature!.name,
      };

  static PeerProfile fromJson(Map<String, Object?> j) {
    final Object? sig = j['sig'];
    return PeerProfile(
      speak: PeerSpeechMode.fromId(j['speak'] as String?),
      signature: sig is String ? slotFromName(sig) : null,
    );
  }

  /// Resolve a persisted slot name, ignoring anything that is not a
  /// signature — a hand-edited or downgraded prefs file must not be
  /// able to make an arbitrary cue the DM arrival sound.
  static CueKind? slotFromName(String name) {
    for (final CueKind k in CueKind.values) {
      if (k.name == name && isSignature(k)) return k;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PeerProfile &&
      other.speak == speak &&
      other.signature == signature;

  @override
  int get hashCode => Object.hash(speak, signature);
}

/// Persisted per-peer records, keyed by node pubkey hex.
///
/// Keying on pubkey means a choice survives a peer being deleted and
/// re-added (R56).
abstract final class PeerProfileStore {
  /// v2 — a JSON object of `pubkeyHex -> record`. v1 was a StringList
  /// of `hex|speakMode`, which had nowhere to put a second field.
  static const String kKey = 'mm.peer.profile.v2';

  /// The v1 key, still read once for migration.
  static const String kLegacyKey = 'mm.tts.peerSpeech.v1';

  static Future<Map<String, PeerProfile>> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(kKey);
    if (raw == null) return _migrateFromV1(p);
    try {
      final Object? decoded = json.decode(raw);
      if (decoded is! Map) return <String, PeerProfile>{};
      final Map<String, PeerProfile> out = <String, PeerProfile>{};
      decoded.forEach((Object? k, Object? v) {
        if (k is! String || v is! Map) return;
        final PeerProfile prof =
            PeerProfile.fromJson(v.cast<String, Object?>());
        if (!prof.isEmpty) out[k.toLowerCase()] = prof;
      });
      return out;
    } catch (_) {
      // Corrupt payload — start clean rather than throw on launch.
      return <String, PeerProfile>{};
    }
  }

  /// Read the v1 StringList and carry it forward.
  ///
  /// The v1 key is deliberately **left in place**. It costs a few bytes
  /// and it means rolling the app back shows the user their old speech
  /// choices rather than an empty list; v2 wins whenever it exists, so
  /// the stale copy can never be read again on the forward path.
  static Future<Map<String, PeerProfile>> _migrateFromV1(
      SharedPreferences p) async {
    final List<String>? rows = p.getStringList(kLegacyKey);
    if (rows == null) return <String, PeerProfile>{};
    final Map<String, PeerProfile> out = <String, PeerProfile>{};
    for (final String row in rows) {
      final int sep = row.indexOf('|');
      if (sep <= 0) continue; // malformed — drop rather than throw
      final PeerSpeechMode m = PeerSpeechMode.fromId(row.substring(sep + 1));
      if (m == PeerSpeechMode.inherit) continue; // never stored
      out[row.substring(0, sep).toLowerCase()] = PeerProfile(speak: m);
    }
    if (out.isNotEmpty) await save(out);
    return out;
  }

  static Future<void> save(Map<String, PeerProfile> profiles) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final Map<String, Object?> payload = <String, Object?>{
      for (final MapEntry<String, PeerProfile> e in profiles.entries)
        if (!e.value.isEmpty) e.key: e.value.toJson(),
    };
    if (payload.isEmpty) {
      await p.remove(kKey);
      return;
    }
    await p.setString(kKey, json.encode(payload));
  }

  static Future<void> clear() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.remove(kKey);
    await p.remove(kLegacyKey);
  }
}

/// The single owner of per-peer records (R58).
///
/// Deliberately **not** part of `TtsController`: the record spans two
/// subsystems — speech and cues — and one prefs key must have exactly
/// one writer. `TtsController` delegates its per-peer speech API here
/// rather than keeping a second copy of the map.
class PeerProfiles extends ChangeNotifier {
  Map<String, PeerProfile> _byKey = <String, PeerProfile>{};

  /// Peers with an explicit override. Exposed for a future "peers with
  /// a voice" list; callers must not mutate it.
  Map<String, PeerProfile> get all =>
      Map<String, PeerProfile>.unmodifiable(_byKey);

  Future<void> load() async {
    _byKey = await PeerProfileStore.load();
    notifyListeners();
  }

  /// Resolve a peer key against the stored records.
  ///
  /// A DM carries the peer's **full 64-hex pubkey when the fabric can
  /// resolve it, or only the 12-hex prefix when it cannot** (see
  /// `ChatMessage.peerPubKeyHex`), while the user sets an override from
  /// a sheet that usually knows the full key. So an exact lookup would
  /// silently miss: match exactly first, then let either side be a
  /// prefix of the other.
  String? resolveKey(String pubKeyHex) {
    if (pubKeyHex.isEmpty) return null;
    final String k = pubKeyHex.toLowerCase();
    if (_byKey.containsKey(k)) return k;
    for (final String stored in _byKey.keys) {
      if (stored.startsWith(k) || k.startsWith(stored)) return stored;
    }
    return null;
  }

  PeerProfile profileFor(String pubKeyHex) {
    final String? k = resolveKey(pubKeyHex);
    return k == null ? const PeerProfile() : _byKey[k]!;
  }

  PeerSpeechMode speechMode(String pubKeyHex) => profileFor(pubKeyHex).speak;

  /// The peer's signature slot, or null for the pack's ordinary `dmIn`.
  CueKind? signatureFor(String pubKeyHex) => profileFor(pubKeyHex).signature;

  Future<void> setSpeechMode(String pubKeyHex, PeerSpeechMode mode) =>
      _update(pubKeyHex, (PeerProfile p) => p.copyWith(speak: mode));

  Future<void> setSignature(String pubKeyHex, CueKind? slot) {
    assert(slot == null || isSignature(slot),
        'setSignature expects a signature slot, got $slot');
    return _update(
      pubKeyHex,
      (PeerProfile p) =>
          p.copyWith(signature: slot, clearSignature: slot == null),
    );
  }

  Future<void> _update(
      String pubKeyHex, PeerProfile Function(PeerProfile) edit) async {
    final String k = pubKeyHex.toLowerCase();
    if (k.isEmpty) return;
    final String? existing = resolveKey(k);
    final PeerProfile before =
        existing == null ? const PeerProfile() : _byKey[existing]!;
    final PeerProfile after = edit(before);

    // Re-key onto the longer form when we learn it, so a prefix-set
    // override converges on the full pubkey rather than accreting two
    // rows for one peer.
    final String key =
        (existing != null && existing.length > k.length) ? existing : k;
    final bool rekeyed = existing != null && existing != key;

    // Bail only when there is genuinely nothing to do. The re-key check
    // has to come first: re-setting a peer to the value it already has,
    // but via its *longer* key, changes no field and still needs to
    // migrate the row -- which is exactly how a prefix-set override
    // learns the full pubkey.
    if (after == before && !rekeyed) return;

    if (rekeyed) _byKey.remove(existing);
    if (after.isEmpty) {
      _byKey.remove(key);
    } else {
      _byKey[key] = after;
    }
    notifyListeners();
    await PeerProfileStore.save(_byKey);
  }
}
