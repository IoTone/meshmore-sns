// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

Uint8List okFrame() => Uint8List.fromList(<int>[0x00]);
Uint8List errFrame(int code) => Uint8List.fromList(<int>[0x01, code]);
Uint8List sentFrame({int ack = 1, bool flood = true}) => Uint8List.fromList(
    <int>[0x06, flood ? 1 : 0, ack & 0xFF, (ack >> 8) & 0xFF, 0, 0, 0, 0, 0, 0]);

Future<MeshcoreController> _ready(FakeMeshcoreTransport fake,
    {Duration watchdog = const Duration(milliseconds: 200)}) async {
  final MeshcoreController c = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    deliveryTimeoutOverride: watchdog,
  );
  await c.connect();
  fake.emit(selfInfoFrame());
  await Future<void>.delayed(Duration.zero);
  return c;
}

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('two sends of one kind cannot swap their answers', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    final ChatMessage first = (await c.sendChannelTextTo(0, 'one'))!;
    final ChatMessage second = (await c.sendChannelTextTo(0, 'two'))!;

    fake.emit(okFrame());
    await tick();
    expect(first.delivery, MessageDelivery.sent);
    expect(second.delivery, MessageDelivery.sending,
        reason: 'the first answer belongs to the first send');

    fake.emit(okFrame());
    await tick();
    expect(second.delivery, MessageDelivery.sent);
    expect(c.unclaimedReplies, 0);
    c.dispose();
  });

  test('a reply for the other kind is unclaimed, not spent', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    final ChatMessage m = (await c.sendChannelTextTo(0, 'hi'))!;

    fake.emit(sentFrame());
    await tick();
    expect(m.delivery, MessageDelivery.sending);
    expect(c.unclaimedReplies, 1);

    fake.emit(okFrame());
    await tick();
    expect(m.delivery, MessageDelivery.sent);
    expect(c.unclaimedReplies, 1);
    c.dispose();
  });

  test('an answer after the watchdog credits nothing and says so', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c =
        await _ready(fake, watchdog: const Duration(milliseconds: 30));
    final ChatMessage m = (await c.sendChannelTextTo(0, 'hi'))!;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(m.delivery, MessageDelivery.failed);

    final int before = c.unclaimedReplies;
    fake.emit(okFrame());
    await tick();
    expect(m.delivery, MessageDelivery.failed,
        reason: 'a late OK must not revive a failed row');
    expect(c.unclaimedReplies, before + 1);
    c.dispose();
  });

  test('a duplicate OK is not spent on the next send', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    final ChatMessage a = (await c.sendChannelTextTo(0, 'a'))!;
    fake.emit(okFrame());
    await tick();
    expect(a.delivery, MessageDelivery.sent);

    // The radio repeats the answer before the next send exists.
    fake.emit(okFrame());
    await tick();
    expect(c.unclaimedReplies, 1);

    final ChatMessage b = (await c.sendChannelTextTo(0, 'b'))!;
    expect(b.delivery, MessageDelivery.sending,
        reason: 'the duplicate must not have pre-confirmed the next send');
    c.dispose();
  });

  test('an error fails the command at the head, not a later one', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    final ChatMessage first = (await c.sendChannelTextTo(0, 'one'))!;
    final ChatMessage second = (await c.sendChannelTextTo(0, 'two'))!;
    fake.emit(errFrame(6)); // ERR_CODE_ILLEGAL_ARG
    await tick();
    expect(first.delivery, MessageDelivery.failed);
    expect(second.delivery, MessageDelivery.sending);
    c.dispose();
  });
}
