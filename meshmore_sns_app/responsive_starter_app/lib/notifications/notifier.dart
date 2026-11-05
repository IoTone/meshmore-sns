// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'message_notification.dart';

/// Whether the OS is still letting our notifications be loud.
///
/// Created at init and read when the user opens the notification settings:
/// a channel the user deleted or lowered is invisible otherwise, and the app
/// would keep promising alerts it can no longer deliver (lifecycle audit L13).
enum NotifierHealth {
  /// Channels exist and are at the importance the app asks for.
  ok,

  /// The user turned this app's notifications off at the OS level.
  blocked,

  /// A channel exists but at a lower importance: no heads-up, no sound.
  quiet,

  /// A channel the app needs was deleted.
  missingChannel,
}

/// The one seam between the app's decision to notify and the platform.
///
/// Tests use a fake so nothing in the suite touches a notification channel;
/// the app uses [LocalNotifier].
abstract interface class Notifier {
  /// Creates the OS channels and installs the tap handler. Idempotent.
  Future<void> init();

  /// Shows [n], replacing any notification with the same [MessageNotification.id].
  Future<void> show(MessageNotification n);

  /// Removes the notification a thread may still be showing.
  Future<void> cancelFor(String payload);

  /// Removes one notification by its OS id, used for the alarm's ongoing one.
  Future<void> cancel(int id);

  /// Reads the OS state back. Never throws: an unreadable state is [ok], so a
  /// platform that cannot answer does not paint a warning that may be false.
  ///
  /// [refresh] asks the platform again. The settings row passes it, because a
  /// user who just changed the channel in Android settings expects to see the
  /// result when they come back, not on the next launch.
  Future<NotifierHealth> health({bool refresh = false});
}

/// Records what the app asked the OS to show. Test-only.
class FakeNotifier implements Notifier {
  final List<MessageNotification> shown = <MessageNotification>[];
  final List<String> cancelled = <String>[];
  int initCount = 0;

  @override
  Future<void> init() async => initCount++;

  @override
  Future<void> show(MessageNotification n) async => shown.add(n);

  @override
  Future<void> cancelFor(String payload) async => cancelled.add(payload);

  @override
  Future<void> cancel(int id) async => cancelled.add('id:$id');

  /// Set by a test to simulate the OS state.
  NotifierHealth healthValue = NotifierHealth.ok;

  @override
  Future<NotifierHealth> health({bool refresh = false}) async => healthValue;

  void clear() {
    shown.clear();
    cancelled.clear();
  }
}
