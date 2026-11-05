// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/notifications/channel_notification_prefs.dart';
import 'package:meshmore_sns_app/notifications/message_notification.dart';
import 'package:meshmore_sns_app/notifications/notification_focus.dart';
import 'package:meshmore_sns_app/notifications/notification_service.dart';
import 'package:meshmore_sns_app/notifications/notifier.dart';

/// D8.20 / D8.13 — what becomes a notification, and what must not.
///
/// The service reads two streams and a few callbacks, so every rule is
/// testable without a radio, a widget or a platform channel.
class _Strings implements NotificationStrings {
  @override
  String title(NotificationClass cls, String? name) => switch (cls) {
        NotificationClass.channel => 'on $name',
        NotificationClass.direct => 'from $name',
        NotificationClass.sos => 'SOS',
      };
}

void main() {
  late StreamController<ChatMessage> channel;
  late StreamController<ChatMessage> direct;
  late FakeNotifier notifier;
  late NotificationPrefs prefs;
  late NotificationFocus focus;
  late NotificationService service;

  NotificationService build({NotificationPrefs? withPrefs}) {
    final NotificationService s = NotificationService(
      channelMessages: channel.stream,
      directMessages: direct.stream,
      notifier: notifier,
      prefs: withPrefs ?? prefs,
      focus: focus,
      strings: _Strings.new,
      selfDisplayName: () => 'Sam',
      ownPubKeyHex: () => 'aabbccdd',
      peerDisplayName: (String key) => key == 'beef' ? 'Bea' : null,
      channelName: (int slot) => slot == 0 ? 'Public' : 'CH $slot',
    )..start();
    return s;
  }

  setUp(() {
    channel = StreamController<ChatMessage>.broadcast();
    direct = StreamController<ChatMessage>.broadcast();
    notifier = FakeNotifier();
    prefs = NotificationPrefs();
    focus = NotificationFocus();
    service = build();
  });

  tearDown(() async {
    await service.dispose();
    await channel.close();
    await direct.close();
  });

  Future<void> channelMsg(String text,
      {String id = 'm1', int slot = 0, bool outgoing = false}) async {
    channel.add(ChatMessage(
      id: id,
      channelIdx: slot,
      text: text,
      outgoing: outgoing,
    ));
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> dm(String text,
      {String id = 'd1', String key = 'beef', bool outgoing = false}) async {
    direct.add(ChatMessage(
      id: id,
      channelIdx: 0,
      text: text,
      outgoing: outgoing,
      peerPubKeyHex: key,
    ));
    await Future<void>.delayed(Duration.zero);
  }

  test('a channel message notifies once, with the channel payload', () async {
    await channelMsg('hello');
    expect(notifier.shown, hasLength(1));
    final MessageNotification n = notifier.shown.single;
    expect(n.cls, NotificationClass.channel);
    expect(n.payload, 'ch:0');
    expect(n.title, 'on Public');
    expect(n.body, 'hello');
  });

  test('the same message replayed after a reconnect notifies once', () async {
    await channelMsg('hello', id: 'same');
    await channelMsg('hello', id: 'same');
    await channelMsg('hello', id: 'same');
    expect(notifier.shown, hasLength(1));
  });

  test('our own outgoing message never notifies', () async {
    await channelMsg('mine', outgoing: true);
    expect(notifier.shown, isEmpty);
  });

  test('a silent channel stays silent', () async {
    await prefs.setFor(0, const ChannelNotificationPrefs(os: false));
    await service.dispose();
    service = build();
    await channelMsg('hello');
    expect(notifier.shown, isEmpty);
  });

  test('mentions-only drops a message that does not name this device',
      () async {
    await prefs.setFor(0, const ChannelNotificationPrefs(mentionsOnly: true));
    await service.dispose();
    service = build();
    await channelMsg('Samantha has the maps');
    expect(notifier.shown, isEmpty);
  });

  test('mentions-only keeps a whole-word mention', () async {
    await prefs.setFor(0, const ChannelNotificationPrefs(mentionsOnly: true));
    await service.dispose();
    service = build();
    await channelMsg('Sam, take the north track');
    expect(notifier.shown, hasLength(1));
  });

  test('mentions-only keeps an @name mention', () async {
    await prefs.setFor(0, const ChannelNotificationPrefs(mentionsOnly: true));
    await service.dispose();
    service = build();
    await channelMsg('ping @Sam please');
    expect(notifier.shown, hasLength(1));
  });

  test('an SOS outranks the channel being silent', () async {
    await prefs.setFor(0, const ChannelNotificationPrefs(
      os: false,
      mentionsOnly: true,
    ));
    await service.dispose();
    service = build();
    await channelMsg('[SOS:abc123] 38.9,-104.7 Sam fuel low');
    expect(notifier.shown, hasLength(1));
    expect(notifier.shown.single.cls, NotificationClass.sos);
    expect(notifier.shown.single.title, 'SOS');
  });

  test('a message on the open thread is not announced', () async {
    focus.foreground = true;
    focus.openChannel = 0;
    await channelMsg('hello');
    expect(notifier.shown, isEmpty);
  });

  test('the same thread in the background is announced', () async {
    focus.foreground = false;
    focus.openChannel = 0;
    await channelMsg('hello');
    expect(notifier.shown, hasLength(1));
  });

  test('another channel is announced while one is open', () async {
    focus.foreground = true;
    focus.openChannel = 2;
    await channelMsg('hello', slot: 1);
    expect(notifier.shown, hasLength(1));
    expect(notifier.shown.single.payload, 'ch:1');
    expect(notifier.shown.single.title, 'on CH 1');
  });

  test('a direct message notifies with the peer payload and name', () async {
    await dm('are you there');
    expect(notifier.shown, hasLength(1));
    final MessageNotification n = notifier.shown.single;
    expect(n.cls, NotificationClass.direct);
    expect(n.payload, 'dm:beef');
    expect(n.title, 'from Bea');
  });

  test('an unknown peer falls back to the key in the title', () async {
    await dm('hello', key: 'c0ffee');
    expect(notifier.shown.single.title, 'from c0ffee');
  });

  test('a DM on the open thread is not announced', () async {
    focus.foreground = true;
    focus.openPeer = 'beef';
    await dm('hello');
    expect(notifier.shown, isEmpty);
  });

  test('the notification id is stable for a message', () {
    expect(
      NotificationService.idFor('abc'),
      NotificationService.idFor('abc'),
    );
    expect(
      NotificationService.idFor('abc'),
      isNot(NotificationService.idFor('abd')),
    );
  });
}
