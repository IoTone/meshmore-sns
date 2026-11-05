// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'message_notification.dart';
import 'notifier.dart';

/// The platform notifier: three OS channels, one per [NotificationClass].
///
/// D8.20 fixes the shape: high importance so a message shows on the lock
/// screen, a dedicated SOS channel that can be loud while the others are
/// silent, and **no full-screen intent** — the platform reserves those for
/// calls and alarms, and a mesh message is neither. Do-not-disturb is left to
/// the OS: the app never asks for policy access, so a user who silenced the
/// device stays silent.
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

  /// Notification ids still on screen, per tap payload, so a thread that is
  /// opened can clear exactly its own notifications and leave the rest.
  final Map<String, Set<int>> _live = <String, Set<int>>{};

  static const Map<String, ({String name, String description})> _channels =
      <String, ({String name, String description})>{
    'mm_messages_channel': (
      name: 'Channel messages',
      description: 'Messages received on a channel from anyone on the mesh.',
    ),
    'mm_messages_direct': (
      name: 'Direct messages',
      description: 'Messages addressed to you by one peer.',
    ),
    'mm_messages_sos': (
      name: 'Emergency alerts',
      description: 'SOS and its acknowledgements.',
    ),
  };

  @override
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
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
    for (final MapEntry<String, ({String name, String description})> e
        in _channels.entries) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          e.key,
          e.value.name,
          description: e.value.description,
          importance: Importance.high,
          playSound: true,
        ),
      );
    }
    // Asked once, at the first message-capable start; a denial is not an
    // error (D8.21) — the in-app banner in Settings says what will not
    // appear and the app keeps working.
    await android.requestNotificationsPermission();
  }

  @override
  Future<void> show(MessageNotification n) async {
    final ({String name, String description}) ch = _channels[n.channelId]!;
    final AndroidNotificationDetails android = AndroidNotificationDetails(
      n.channelId,
      ch.name,
      channelDescription: ch.description,
      importance: Importance.high,
      priority: Priority.high,
      category: n.cls == NotificationClass.sos
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.message,
      onlyAlertOnce: false,
      autoCancel: true,
      // A message is not a call: never a full-screen intent.
      fullScreenIntent: false,
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
  }

  @override
  Future<void> cancel(int id) async {
    for (final Set<int> ids in _live.values) {
      ids.remove(id);
    }
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelFor(String payload) async {
    final Set<int>? ids = _live.remove(payload);
    if (ids == null) return;
    for (final int id in ids) {
      await _plugin.cancel(id: id);
    }
  }
}
