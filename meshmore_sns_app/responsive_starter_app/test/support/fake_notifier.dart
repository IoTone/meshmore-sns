// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:meshmore_sns_app/notifications/message_notification.dart';
import 'package:meshmore_sns_app/notifications/notifier.dart';

/// Records what the app asked the OS to show. Test-only.
class FakeNotifier implements Notifier {
  final List<MessageNotification> shown = <MessageNotification>[];
  final List<String> cancelled = <String>[];
  int initCount = 0;

  @override
  Future<void> init() async => initCount++;

  @override
  Future<void> show(MessageNotification n) async => shown.add(n);

  /// Batch lines, newest last. A growing queue replaces the previous entry, so
  /// the last one here is the count the user would be looking at.
  final List<MessageDigest> digests = <MessageDigest>[];

  @override
  Future<void> showDigest(MessageDigest d) async => digests.add(d);

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
    digests.clear();
  }
}
