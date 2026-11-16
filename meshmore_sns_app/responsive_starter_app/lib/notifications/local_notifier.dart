// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../gen/app_localizations.dart';
import '../gen/app_localizations_en.dart';
import '../gen/app_localizations_ja.dart';
import 'message_notification.dart';
import 'notifier.dart';

/// The platform notifier: one OS channel per [NotificationClass].
///
/// D8.20 fixes the shape: high importance so a message shows on the lock
/// screen, a dedicated SOS channel that can be loud while the others are
/// silent, and **no full-screen intent** — the platform reserves those for
/// calls and alarms, and a mesh message is neither. Do-not-disturb is left to
/// the OS: the app never asks for policy access, so a user who silenced the
/// device stays silent.
/// The decision [LocalNotifier.refreshHealth] makes, kept pure so it can be
/// tested without a platform channel.
///
/// `blocked` outranks the rest because a disabled app cannot show anything;
/// a deleted channel outranks a quiet one because it fails rather than
/// whispers.
NotifierHealth healthFrom({
  required bool? enabled,
  required List<AndroidNotificationChannel>? channels,
  required Iterable<String> ourIds,
}) {
  if (enabled == false) return NotifierHealth.blocked;
  if (channels == null) return NotifierHealth.ok;
  final Map<String, AndroidNotificationChannel> byId =
      <String, AndroidNotificationChannel>{
    for (final AndroidNotificationChannel c in channels) c.id: c,
  };
  bool quiet = false;
  for (final String id in ourIds) {
    final AndroidNotificationChannel? c = byId[id];
    if (c == null) return NotifierHealth.missingChannel;
    if (c.importance.index < Importance.high.index) quiet = true;
  }
  return quiet ? NotifierHealth.quiet : NotifierHealth.ok;
}

/// What the group summary says, and where a tap on it goes.
///
/// Pure so the two things that matter can be asserted without a platform
/// channel: the count the user is shown, and the payload the tap carries.
/// Tapping an OS auto-summary carried nothing, which is how a tap on "2
/// messages" landed on whichever thread was last open.
({int count, String payload, String body}) groupSummaryFor({
  required List<String> recentPayloads,
  required String newestPayload,
  required String newestBody,
  required AppLocalizations strings,
}) {
  final int count = recentPayloads.isEmpty ? 1 : recentPayloads.length;
  return (
    count: count,
    payload: newestPayload,
    body: strings.notifGroupBody(count, newestBody),
  );
}

/// Whether opening [opened] should also clear the batch line.
///
/// Pure, because the call it guards is a platform cancel and the rule is what
/// can be wrong: a batch standing for `ch:2` must not survive the user opening
/// `ch:2`, and must not be cleared by opening `ch:5`.
bool digestClearedBy({required String opened, required String digestPayload}) =>
    opened.isNotEmpty && opened == digestPayload;

class LocalNotifier implements Notifier {
  LocalNotifier({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Set by the app so a tap can route. Called with the notification payload.
  ///
  /// A tap that launched the app arrives from `init`, which runs before the
  /// router exists; that payload waits here until the handler is set, so a
  /// notification tapped from a cold start still opens its thread instead of
  /// landing on the Dashboard.
  set onTap(void Function(String payload)? handler) {
    _onTap = handler;
    final String? pending = _pendingTap;
    if (pending != null && handler != null) {
      _pendingTap = null;
      handler(pending);
    }
  }

  void Function(String payload)? get onTap => _onTap;

  void Function(String payload)? _onTap;
  String? _pendingTap;

  void _deliver(String payload) {
    if (payload.isEmpty) return;
    final void Function(String payload)? handler = _onTap;
    if (handler == null) {
      _pendingTap = payload;
      return;
    }
    handler(payload);
  }

  bool _inited = false;

  /// The OS groups notifications on one channel into an auto-summary, and that
  /// summary carries no payload, so tapping it landed the app on whatever thread
  /// was last open. On a busy mesh the summary is the row most thumbs hit, so
  /// the group is explicit now: every message joins [_groupKey] and one summary
  /// is posted with the newest payload, which means a summary tap opens the
  /// message the user was told about.
  static const String _groupKey = 'mm_messages';

  /// The summary's own id, outside the per-message range the controller picks.
  static const int summaryId = 0;

  /// The batch line's own id, so a growing catch-up queue rewrites one entry
  /// instead of stacking a second, a third and a twelfth.
  static const int digestId = 1;

  /// Payloads posted, oldest first, bounded: the summary routes to the newest
  /// and the count only has to be plausible.
  final List<String> _recentPayloads = <String>[];
  static const int _recentMax = 20;

  /// The thread the batch line routes to, so opening that thread clears it the
  /// same way it clears the messages' own entries. Empty when no batch line is
  /// showing.
  String _digestPayload = '';

  /// Notification ids still on screen, per tap payload, so a thread that is
  /// opened can clear exactly its own notifications and leave the rest.
  final Map<String, Set<int>> _live = <String, Set<int>>{};

  /// What a channel is allowed to do to the phone.
  ///
  /// Every one of these used to be created at high importance with a sound, so a
  /// public channel with a dozen people talking beeped a dozen times: the owner
  /// reported the phone beeping while the app was not even open. A channel is
  /// chatter and it waits in the tray; a direct message and an emergency are
  /// addressed to this reader and are worth a sound.
  static const Map<String, ({String name, String description, Importance importance, bool sound})>
      _channels =
      <String, ({String name, String description, Importance importance, bool sound})>{
    // The identifier changed with the rule. Android keeps the settings a channel
    // was created with, so lowering the importance of the existing one would
    // never reach a phone that already has it.
    'mm_messages_channel2': (
      name: 'Channel messages',
      description: 'Messages received on a channel from anyone on the mesh.',
      importance: Importance.defaultImportance,
      sound: false,
    ),
    'mm_messages_direct': (
      name: 'Direct messages',
      description: 'Messages addressed to you by one peer.',
      importance: Importance.high,
      sound: true,
    ),
    'mm_messages_sos': (
      name: 'Emergency alerts',
      description: 'SOS and its acknowledgements.',
      importance: Importance.high,
      sound: true,
    ),
    // Its own channel, so a reader can silence the fences they drew without
    // silencing the messages they are waiting for, and the other way round.
    'mm_geofence': (
      name: 'Fence crossings',
      description: 'When you walk into or out of a fence you drew.',
      importance: Importance.high,
      sound: true,
    ),
  };

  @override
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    await _plugin.initialize(
      settings: const InitializationSettings(
        // A dedicated white-on-transparent glyph, not the launcher icon: the OS
        // masks the small icon to one colour, so a full-colour launcher asset
        // shows as a grey blob. This also stopped being available when the
        // duplicate `ic_launcher` icon set was removed on 2026-11-05, which made
        // initialisation throw `invalid_icon` and took every OS notification
        // with it — found on the handset, not by a test.
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        // iOS is deprioritised this phase; the settings are still valid so
        // the same notifier compiles and behaves there.
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse r) {
        final String? payload = r.payload;
        if (payload != null) _deliver(payload);
      },
    );
    // The tap that launched the process is not delivered to the callback
    // above; it is only readable here, once.
    final NotificationAppLaunchDetails? launch =
        await _plugin.getNotificationAppLaunchDetails();
    if (launch != null && launch.didNotificationLaunchApp) {
      final String? payload = launch.notificationResponse?.payload;
      if (payload != null) _deliver(payload);
    }
    if (!Platform.isAndroid) return;
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    for (final MapEntry<String, ({String name, String description, Importance importance, bool sound})>
        e in _channels.entries) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          e.key,
          e.value.name,
          description: e.value.description,
          importance: e.value.importance,
          playSound: e.value.sound,
        ),
      );
    }
    await refreshHealth();
    // Asked once, at the first message-capable start; a denial is not an
    // error (D8.21) — the in-app banner in Settings says what will not
    // appear and the app keeps working.
    await android.requestNotificationsPermission();
  }

  @override
  Future<void> show(MessageNotification n) async {
    final ({String name, String description, Importance importance, bool sound})
        ch = _channels[n.channelId]!;
    // A fence crossing is not a message: it stays out of the message group, so
    // the group's "N messages" summary never counts one and a tap on that
    // summary never opens a fence.
    final bool grouped = joinsMessageGroup(n.cls);
    final AndroidNotificationDetails android = AndroidNotificationDetails(
      n.channelId,
      ch.name,
      channelDescription: ch.description,
      importance: Importance.high,
      priority: Priority.high,
      category: switch (n.cls) {
        NotificationClass.sos => AndroidNotificationCategory.alarm,
        // A fence is a reminder the reader set for themselves, not a call and
        // not a message.
        NotificationClass.geofence => AndroidNotificationCategory.reminder,
        NotificationClass.channel ||
        NotificationClass.direct =>
          AndroidNotificationCategory.message,
      },
      onlyAlertOnce: false,
      autoCancel: true,
      // A message is not a call: never a full-screen intent.
      fullScreenIntent: false,
      groupKey: grouped ? _groupKey : null,
    );
    (_live[n.payload] ??= <int>{}).add(n.id);
    await _plugin.show(
      id: n.id,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: android,
        iOS: const DarwinNotificationDetails(),
      ),
      payload: n.payload,
    );
    if (!grouped) return;
    _rememberPayload(n.payload);
    await _postSummary(n);
  }

  /// The batch line: one entry for a queue, replaced in place as it grows.
  ///
  /// `onlyAlertOnce` is what makes a burst behave: the first post alerts, and
  /// every later count inside the same catch-up window rewrites the same id, so
  /// a dozen queued messages are one sound and one entry reading "12 unread
  /// messages" rather than twelve of each.
  ///
  /// It does not post a group summary of its own. The entry already stands for
  /// the whole queue, and a summary counted beside it would state the same
  /// number twice.
  @override
  Future<void> showDigest(MessageDigest d) async {
    final ({String name, String description, Importance importance, bool sound})
        ch = _channels[d.channelId]!;
    await _plugin.show(
      id: digestId,
      title: d.title,
      body: d.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          d.channelId,
          ch.name,
          channelDescription: ch.description,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          onlyAlertOnce: true,
          autoCancel: true,
          fullScreenIntent: false,
          groupKey: _groupKey,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: d.payload,
    );
    _digestPayload = d.payload;
  }

  /// Drop the batch entry so the next burst can alert again.
  ///
  /// The digest is one id with `onlyAlertOnce: true`, which is what makes a
  /// burst one sound instead of twelve. The cost was that every burst after the
  /// first rewrote the same entry silently until the user opened the thread it
  /// pointed at, so a reader who never opened that thread got one audible
  /// digest and then nothing. Clearing it when a new catch-up window opens
  /// keeps "one sound per burst" and removes "silent forever".
  @override
  Future<void> clearDigest() async {
    _digestPayload = '';
    await _plugin.cancel(id: digestId);
  }

  /// Two bundles ship, so anything but Japanese is English.
  AppLocalizations get _strings {
    final Locale device = WidgetsBinding.instance.platformDispatcher.locale;
    return device.languageCode == 'ja'
        ? AppLocalizationsJa()
        : AppLocalizationsEn();
  }

  void _rememberPayload(String payload) {
    if (payload.isEmpty) return;
    _recentPayloads.remove(payload);
    _recentPayloads.add(payload);
    while (_recentPayloads.length > _recentMax) {
      _recentPayloads.removeAt(0);
    }
  }

  /// The explicit group summary, silent and replaced in place.
  ///
  /// Silent because the child that just arrived already alerted: a summary that
  /// also sounded would double every cue.
  Future<void> _postSummary(MessageNotification newest) async {
    final ({String name, String description, Importance importance, bool sound})
        ch = _channels[newest.channelId]!;
    final ({int count, String payload, String body}) summary =
        groupSummaryFor(
      recentPayloads: _recentPayloads,
      newestPayload: newest.payload,
      newestBody: newest.body,
      strings: _strings,
    );
    await _plugin.show(
      id: summaryId,
      title: newest.title,
      // The device's language, built directly: this layer has no BuildContext
      // and no delegate, and a summary is not worth a second load path.
      body: summary.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          newest.channelId,
          ch.name,
          channelDescription: ch.description,
          importance: Importance.high,
          priority: Priority.high,
          groupKey: _groupKey,
          setAsGroupSummary: true,
          onlyAlertOnce: true,
          silent: true,
          autoCancel: true,
          fullScreenIntent: false,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: summary.payload,
    );
  }

  /// The last state read from the OS, and the channels it reported.
  NotifierHealth _health = NotifierHealth.ok;
  @override
  Future<NotifierHealth> health({bool refresh = false}) async =>
      refresh ? refreshHealth() : _health;

  /// Reads the OS back and recreates a channel the user deleted.
  ///
  /// Called from [init] and when the notification settings are opened, which
  /// are the two moments the answer can have changed. A missing channel is
  /// recreated silently: it is the app's own channel id, and a deleted one
  /// means notifications would fail rather than arrive quiet.
  Future<NotifierHealth> refreshHealth() async {
    if (!Platform.isAndroid) return _health = NotifierHealth.ok;
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return _health = NotifierHealth.ok;
    try {
      final bool? enabled = await android.areNotificationsEnabled();
      final List<AndroidNotificationChannel>? live =
          enabled == false ? null : await android.getNotificationChannels();
      final NotifierHealth read = healthFrom(
        enabled: enabled,
        channels: live,
        ourIds: _channels.keys,
      );
      if (read == NotifierHealth.missingChannel) {
        // Recreate what was deleted: the ids are ours, and a missing channel
        // fails a notification instead of showing it quietly.
        for (final MapEntry<String, ({String name, String description, Importance importance, bool sound})>
            e in _channels.entries) {
          await android.createNotificationChannel(AndroidNotificationChannel(
            e.key,
            e.value.name,
            description: e.value.description,
            importance: e.value.importance,
            playSound: e.value.sound,
          ));
        }
      }
      return _health = read;
    } catch (_) {
      return _health = NotifierHealth.ok;
    }
  }

  @override
  Future<void> cancel(int id) async {
    for (final Set<int> ids in _live.values) {
      ids.remove(id);
    }
    await _plugin.cancel(id: id);
    // The summary outlives its children otherwise, and a stale count with a
    // payload that has already been read is worse than no summary.
    if (_live.isEmpty) {
      _recentPayloads.clear();
      await _plugin.cancel(id: summaryId);
    }
  }

  @override
  Future<void> cancelFor(String payload) async {
    // A batch line stands for the messages whose thread this is, so opening
    // that thread clears it. Without this it stayed on the lock screen after
    // the user had read every message it counted.
    if (digestClearedBy(opened: payload, digestPayload: _digestPayload)) {
      _digestPayload = '';
      await _plugin.cancel(id: digestId);
    }
    final Set<int>? ids = _live.remove(payload);
    if (ids == null) return;
    for (final int id in ids) {
      await _plugin.cancel(id: id);
    }
    _recentPayloads.remove(payload);
    if (_live.isEmpty) {
      _recentPayloads.clear();
      await _plugin.cancel(id: summaryId);
    }
  }
}
