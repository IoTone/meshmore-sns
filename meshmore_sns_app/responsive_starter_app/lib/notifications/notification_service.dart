// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import '../gen/app_localizations.dart';
import '../meshcore/chat_message.dart';
import 'channel_notification_prefs.dart';
import 'mention_matcher.dart';
import '../sos/sos_message.dart';
import 'message_notification.dart';
import 'notification_focus.dart';
import 'notifier.dart';

/// What the app does around a notification, besides posting it.
///
/// The per-channel bundle has four switches (D8.13), and the OS answers only
/// one of them. Cue, vibration and speech are the app's, so they sit behind
/// this seam: the service decides *whether* from the channel's settings, and
/// the app decides *how*.
abstract interface class NotificationEffects {
  /// Play the theme's inbound cue.
  void cue(NotificationClass cls);

  /// Vibrate for an inbound message.
  void vibrate();

  /// Read [text] aloud for [channelIdx] through the TTS layer, which keeps
  /// its own per-channel mute and voice.
  void speakChannel(int channelIdx, String text);
}

/// The effects a harness gets: nothing.
class SilentNotificationEffects implements NotificationEffects {
  const SilentNotificationEffects();

  @override
  void cue(NotificationClass cls) {}

  @override
  void vibrate() {}

  @override
  void speakChannel(int channelIdx, String text) {}
}

/// The strings a notification needs, behind one call so the service can be
/// tested without a widget tree and can follow a locale change.
abstract interface class NotificationStrings {
  /// The bold line the OS shows. [name] is the channel name or the peer's.
  String title(NotificationClass cls, String? name);

  /// The body for an SOS, which never carries the coordinates.
  ///
  /// An SOS text is `[SOS:<id6>] <lat>,<lon> <callsign> …`, and the lock
  /// screen is not where a position should be published: the diagnostics
  /// redactor treats coordinates as opt-in, so the one surface that shows text
  /// without the user opening the app must not publish them either. The full
  /// text stays in the thread.
  String sosBody();

  /// The body of the catch-up line: how many messages are waiting, and
  /// nothing about their contents. A queue is read in the app, not on a lock
  /// screen.
  String unreadDigest(int count);

  /// The body of the ongoing notification shown while an alarm repeats.
  /// Deliberately not the message text: this line is about the alarm, and it
  /// stays on screen until the alarm ends.
  String alarmRunningBody();

  /// The line a fence crossing shows. [entry] is true walking in and false
  /// walking out, so the pair cannot be confused on a lock screen.
  String fenceCrossed(String label, {required bool entry});

  /// The honest second line under a fence crossing.
  ///
  /// A fence is evaluated against the position fixes the app already has, so a
  /// crossing is only seen when one arrives. The notification says so rather
  /// than implying the app is watching continuously.
  String fenceCrossedBody();
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
      // A fence crossing has two titles and the direction decides which, so it
      // never comes through here: see [fenceCrossed]. Reaching this arm is a
      // programming error, and it says so rather than inventing a title.
      NotificationClass.geofence =>
        throw StateError('a fence crossing is titled by fenceCrossed'),
    };
  }

  @override
  String fenceCrossed(String label, {required bool entry}) =>
      entry ? l10n.geofenceEntered(label) : l10n.geofenceLeft(label);

  @override
  String fenceCrossedBody() => l10n.notifBodyFence;

  @override
  String sosBody() => l10n.notifBodySos;

  @override
  String unreadDigest(int count) => l10n.notifUnreadDigest(count);

  @override
  String alarmRunningBody() => l10n.notifAlarmRunningBody;
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
    this.isBlocked,
    NotificationEffects effects = const SilentNotificationEffects(),
    this.catchUpMinGap = const Duration(seconds: 20),
  }) : _effects = effects;

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

  /// The block filter, when the app has one. A blocked key raises no
  /// notification, no cue, no vibration and no speech: the same rule the
  /// timeline follows, applied before anything is shown (`block-spec` §5).
  final bool Function(ChatMessage message)? isBlocked;

  NotificationEffects _effects;

  /// The app attaches the real cue/vibration/speech after its first frame,
  /// when the providers that own them exist. Before that the effects are
  /// silent, which is also what a harness gets.
  set effects(NotificationEffects e) => _effects = e;

  StreamSubscription<ChatMessage>? _channelSub;
  StreamSubscription<ChatMessage>? _dmSub;

  /// How long a burst keeps counting as catch-up after the last message.
  ///
  /// The radio hands over its whole queue when the link comes up, one frame at
  /// a time, and the gaps between those frames are small but not zero. Three
  /// seconds of quiet is the end of the queue.
  Duration catchUpIdle = const Duration(seconds: 3);

  /// The longest a catch-up window may run, so a radio that keeps dribbling
  /// messages cannot hold the queue open forever.
  Duration catchUpMax = const Duration(seconds: 20);

  bool _catchingUp = false;
  int _catchUpCount = 0;
  Timer? _catchUpIdleTimer;
  Timer? _catchUpMaxTimer;

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
    _catchUpIdleTimer?.cancel();
    _catchUpMaxTimer?.cancel();
    await _channelSub?.cancel();
    await _dmSub?.cancel();
    _channelSub = null;
    _dmSub = null;
    _started = false;
  }

  /// The OS id for a message, stable for the life of the message **and across
  /// processes**: `String.hashCode` is not guaranteed stable between runs, and
  /// `cancelFor` targets ids that were posted by an earlier process. FNV-1a
  /// over the id is the same number every run.
  static int idFor(String messageId) {
    int h = 0x811C9DC5;
    for (final int unit in messageId.codeUnits) {
      h ^= unit & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h & 0x7FFFFFFF;
  }

  void _onChannel(ChatMessage m) {
    if (m.outgoing) return;
    if (isBlocked?.call(m) ?? false) return;
    if (!_firstTime(m.id)) return;
    final bool sos = isSosLine(m.text);
    // The channel's bundle is read once: `muted` is a master silence, and the
    // four switches below only refine it. An SOS outranks the silence, the
    // same way it outranks a muted cue — a channel quieted for chatter must
    // not swallow a distress call.
    final ChannelNotificationPrefs p = prefs.prefsFor(m.channelIdx);
    if (!sos) {
      if (focus.isChannelOpen(m.channelIdx)) return;
      if (p.muted) return;
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
    // A queue handed over when the link comes up is one event. Counting it
    // here — after every silence rule has already decided the message would
    // have been announced — keeps a muted channel muted and turns the rest into
    // a single "N unread messages" line. An SOS never takes this path.
    if (_catchingUp && !sos) {
      _absorb(cls, channelName(m.channelIdx), 'ch:${m.channelIdx}');
      return;
    }
    // The bundle's other three switches. Honoured here rather than in the
    // notifier, because a cue and a vibration are the app's, not the OS's,
    // and a silent channel must not cue either.
    final ChannelNotificationPrefs bundle = p;
    // An SOS is loud whatever the channel's bundle says: the OS channel is
    // the user's control for its silence, and a channel that was muted for
    // chatter must not mute a distress call with it.
    if (bundle.audio || sos) _effects.cue(cls);
    if (bundle.haptic || sos) _effects.vibrate();
    if (bundle.tts) _effects.speakChannel(m.channelIdx, m.text);
    notifier.show(MessageNotification(
      id: idFor(m.id),
      cls: cls,
      title: strings().title(cls, channelName(m.channelIdx)),
      body: sos ? strings().sosBody() : m.text,
      payload: 'ch:${m.channelIdx}',
    ));
  }

  void _onDirect(ChatMessage m) {
    if (m.outgoing) return;
    if (isBlocked?.call(m) ?? false) return;
    if (!_firstTime(m.id)) return;
    final String key = m.peerPubKeyHex ?? '';
    if (focus.isPeerOpen(key)) return;
    final String? name = peerDisplayName(key);
    final bool sos = isSosLine(m.text);
    if (_catchingUp && !sos) {
      _absorb(NotificationClass.direct, name ?? key, 'dm:$key');
      return;
    }
    _effects.cue(NotificationClass.direct);
    _effects.vibrate();
    notifier.show(MessageNotification(
      id: idFor(m.id),
      cls: sos ? NotificationClass.sos : NotificationClass.direct,
      title: strings().title(
          sos ? NotificationClass.sos : NotificationClass.direct, name ?? key),
      body: sos ? strings().sosBody() : m.text,
      payload: 'dm:$key',
    ));
  }

  /// The link just reached ready, so the radio is about to hand over whatever
  /// queued while the phone was away.
  ///
  /// Everything that arrives before the queue falls quiet is counted into one
  /// entry rather than announced one message at a time. The window closes after
  /// [catchUpIdle] with nothing new, or after [catchUpMax] whatever happens, and
  /// from then on a message is announced on its own — which is what "only when
  /// already connected" means: connected *and* caught up.
  void onLinkReady() {
    // A reconnect is not automatically a backlog. The BLE link flaps, and
    // treating every flap as a queue meant ordinary traffic arriving just after
    // a reconnect was counted into a silent digest instead of announced. Only
    // an absence long enough to have queued something counts.
    final DateTime now = DateTime.now();
    final DateTime? down = _linkDownAt;
    _linkDownAt = null;
    final bool wasAway = down != null && now.difference(down) >= catchUpMinGap;
    if (!wasAway) {
      _catchingUp = false;
      return;
    }
    _catchingUp = true;
    _catchUpCount = 0;
    _catchUpIdleTimer?.cancel();
    _catchUpMaxTimer?.cancel();
    _catchUpMaxTimer = Timer(catchUpMax, _flushCatchUp);
    // A new window may alert: the previous digest is dropped so its
    // `onlyAlertOnce` cannot silence this burst.
    unawaited(notifier.clearDigest());
  }

  /// When the link last left ready, so a reconnect can tell a flap from an
  /// absence.
  DateTime? _linkDownAt;

  /// The shortest absence that counts as a backlog. Below this the link merely
  /// blinked, and the messages are ordinary traffic. Injectable so a test can
  /// exercise the window without waiting twenty seconds.
  final Duration catchUpMinGap;

  /// Called when the link leaves ready.
  void onLinkDown() {
    _linkDownAt = DateTime.now();
    _catchingUp = false;
  }

  /// Whether a queue is being counted right now. Read by tests and by anything
  /// that wants to say "catching up" without guessing.
  bool get isCatchingUp => _catchingUp;

  void _absorb(
    NotificationClass cls,
    String? name,
    String payload,
  ) {
    _catchUpCount++;
    // The batch's one cue: the OS entry alerts on its first post because
    // `onlyAlertOnce` silences the rewrites, and the app's own cue follows the
    // same rule.
    if (_catchUpCount == 1) {
      _effects.cue(cls);
      _effects.vibrate();
    }
    _catchUpIdleTimer?.cancel();
    _catchUpIdleTimer = Timer(catchUpIdle, _flushCatchUp);
    notifier.showDigest(MessageDigest(
      count: _catchUpCount,
      cls: cls,
      title: strings().title(cls, name),
      body: strings().unreadDigest(_catchUpCount),
      payload: payload,
    ));
  }

  void _flushCatchUp() {
    _catchUpIdleTimer?.cancel();
    _catchUpMaxTimer?.cancel();
    _catchUpIdleTimer = null;
    _catchUpMaxTimer = null;
    _catchingUp = false;
    _catchUpCount = 0;
  }

  /// Whether an alarm is repeating, as the OS should show it.
  ///
  /// The alarm screen is not the only place a user can be: an armed alarm left
  /// running while they read chat needs one ambient sign, or a backgrounded
  /// alarm reads as stopped. A fixed id replaces the same notification rather
  /// than stacking, and cancelling it is the end of the alarm.
  Future<void> setAlarmRunning(bool running) async {
    if (running == _alarmRunning) return;
    _alarmRunning = running;
    if (!running) {
      await notifier.cancel(NotificationService.alarmNotificationId);
      return;
    }
    await notifier.show(MessageNotification(
      id: NotificationService.alarmNotificationId,
      cls: NotificationClass.sos,
      title: strings().title(NotificationClass.sos, null),
      body: strings().alarmRunningBody(),
      payload: 'sos:',
    ));
  }

  bool _alarmRunning = false;

  /// A fence crossing, posted through the same notifier as a message.
  ///
  /// One OS id per fence, so walking in and out of the same fence replaces the
  /// previous entry instead of stacking a second one, and a re-entry after a
  /// restart lands on the entry that is already there. The id is derived the
  /// same way a message's is, because `String.hashCode` is not stable between
  /// processes and `cancelFor` targets ids an earlier process posted.
  ///
  /// The cue is not played here: a crossing has two cues and the direction
  /// decides which, so `GeofenceController.onRaised` plays it beside this call.
  void onGeofence({
    required String fenceId,
    required String label,
    required bool entry,
  }) {
    notifier.show(MessageNotification(
      id: idFor('fence:$fenceId'),
      cls: NotificationClass.geofence,
      title: strings().fenceCrossed(label, entry: entry),
      body: strings().fenceCrossedBody(),
      payload: 'fence:$fenceId',
    ));
  }

  /// The alarm's own notification id: far from any message's digest range in
  /// practice, and fixed so replacing it never stacks.
  static const int alarmNotificationId = 0x5A5A5A;

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
