// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/failure.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';

/// A9 and A10 of the link failure register: a link that gave up must offer the
/// way back, and a channel send whose write threw must not claim it failed.
Future<MeshcoreController> _ready(FakeMeshcoreTransport fake) async {
  final MeshcoreController c = MeshcoreController(
    transportFactory: () async => fake,
    connection: MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await c.connect();
  fake.emit(selfInfoFrame());
  await Future<void>.delayed(Duration.zero);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a channel send whose write throws reads unknown, never failed',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);

    // A write that throws is the link going away at the worst moment: the
    // radio may already hold the frame, so nothing here is proof of failure.
    fake.failSend = true;
    final ChatMessage? m = await c.sendChannelTextTo(0, 'hello');
    fake.failSend = false;

    expect(m, isNotNull);
    expect(m!.delivery, MessageDelivery.unknown,
        reason: 'APP-C2: a channel row is never failed from a write error');
    expect(m.failReason, 'link dropped while sending');
  });

  test('an outgoing row that was never written keeps its draft text', () async {
    // The composer restores the text when a row ends unknown, which is why
    // the state has to be unknown rather than failed: failed is a Retry
    // prompt, unknown is "check before retrying".
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    fake.failSend = true;
    final ChatMessage? m = await c.sendChannelTextTo(0, 'keep me');
    fake.failSend = false;

    expect(m!.text, 'keep me');
    expect(m.delivery, MessageDelivery.unknown);
  });

  test('a channel send the radio has denied is refused here, not on the air',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    // The radio answered ERR_CODE_UNSUPPORTED_CMD for a channel text earlier.
    c.capabilities
        .observeError(MeshcoreCommand.sendChannelMessage, 1);
    final int before = fake.sent.length;

    final ChatMessage? m = await c.sendChannelTextTo(0, 'hello');

    expect(m!.delivery, MessageDelivery.failed);
    expect(m.failCause, FailureCause.unsupportedCommand,
        reason: 'the row names the gap instead of waiting for an ERR');
    expect(fake.sent.length, before,
        reason: 'a command the radio denied is not written again');
  });
}
