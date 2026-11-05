// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import '../gen/app_localizations.dart';
import '../meshcore/chat_message.dart';
import 'channel_notification_prefs.dart';
import 'mention_matcher.dart';
import 'message_notification.dart';
import 'notification_focus.dart';
import 'notifier.dart';

/// The strings a notification needs, behind one call so the service can be
/// tested without a widget tree and can follow a locale change.
abstract interface class NotificationStrings {
  /// The bold line the OS shows. [name] is the channel name or the peer's.
  String title(NotificationClass cls, String? name);
}

/// [NotificationStrings] over the generated ARB bundle.
class LocalizedNotificationStrings implements NotificationStrings {
  const LocalizedNotificationStrings(this.l10n);

  final AppLocalizations l10n;

  @override
  String title(NotificationClass cls, String? name) {
    final String who = (name == null || name.isEmpty) ? '?' : name;
    return switch (cls) {
      NotificationClass.channel => l10n.notifTitleChannel(who),
      NotificationClass.direct => l10n.notifTitleDirect(who),
      NotificationClass.sos => l10n.notifTitleSos,
    };
  }
}

/// Decides which inbound messages become notifications, and which do not.
///
/// Every rule here was fixed elsewhere, so the tests are the decision made
/// executable:
/// - a message already on screen is not announced;
/// - a channel's own settings decide silence, and mentions-only narrows it;
/// - one message notifies once, however often a reconnect replays it;
/// - an SOS outranks a channel's silence, because the SOS OS channel is the
///   user's control for it (D8.20).
class NotificationService {
  NotificationService({
    required this.channelMessages,
    required this.directMessages,
    required this.notifier,
    required this.prefs,
    required this.focus,
    required this.strings,
    required this.selfDisplayName,
    required this.ownPubKeyHex,
    required this.peerDisplayName,
    required this.channelName,
  });

  /// One notification per inbound message, never per transport event.
  final Stream<ChatMessage> channelMessages;
  final Stream<ChatMessage> directMessages;

  final Notifier notifier;
  final NotificationPrefs prefs;
  final NotificationFocus focus;
  final NotificationStrings Function() strings;

  /// This device's display name, for mention matching.
  final String? Function() selfDisplayName;

  /// This device's public key, for the key-suffix opt-in.
  final String? Function() ownPubKeyHex;

  /// A peer's display name for the DM title, given the full or short key.
  final String? Function(String peerKey) peerDisplayName;

  /// A channel slot's name, or its index when the radio has not listed it.
  final String Function(int slot) channelName;

  StreamSubscription<ChatMessage>? _channelSub;
  StreamSubscription<ChatMessage>? _dmSub;

  /// Message ids already announced this process. Bounded: a long session must
  /// not grow the set forever, and the oldest id is the least likely replay.
  final Set<String> _announced = <String>{};
  static const int _announcedCap = 200;

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _channelSub = channelMessages.listen(_onChannel);
    _dmSub = directMessages.listen(_onDirect);
  }

  Future<void> dispose() async {
    await _channelSub?.cancel();
    await _dmSub?.cancel();
    _channelSub = null;
    _dmSub = null;
    _started = false;
  }

  /// The OS id for a message, stable for the life of the message.
  static int idFor(String messageId) => messageId.hashCode & 0x7FFFFFFF;

  void _onChannel(ChatMessage m) {
    if (m.outgoing) return;
    if (!_firstTime(m.id)) return;
    final bool sos = m.text.toUpperCase().startsWith('[SOS:');
    if (!sos) {
      if (focus.isChannelOpen(m.channelIdx)) return;
      final ChannelNotificationPrefs p = prefs.prefsFor(m.channelIdx);
      if (!p.os) return;
      final bool mentioned = isMentioned(
        m.text,
        selfDisplayName(),
        keySuffix: ownPubKeyHex(),
        matchKeySuffix: p.keySuffixMentions,
      );
      if (p.mentionsOnly && !mentioned) return;
    }
    final NotificationClass cls =
        sos ? NotificationClass.sos : NotificationClass.channel;
    notifier.show(MessageNotification(
      id: idFor(m.id),
      cls: cls,
      title: strings().title(cls, channelName(m.channelIdx)),
      body: m.text,
      payload: 'ch:${m.channelIdx}',
    ));
  }

  void _onDirect(ChatMessage m) {
    if (m.outgoing) return;
    if (!_firstTime(m.id)) return;
    final String key = m.peerPubKeyHex ?? '';
    if (focus.isPeerOpen(key)) return;
    final String? name = peerDisplayName(key);
    notifier.show(MessageNotification(
      id: idFor(m.id),
      cls: NotificationClass.direct,
      title: strings().title(NotificationClass.direct, name ?? key),
      body: m.text,
      payload: 'dm:$key',
    ));
  }

  /// True the first time [id] is seen. A replayed frame, a re-subscribed
  /// stream or a reconnect must not announce the same message twice.
  bool _firstTime(String id) {
    if (!_announced.add(id)) return false;
    if (_announced.length > _announcedCap) {
      _announced.remove(_announced.first);
    }
    return true;
  }
}
