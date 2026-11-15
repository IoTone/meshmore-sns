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

/// When the link comes up the radio hands over whatever queued while the phone
/// was away, and that queue is one event.
///
/// A dozen queued messages must produce one entry reading "12 unread messages",
/// not twelve entries: the user did not witness them arrive, and a locked screen
/// full of lines from a moment they were not there for is noise. A message that
/// arrives once the queue has fallen quiet is announced on its own, which is
/// what "only while already connected" means.
class _Strings implements NotificationStrings {
  @override
  String title(NotificationClass cls, String? name) => switch (cls) {
        NotificationClass.channel => 'on $name',
        NotificationClass.direct => 'from $name',
        NotificationClass.sos => 'SOS',
        NotificationClass.geofence => 'fence',
      };

  @override
  String fenceCrossed(String label, {required bool entry}) =>
      entry ? 'entered $label' : 'left $label';

  @override
  String fenceCrossedBody() => 'from the latest position update';

  @override
  String sosBody() => 'SOS body without coordinates';

  @override
  String unreadDigest(int count) =>
      count == 1 ? '1 unread message' : '$count unread messages';

  @override
  String alarmRunningBody() => 'alarm running body';
}

class _Effects implements NotificationEffects {
  int cues = 0;
  int vibrations = 0;

  @override
  void cue(NotificationClass cls) => cues++;

  @override
  void vibrate() => vibrations++;

  @override
  void speakChannel(int channelIdx, String text) {}
}

void main() {
  late StreamController<ChatMessage> channel;
  late StreamController<ChatMessage> direct;
  late FakeNotifier notifier;
  late _Effects effects;
  late NotificationService service;

  setUp(() {
    channel = StreamController<ChatMessage>.broadcast();
    direct = StreamController<ChatMessage>.broadcast();
    notifier = FakeNotifier();
    effects = _Effects();
    service = NotificationService(
      channelMessages: channel.stream,
      directMessages: direct.stream,
      notifier: notifier,
      prefs: NotificationPrefs(),
      focus: NotificationFocus(),
      strings: _Strings.new,
      selfDisplayName: () => 'Sam',
      ownPubKeyHex: () => 'aabbccdd',
      peerDisplayName: (String key) => 'Bea',
      channelName: (int slot) => slot == 0 ? 'Public' : 'CH $slot',
      // A test cannot wait out a real absence, and the rule under test is the
      // window's behaviour, not its length.
      catchUpMinGap: Duration.zero,
    )
      ..effects = effects
      ..catchUpIdle = const Duration(milliseconds: 30)
      ..catchUpMax = const Duration(seconds: 5)
      ..start();
  });

  tearDown(() async {
    await service.dispose();
    await channel.close();
    await direct.close();
  });

  Future<void> say(int i, {int slot = 0}) async {
    channel.add(ChatMessage(
      id: 'm$i',
      channelIdx: slot,
      text: 'queued $i',
      outgoing: false,
    ));
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 80));

  test('a catch-up queue becomes one line with a count', () async {
    service.onLinkDown();
    service.onLinkReady();
    for (int i = 0; i < 12; i++) {
      await say(i);
    }
    await settle();

    expect(notifier.shown, isEmpty,
        reason: 'a queue must not post one notification per message');
    expect(notifier.digests, isNotEmpty);
    expect(notifier.digests.last.count, 12);
    expect(notifier.digests.last.body, '12 unread messages');
    expect(notifier.digests.last.payload, 'ch:0');
  });

  test('the queue is one cue, not one per message', () async {
    service.onLinkDown();
    service.onLinkReady();
    for (int i = 0; i < 6; i++) {
      await say(i);
    }
    await settle();
    expect(effects.cues, 1);
    expect(effects.vibrations, 1);
  });

  test('a message after the queue has settled is announced on its own',
      () async {
    service.onLinkDown();
    service.onLinkReady();
    await say(1);
    await settle();
    expect(service.isCatchingUp, isFalse);

    await say(2);
    await settle();
    expect(notifier.shown, hasLength(1),
        reason: 'arriving while connected and caught up means its own entry');
    expect(notifier.shown.single.body, 'queued 2');
  });

  test('nothing queued means no line at all', () async {
    service.onLinkDown();
    service.onLinkReady();
    await settle();
    expect(notifier.digests, isEmpty);
    expect(notifier.shown, isEmpty);
  });

  test('a direct message in the queue lands in the queue line', () async {
    service.onLinkDown();
    service.onLinkReady();
    direct.add(ChatMessage(
      id: 'd1',
      channelIdx: 0,
      text: 'queued dm',
      peerPubKeyHex: 'beef',
      outgoing: false,
    ));
    await Future<void>.delayed(Duration.zero);
    await settle();
    expect(notifier.shown, isEmpty);
    expect(notifier.digests.last.payload, 'dm:beef');
    expect(notifier.digests.last.cls, NotificationClass.direct);
  });

  test('an SOS in the queue is still its own loud entry', () async {
    service.onLinkDown();
    service.onLinkReady();
    await say(1);
    channel.add(ChatMessage(
      id: 'sos1',
      channelIdx: 0,
      text: '[SOS:abc123] 38.9,-104.7 Sam',
      outgoing: false,
    ));
    await Future<void>.delayed(Duration.zero);
    await settle();
    expect(notifier.shown, hasLength(1),
        reason: 'a distress call never waits behind a count');
    expect(notifier.shown.single.cls, NotificationClass.sos);
  });

  test('a second connect opens a fresh window', () async {
    service.onLinkDown();
    service.onLinkReady();
    await say(1);
    await settle();
    expect(notifier.digests.last.count, 1);

    // The link dropped and came back: the next queue counts from one again.
    service.onLinkDown();
    service.onLinkReady();
    await say(2);
    await settle();
    expect(notifier.digests.last.count, 1,
        reason: 'the old queue is not carried into the new window');
  });

  test('the longest window ends even if messages keep coming', () async {
    service.catchUpMax = const Duration(milliseconds: 60);
    service.onLinkDown();
    service.onLinkReady();
    for (int i = 0; i < 5; i++) {
      await say(i);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(service.isCatchingUp, isFalse);
    await say(99);
    await settle();
    // Once the cap closes the window, a message is announced on its own — which
    // may already have happened for a message that arrived after the cap fired
    // mid-loop, so the assertion is about the newest, not the total.
    expect(notifier.shown, isNotEmpty,
        reason: 'after the cap, a message is announced on its own');
    expect(notifier.shown.last.body, 'queued 99');
  });
}
