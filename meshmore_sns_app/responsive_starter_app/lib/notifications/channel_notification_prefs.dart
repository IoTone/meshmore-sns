// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../util/prefs.dart';

/// What one channel slot is allowed to do when a message arrives (D8.13).
///
/// Per channel, because "silence the noisy one" is the actual need: a
/// global switch either loses an emergency or wakes the house. OS silence is
/// a channel setting here, not a device-wide mute.
@immutable
class ChannelNotificationPrefs {
  const ChannelNotificationPrefs({
    this.os = true,
    this.audio = false,
    this.haptic = true,
    this.tts = false,
    this.mentionsOnly = false,
    this.keySuffixMentions = false,
  });

  /// Post an OS notification.
  final bool os;

  /// Play the theme's cue.
  final bool audio;

  /// Vibrate.
  final bool haptic;

  /// Speak the message through the TTS layer.
  final bool tts;

  /// Only alert when the message names this device (D8.13). Off by default:
  /// turning it on for a busy channel is a deliberate act.
  final bool mentionsOnly;

  /// Also treat the public key's hex suffix as a mention. Off by default and
  /// not recommended — four hex characters are not an identity.
  final bool keySuffixMentions;

  ChannelNotificationPrefs copyWith({
    bool? os,
    bool? audio,
    bool? haptic,
    bool? tts,
    bool? mentionsOnly,
    bool? keySuffixMentions,
  }) =>
      ChannelNotificationPrefs(
        os: os ?? this.os,
        audio: audio ?? this.audio,
        haptic: haptic ?? this.haptic,
        tts: tts ?? this.tts,
        mentionsOnly: mentionsOnly ?? this.mentionsOnly,
        keySuffixMentions: keySuffixMentions ?? this.keySuffixMentions,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'os': os,
        'audio': audio,
        'haptic': haptic,
        'tts': tts,
        'mentionsOnly': mentionsOnly,
        'keySuffixMentions': keySuffixMentions,
      };

  static ChannelNotificationPrefs fromJson(Map<String, dynamic> j) =>
      ChannelNotificationPrefs(
        os: j['os'] as bool? ?? true,
        audio: j['audio'] as bool? ?? false,
        haptic: j['haptic'] as bool? ?? true,
        tts: j['tts'] as bool? ?? false,
        mentionsOnly: j['mentionsOnly'] as bool? ?? false,
        keySuffixMentions: j['keySuffixMentions'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is ChannelNotificationPrefs &&
      other.os == os &&
      other.audio == audio &&
      other.haptic == haptic &&
      other.tts == tts &&
      other.mentionsOnly == mentionsOnly &&
      other.keySuffixMentions == keySuffixMentions;

  @override
  int get hashCode =>
      Object.hash(os, audio, haptic, tts, mentionsOnly, keySuffixMentions);
}

/// The per-channel notification settings, persisted as one JSON map.
///
/// A slot with no stored entry takes [ChannelNotificationPrefs]'s defaults,
/// so adding a channel never inherits the last channel's silence.
class NotificationPrefs extends ChangeNotifier {
  NotificationPrefs({Map<int, ChannelNotificationPrefs>? seed})
      : _byChannel = <int, ChannelNotificationPrefs>{...?seed};

  static const String _key = 'mm.notifPrefs.v1';

  final Map<int, ChannelNotificationPrefs> _byChannel;

  ChannelNotificationPrefs prefsFor(int channelIdx) =>
      _byChannel[channelIdx] ?? const ChannelNotificationPrefs();

  Future<void> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
      _byChannel.clear();
      for (final MapEntry<String, dynamic> e in j.entries) {
        final int? idx = int.tryParse(e.key);
        if (idx == null) continue;
        _byChannel[idx] =
            ChannelNotificationPrefs.fromJson(e.value as Map<String, dynamic>);
      }
      notifyListeners();
    } catch (_) {
      // A corrupt blob is not worth a crash: every slot falls back to the
      // defaults, which is the state a new install has.
      _byChannel.clear();
    }
  }

  Future<void> setFor(int channelIdx, ChannelNotificationPrefs p) async {
    if (prefsFor(channelIdx) == p) return;
    _byChannel[channelIdx] = p;
    notifyListeners();
    final Map<String, dynamic> j = <String, dynamic>{
      for (final MapEntry<int, ChannelNotificationPrefs> e in _byChannel.entries)
        e.key.toString(): e.value.toJson(),
    };
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await Prefs.setString(prefs, _key, jsonEncode(j));
  }
}
