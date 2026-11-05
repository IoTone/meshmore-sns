// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'message_notification.dart';

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

  void clear() {
    shown.clear();
    cancelled.clear();
  }
}
