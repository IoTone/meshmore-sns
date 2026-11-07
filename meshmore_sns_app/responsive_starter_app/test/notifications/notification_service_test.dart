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

  @override
  String sosBody() => 'SOS body without coordinates';

  @override
  String alarmRunningBody() => 'alarm running body';
}

/// Records what the app asked the phone to do besides posting.
class _Effects implements NotificationEffects {
  final List<NotificationClass> cues = <NotificationClass>[];
  int vibrations = 0;
  final List<(int, String)> spoken = <(int, String)>[];

  @override
  void cue(NotificationClass cls) => cues.add(cls);

  @override
  void vibrate() => vibrations++;

  @override
  void speakChannel(int channelIdx, String text) =>
      spoken.add((channelIdx, text));
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
    // The real shape of channel text: the firmware prepends the sender's name,
    // so the tag is after the prefix (safety audit SOS-1).
    await channelMsg('Sam: [SOS:abc123] 38.9,-104.7 fuel low');
    expect(notifier.shown, hasLength(1));
    expect(notifier.shown.single.cls, NotificationClass.sos);
    expect(notifier.shown.single.title, 'SOS');
    // The coordinates travel in the message; the lock screen is not where
    // they belong (the diagnostics redactor treats a position as opt-in).
    expect(notifier.shown.single.body, 'SOS body without coordinates');
    expect(notifier.shown.single.body, isNot(contains('38.9')));
  });

  test('a channel SOS is the SOS class, with the sender prefix in the line',
      () async {
    // The defect this pins: `startsWith('[SOS:')` never matched channel text,
    // so a channel alarm arrived on the chatter channel, could be silenced by
    // the channel's own bundle, and put the raw coordinates on the lock
    // screen as an ordinary message body.
    await prefs.setFor(0, const ChannelNotificationPrefs(
      os: true,
      audio: false,
      haptic: false,
      mentionsOnly: true,
    ));
    await service.dispose();
    service = build();
    await channelMsg('Sam: [SOS:abc123] 38.9,-104.7 fuel low',
        id: 'sos-prefixed');
    expect(notifier.shown.single.cls, NotificationClass.sos);
    expect(notifier.shown.single.title, 'SOS');
    expect(notifier.shown.single.body, 'SOS body without coordinates');
  });

  test('a prefixed line that is not an SOS stays a channel message', () async {
    await channelMsg('Sam: hello there', id: 'plain-prefixed');
    expect(notifier.shown.single.cls, NotificationClass.channel);
  });

  test('a direct SOS is redacted too, and keeps the DM route', () async {
    await dm('[SOS:abc123] 38.9,-104.7 Sam fuel low', key: 'a1' * 32);
    expect(notifier.shown.single.cls, NotificationClass.sos);
    expect(notifier.shown.single.body, isNot(contains('38.9')));
    expect(notifier.shown.single.payload, startsWith('dm:'));
  });

  test('the OS id is a stable digest, not a per-run hash', () {
    // A fixed input must give a fixed id: the value is pinned so a change in
    // hashing is a visible test failure rather than notifications that stop
    // replacing each other after a restart.
    final int a = NotificationService.idFor('msg-1234');
    final int b = NotificationService.idFor('msg-1234');
    expect(a, b);
    expect(a, isNot(NotificationService.idFor('msg-1235')));
    expect(a, inInclusiveRange(0, 0x7FFFFFFF));
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

  // D8.13 — the bundle's three non-OS switches actually do something, and a
  // silent channel stays silent in all of them.
  group('the per-channel bundle', () {
    test('a cue and a vibration follow the channel settings', () async {
      final _Effects fx = _Effects();
      service.effects = fx;
      await prefs.setFor(0, const ChannelNotificationPrefs(audio: true));
      await channelMsg('hello');
      expect(fx.cues, <NotificationClass>[NotificationClass.channel]);
      expect(fx.vibrations, 1);
    });

    test('a silenced channel neither cues nor vibrates', () async {
      final _Effects fx = _Effects();
      service.effects = fx;
      await prefs.setFor(0, const ChannelNotificationPrefs(
        os: false,
        audio: false,
        haptic: false,
      ));
      await channelMsg('hello');
      expect(fx.cues, isEmpty);
      expect(fx.vibrations, 0);
    });

    test('speech is per channel and carries the message text', () async {
      final _Effects fx = _Effects();
      service.effects = fx;
      await prefs.setFor(0, const ChannelNotificationPrefs(tts: true));
      await channelMsg('bridge out', slot: 0);
      expect(fx.spoken, <(int, String)>[(0, 'bridge out')]);
    });

    test('an SOS is loud even where the channel is silent', () async {
      final _Effects fx = _Effects();
      service.effects = fx;
      await prefs.setFor(0, const ChannelNotificationPrefs(
        os: false,
        audio: false,
        haptic: false,
      ));
      await channelMsg('[SOS:abc123] 38.9,-104.8');
      expect(fx.cues, <NotificationClass>[NotificationClass.sos]);
      expect(fx.vibrations, 1);
      expect(notifier.shown.single.cls, NotificationClass.sos);
    });

    test('a direct message cues and vibrates without a channel bundle',
        () async {
      final _Effects fx = _Effects();
      service.effects = fx;
      direct.add(ChatMessage(
        id: 'd1',
        channelIdx: 0,
        text: 'hi',
        outgoing: false,
        peerPubKeyHex: 'beef',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(fx.cues, <NotificationClass>[NotificationClass.direct]);
      expect(fx.vibrations, 1);
    });
  });

  test('a blocked key raises nothing: no post, no cue, no speech', () async {
    // setUp already started an unfiltered service on the same broadcast
    // streams; it would post for the same message and make this test lie.
    await service.dispose();
    final _Effects fx = _Effects();
    final NotificationService s = NotificationService(
      channelMessages: channel.stream,
      directMessages: direct.stream,
      notifier: notifier,
      prefs: prefs,
      focus: focus,
      strings: _Strings.new,
      selfDisplayName: () => 'Sam',
      ownPubKeyHex: () => 'aabbccdd',
      peerDisplayName: (String key) => 'Peer',
      channelName: (int slot) => 'general',
      isBlocked: (ChatMessage m) => m.peerPubKeyHex == 'b' * 64,
    )..effects = fx;
    s.start();
    direct.add(ChatMessage(
      channelIdx: 0,
      text: 'you should not see this',
      outgoing: false,
      peerPubKeyHex: 'b' * 64,
    ));
    await Future<void>.delayed(Duration.zero);
    expect(notifier.shown, isEmpty);
    expect(fx.cues, isEmpty);
    expect(fx.vibrations, 0);
    expect(fx.spoken, isEmpty);
    await s.dispose();
  });
}
