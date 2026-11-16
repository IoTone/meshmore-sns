// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:meshcore/meshcore.dart' show kPublicChannelPsk;

/// A conversation the bot can be bound to (R59).
///
/// Two kinds only: a channel slot, or a DM with one peer. Both carry a
/// stable [key] used for persistence and for per-scope counters.
sealed class BotScope {
  const BotScope();

  /// Stable identifier, safe to persist.
  String get key;

  static BotScope? fromKey(String key) {
    if (key.startsWith('ch:')) {
      final int? idx = int.tryParse(key.substring(3));
      return idx == null ? null : ChannelScope(idx);
    }
    if (key.startsWith('dm:')) {
      final String hex = key.substring(3);
      return hex.isEmpty ? null : DmScope(hex);
    }
    return null;
  }
}

class ChannelScope extends BotScope {
  const ChannelScope(this.idx);
  final int idx;

  @override
  String get key => 'ch:$idx';

  @override
  bool operator ==(Object other) => other is ChannelScope && other.idx == idx;
  @override
  int get hashCode => idx.hashCode;
  @override
  String toString() => key;
}

class DmScope extends BotScope {
  DmScope(String pubKeyHex) : pubKeyHex = pubKeyHex.toLowerCase();
  final String pubKeyHex;

  @override
  String get key => 'dm:$pubKeyHex';

  @override
  bool operator ==(Object other) =>
      other is DmScope && other.pubKeyHex == pubKeyHex;
  @override
  int get hashCode => pubKeyHex.hashCode;
  @override
  String toString() => key;
}

/// Why a scope may not host a bot.
enum BotRefusal {
  /// Slot 0 is Public by definition, whatever key it currently holds.
  publicSlot,

  /// The slot's key IS the well-known public PSK, so anything sent
  /// there is readable by every stock radio on the mesh — it is Public
  /// under another number.
  publicPsk,

  /// We have not seen this slot's key yet, so we cannot prove it is
  /// private. Refusing until we can is the safe direction: the cost of
  /// a wrong "no" is a delay, the cost of a wrong "yes" is a bot
  /// talking on Public.
  unknownPsk,
}

/// Whether a scope may host a bot, and why not when it may not.
///
/// This is the **structural** enforcement the spec calls for. The
/// refusal lives here, in the binding path, rather than in a hidden
/// control: a UI that forgot to grey out a switch, a restored
/// preference from an older build, or a future call site that never
/// heard of Public all hit the same gate.
///
/// [pskFor] resolves a channel slot's 16-byte key, or null when we
/// have not observed it.
BotRefusal? botRefusalFor(
  BotScope scope,
  List<int>? Function(int idx) pskFor,
) {
  switch (scope) {
    case DmScope():
      // A DM is end-to-end between two identified parties; there is no
      // Public equivalent to protect.
      return null;
    case ChannelScope(idx: final int idx):
      if (idx == 0) return BotRefusal.publicSlot;
      final List<int>? psk = pskFor(idx);
      if (psk == null) return BotRefusal.unknownPsk;
      return pskIsPublic(psk) ? BotRefusal.publicPsk : null;
  }
}

/// Byte-equality against the well-known Public PSK.
///
/// A slot that still holds this key is Public no matter what it is
/// named or numbered — renaming slot 3 to "Ops" while leaving the
/// stock key in place protects nothing.
bool pskIsPublic(List<int> psk) {
  if (psk.length != kPublicChannelPsk.length) return false;
  for (int i = 0; i < psk.length; i++) {
    if (psk[i] != kPublicChannelPsk[i]) return false;
  }
  return true;
}
