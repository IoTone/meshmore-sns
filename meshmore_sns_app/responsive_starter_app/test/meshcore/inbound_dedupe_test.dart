// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// The protocol has no message identifier.
///
/// A received message is identified by its sender's prefix, the sender's own
/// timestamp and its text, and the radio's queue re-sends anything it never saw
/// acknowledged. After a crash or a dropped link the same message arrives again,
/// and appending it puts the same words on screen twice with nothing to tell a
/// duplicate from a repeat. The app keeps a bounded memory of what it has just
/// ingested and drops the repeat.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> settle() async {
    for (int i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<MeshcoreController> ready(FakeMeshcoreTransport fake) async {
    final MeshcoreController c =
        MeshcoreController(transportFactory: () async => fake);
    await c.connect();
    fake.emit(selfInfoFrame());
    await settle();
    return c;
  }

  test('a DM delivered twice is one row', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await ready(fake);
    final List<int> prefix = <int>[0x11, 0x22, 0x33, 0x44, 0x55, 0x66];
    fake.emit(contactMessageFrame(prefix: prefix, text: 'copy that'));
    await settle();
    fake.emit(contactMessageFrame(prefix: prefix, text: 'copy that'));
    await settle();
    expect(
        c.dmHistoryFor('112233445566')
            .where((ChatMessage m) => !m.outgoing)
            .length,
        1,
        reason: 'a re-delivery is the same message, not a second one');
    c.dispose();
  });

  test('a different text from the same sender is kept', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await ready(fake);
    final List<int> prefix = <int>[0x11, 0x22, 0x33, 0x44, 0x55, 0x66];
    fake.emit(contactMessageFrame(prefix: prefix, text: 'first'));
    await settle();
    fake.emit(contactMessageFrame(prefix: prefix, text: 'second'));
    await settle();
    expect(
        c.dmHistoryFor('112233445566')
            .where((ChatMessage m) => !m.outgoing)
            .length,
        2);
    c.dispose();
  });

  test('a channel message delivered twice is one row', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await ready(fake);
    fake.emit(channelMsgFrame(idx: 0, text: 'anyone on?'));
    await settle();
    fake.emit(channelMsgFrame(idx: 0, text: 'anyone on?'));
    await settle();
    expect(
        c.messagesFor(0).where((ChatMessage m) => !m.outgoing), hasLength(1));
    c.dispose();
  });

  test('the same words on two channels are two messages', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await ready(fake);
    fake.emit(channelMsgFrame(idx: 0, text: 'same'));
    await settle();
    fake.emit(channelMsgFrame(idx: 1, text: 'same'));
    await settle();
    expect(c.messagesFor(0).where((ChatMessage m) => !m.outgoing), hasLength(1));
    expect(c.messagesFor(1).where((ChatMessage m) => !m.outgoing), hasLength(1));
    c.dispose();
  });
}
