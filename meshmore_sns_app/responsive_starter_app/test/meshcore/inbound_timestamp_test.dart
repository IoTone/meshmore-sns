// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// What a received message says about *when* it was sent.
///
/// The frame carries the sender's unix seconds and the app used to ignore it,
/// stamping every row with the moment it arrived. The radio queues inbound
/// messages while the app is away and the app drains them on reconnect, so a
/// conversation from last night arrived looking like it had just happened.
Future<MeshcoreController> _ready(FakeMeshcoreTransport fake) async {
  final MeshcoreController c = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await c.connect();
  fake.emit(selfInfoFrame());
  await Future<void>.delayed(Duration.zero);
  return c;
}

int _unix(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a channel row keeps the time the sender sent it', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    final DateTime sent = DateTime.now().subtract(const Duration(hours: 3));

    fake.emit(channelMsgFrame(idx: 0, text: 'from last night', ts: _unix(sent)));
    await Future<void>.delayed(Duration.zero);

    final ChatMessage row = c.messagesFor(0).last;
    expect(row.text, 'from last night');
    // Within a second: the frame carries whole seconds.
    expect(row.at.difference(sent).inSeconds.abs(), lessThanOrEqualTo(1),
        reason: 'the row was stamped with the drain time, not the send time');
    c.dispose();
  });

  test('a DM row keeps the time the sender sent it', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    final DateTime sent = DateTime.now().subtract(const Duration(minutes: 40));

    fake.emit(contactMessageFrame(
        prefix: <int>[0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF],
        text: 'earlier',
        ts: _unix(sent)));
    await Future<void>.delayed(Duration.zero);

    final ChatMessage row = c.dmHistoryFor('aabbccddeeff').last;
    expect(row.at.difference(sent).inSeconds.abs(), lessThanOrEqualTo(1));
    c.dispose();
  });

  test('a stamp from the future is not evidence, so the receive time is used',
      () async {
    // A sender's clock can be wrong by years. A row dated tomorrow is worse than
    // a row dated now, because the reader cannot tell which is the lie.
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    final DateTime before = DateTime.now();

    fake.emit(channelMsgFrame(
        idx: 0,
        text: 'from the future',
        ts: _unix(DateTime.now().add(const Duration(days: 2)))));
    await Future<void>.delayed(Duration.zero);

    final ChatMessage row = c.messagesFor(0).last;
    expect(row.at.isBefore(before.add(const Duration(minutes: 1))), isTrue,
        reason: 'a future stamp was trusted');
    c.dispose();
  });

  test('a stamp older than the history is not evidence either', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    final DateTime before = DateTime.now();

    fake.emit(channelMsgFrame(
        idx: 0,
        text: 'from 2019',
        ts: _unix(DateTime.utc(2019, 1, 1))));
    await Future<void>.delayed(Duration.zero);

    final ChatMessage row = c.messagesFor(0).last;
    expect(row.at.isAfter(before.subtract(const Duration(minutes: 1))), isTrue,
        reason: 'a stamp from years ago was trusted');
    c.dispose();
  });

  test('a frame with no timestamp still lands, stamped on arrival', () async {
    // The legacy frames in the wild carry zero. Zero is not 1970: it is "the
    // sender did not say", and the receive time is the honest answer.
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    final DateTime before = DateTime.now();

    fake.emit(channelMsgFrame(idx: 0, text: 'no stamp'));
    await Future<void>.delayed(Duration.zero);

    final ChatMessage row = c.messagesFor(0).last;
    expect(row.at.isAfter(before.subtract(const Duration(minutes: 1))), isTrue);
    c.dispose();
  });
}
