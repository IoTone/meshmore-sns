// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/notifications/local_notifier.dart';
import 'package:meshmore_sns_app/notifications/notifier.dart';

/// L13 — the OS state the app cannot see without asking.
///
/// A user who lowers a channel to silent, deletes it, or turns the app's
/// notifications off has changed what the app can deliver, and nothing in the
/// app reads that back. These are the decisions the read makes, tested
/// without a platform channel.
void main() {
  const List<String> ours = <String>[
    'mm_messages_channel',
    'mm_messages_direct',
    'mm_messages_sos',
    // The fence channel is one of ours too: a reader who silenced it has
    // changed what the app can deliver, and the health row has to say so.
    'mm_geofence',
  ];

  AndroidNotificationChannel channel(String id, Importance importance) =>
      AndroidNotificationChannel(id, id, importance: importance);

  List<AndroidNotificationChannel> allAt(Importance importance) => <
      AndroidNotificationChannel>[
    for (final String id in ours) channel(id, importance),
  ];

  test('everything at high importance is ok', () {
    expect(
      healthFrom(
        enabled: true,
        channels: allAt(Importance.high),
        ourIds: ours,
      ),
      NotifierHealth.ok,
    );
  });

  test('notifications off at the OS level outranks every channel state', () {
    expect(
      healthFrom(enabled: false, channels: allAt(Importance.high), ourIds: ours),
      NotifierHealth.blocked,
    );
    expect(
      healthFrom(enabled: false, channels: null, ourIds: ours),
      NotifierHealth.blocked,
    );
  });

  test('a lowered channel is quiet', () {
    final List<AndroidNotificationChannel> mixed = allAt(Importance.high)
      ..[1] = channel('mm_messages_direct', Importance.low);
    expect(
      healthFrom(enabled: true, channels: mixed, ourIds: ours),
      NotifierHealth.quiet,
    );
  });

  test('a deleted channel is missing, and missing outranks quiet', () {
    final List<AndroidNotificationChannel> oneGone = allAt(Importance.high)
        .where((AndroidNotificationChannel c) => c.id != 'mm_messages_sos')
        .toList()
      ..[0] = channel('mm_messages_channel', Importance.low);
    expect(
      healthFrom(enabled: true, channels: oneGone, ourIds: ours),
      NotifierHealth.missingChannel,
    );
  });

  test('a platform that cannot answer is not reported as a problem', () {
    expect(
      healthFrom(enabled: null, channels: null, ourIds: ours),
      NotifierHealth.ok,
    );
  });

  test('a silenced fence channel is quiet, like any other', () {
    final List<AndroidNotificationChannel> mixed = allAt(Importance.high)
      ..[3] = channel('mm_geofence', Importance.min);
    expect(
      healthFrom(enabled: true, channels: mixed, ourIds: ours),
      NotifierHealth.quiet,
    );
  });
}
