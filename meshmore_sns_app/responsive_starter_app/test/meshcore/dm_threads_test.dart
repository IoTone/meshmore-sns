// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/meshcore/dm_thread.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';

/// A DM has no channel to sit in, so the strip had no way to name one.
///
/// An inbound DM from a peer the reader had never written to was stored,
/// notified, and then unreachable: the only routes to a thread were the peer's
/// own node sheet and a search hit. These are the rules the strip's list has to
/// hold to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  Future<MeshcoreController> ready(FakeMeshcoreTransport fake) async {
    final MeshcoreController c =
        MeshcoreController(transportFactory: () async => fake);
    await c.connect();
    fake.emit(selfInfoFrame());
    await settle();
    return c;
  }

  test('an inbound DM from a stranger is a thread', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await ready(fake);
    fake.emit(contactMessageFrame(
      prefix: <int>[0x11, 0x22, 0x33, 0x44, 0x55, 0x66],
      text: '38.91993,-104.77313',
    ));
    await settle();
    final List<DmThread> threads = c.dmThreads;
    expect(threads.length, 1,
        reason: 'a DM from a peer we never wrote to is still a conversation');
    expect(threads.single.peerPubKeyHex, '112233445566');
    expect(threads.single.unread, 1);
    c.dispose();
  });

  test('the newest thread comes first', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await ready(fake);
    fake.emit(contactMessageFrame(
        prefix: <int>[0x11, 0x22, 0x33, 0x44, 0x55, 0x66], text: 'older'));
    await settle();
    fake.emit(contactMessageFrame(
        prefix: <int>[0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF], text: 'newer'));
    await settle();
    expect(c.dmThreads.first.peerPubKeyHex, 'aabbccddeeff',
        reason: 'the strip lists conversations by when they last spoke');
    c.dispose();
  });

  test('opening a thread clears its unread count', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await ready(fake);
    fake.emit(contactMessageFrame(
        prefix: <int>[0x11, 0x22, 0x33, 0x44, 0x55, 0x66], text: 'hello'));
    await settle();
    expect(c.dmThreads.single.unread, 1);
    c.markDmRead('112233445566');
    await settle();
    expect(c.dmThreads.single.unread, 0);
    c.dispose();
  });

  test('a channel message is not a DM thread', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await ready(fake);
    fake.emit(channelMsgFrame(idx: 0, text: 'in the channel'));
    await settle();
    expect(c.dmThreads, isEmpty,
        reason: 'a channel row has no peer, so it belongs to no conversation');
    c.dispose();
  });

  test('a peer with a heard name is listed by that name', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await ready(fake);
    fake.emit(contactMessageFrame(
        prefix: <int>[0x11, 0x22, 0x33, 0x44, 0x55, 0x66], text: 'hi'));
    await settle();
    expect(c.dmThreads.single.name, '112233445566',
        reason: 'an unheard peer is named by the only handle a DM carries');
    c.dispose();
  });
}
