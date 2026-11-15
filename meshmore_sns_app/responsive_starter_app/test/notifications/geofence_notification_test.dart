// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/notifications/channel_notification_prefs.dart';
import 'package:meshmore_sns_app/notifications/message_notification.dart';
import 'package:meshmore_sns_app/notifications/notification_focus.dart';
import 'package:meshmore_sns_app/notifications/notification_service.dart';

import '../support/fake_notifier.dart';

/// The fence crossing's OS entry: the half of the geofence spec that was
/// missing while the cues were already built.
///
/// A crossing is not a message. It is the app watching the reader's own
/// position, so it has its own OS channel, its own title per direction, and no
/// place in the message group whose summary counts messages.
class _Strings implements NotificationStrings {
  @override
  String title(NotificationClass cls, String? name) => switch (cls) {
        NotificationClass.channel => 'on $name',
        NotificationClass.direct => 'from $name',
        NotificationClass.sos => 'SOS',
        NotificationClass.geofence => 'fence',
      };

  @override
  String sosBody() => 'SOS body without coordinates';

  @override
  String unreadDigest(int count) => '$count unread messages';

  @override
  String alarmRunningBody() => 'alarm running body';

  @override
  String fenceCrossed(String label, {required bool entry}) =>
      entry ? 'Entered $label' : 'Left $label';

  @override
  String fenceCrossedBody() => 'From the latest position update';
}

void main() {
  late StreamController<ChatMessage> channel;
  late StreamController<ChatMessage> direct;
  late FakeNotifier notifier;
  late NotificationPrefs prefs;
  late NotificationFocus focus;
  late NotificationService service;

  setUp(() {
    channel = StreamController<ChatMessage>.broadcast();
    direct = StreamController<ChatMessage>.broadcast();
    notifier = FakeNotifier();
    prefs = NotificationPrefs();
    focus = NotificationFocus();
    service = NotificationService(
      channelMessages: channel.stream,
      directMessages: direct.stream,
      notifier: notifier,
      prefs: prefs,
      focus: focus,
      strings: _Strings.new,
      selfDisplayName: () => 'Sam',
      ownPubKeyHex: () => 'aabbccdd',
      peerDisplayName: (String key) => null,
      channelName: (int slot) => 'CH $slot',
    )..start();
  });

  tearDown(() async {
    await service.dispose();
    await channel.close();
    await direct.close();
  });

  test('a crossing posts one entry, on the fence channel, naming the fence',
      () {
    service.onGeofence(fenceId: 'gf1', label: 'Base', entry: true);

    final MessageNotification n = notifier.shown.single;
    expect(n.cls, NotificationClass.geofence);
    expect(n.channelId, 'mm_geofence');
    expect(n.title, 'Entered Base');
    expect(n.body, 'From the latest position update',
        reason: 'the body states the limit rather than implying live tracking');
    expect(n.payload, 'fence:gf1');
  });

  test('entering and leaving read differently', () {
    service.onGeofence(fenceId: 'gf1', label: 'Base', entry: true);
    service.onGeofence(fenceId: 'gf1', label: 'Base', entry: false);

    expect(notifier.shown.map((MessageNotification n) => n.title),
        <String>['Entered Base', 'Left Base']);
  });

  test('one fence has one OS id, so a re-entry replaces rather than stacks',
      () {
    service.onGeofence(fenceId: 'gf1', label: 'Base', entry: true);
    service.onGeofence(fenceId: 'gf1', label: 'Base', entry: false);
    service.onGeofence(fenceId: 'gf2', label: 'Yard', entry: true);

    final List<int> ids =
        notifier.shown.map((MessageNotification n) => n.id).toList();
    expect(ids[0], ids[1], reason: 'the same fence is one entry');
    expect(ids[2], isNot(ids[0]), reason: 'a different fence is its own entry');
  });

  test('a crossing never joins the message group', () {
    expect(joinsMessageGroup(NotificationClass.geofence), isFalse);
    expect(joinsMessageGroup(NotificationClass.channel), isTrue);
    expect(joinsMessageGroup(NotificationClass.direct), isTrue);
    expect(joinsMessageGroup(NotificationClass.sos), isTrue);
  });

  test('a crossing does not disturb the message count', () async {
    service.onGeofence(fenceId: 'gf1', label: 'Base', entry: true);
    channel.add(
        ChatMessage(id: 'm1', channelIdx: 0, text: 'hello', outgoing: false));
    await Future<void>.delayed(Duration.zero);

    // The digest is the only line that states a count, and a crossing must not
    // reach it: a queue of messages is what it stands for.
    expect(notifier.digests, isEmpty);
    expect(
        notifier.shown.map((MessageNotification n) => n.cls),
        <NotificationClass>[
          NotificationClass.geofence,
          NotificationClass.channel
        ]);
  });

  test('the fence channel is its own, so it can be silenced alone', () {
    expect(channelIdFor(NotificationClass.geofence), 'mm_geofence');
    expect(
      <String>{
        channelIdFor(NotificationClass.channel),
        channelIdFor(NotificationClass.direct),
        channelIdFor(NotificationClass.sos),
        channelIdFor(NotificationClass.geofence),
      },
      hasLength(4),
      reason: 'one OS channel per class is the promise D8.20 makes',
    );
  });
}
