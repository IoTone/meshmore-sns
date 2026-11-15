// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/radio_switch.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// D8.9 — one session, and changing it is explicit.
///
/// The rule the register states is the one asserted here: a switch is refused
/// while a send is unanswered, because an answer belongs to the link it arrived
/// on. Marking the send unknown instead would leave a row that can never settle
/// and a failure the app cannot prove.
const String _peer =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a switch with nothing in flight moves the session', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);

    final RadioSwitchOutcome outcome =
        await switchRadio(c, remoteId: 'AA:BB:CC', name: 'HELTEC');
    expect(outcome, RadioSwitchOutcome.switched);
    expect(c.pairedRemoteId, 'AA:BB:CC');
    expect(c.pairedName, 'HELTEC');
    c.dispose();
  });

  test('a switch to the radio already paired touches nothing', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    await switchRadio(c, remoteId: 'AA:BB:CC', name: 'HELTEC');
    final int sentBefore = fake.sent.length;

    final RadioSwitchOutcome outcome =
        await switchRadio(c, remoteId: 'AA:BB:CC', name: 'HELTEC');
    expect(outcome, RadioSwitchOutcome.sameRadio);
    expect(fake.sent.length, sentBefore,
        reason: 'a no-op must not tear the link down and bring it back');
    c.dispose();
  });

  test('a switch is refused while a message is unanswered', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    // A send whose write threw is `unknown`, which is unsettled: the answer may
    // still arrive, and it would arrive on this link.
    fake.setConnected(false);
    final ChatMessage? m = await c.sendDirectText(_peer, 'hello');
    expect(m, isNotNull);
    expect(m!.delivery, MessageDelivery.unknown);
    expect(c.unsettledOutgoingCount, greaterThan(0));
    fake.setConnected(true);

    final RadioSwitchOutcome outcome =
        await switchRadio(c, remoteId: 'AA:BB:CC', name: 'HELTEC');
    expect(outcome, RadioSwitchOutcome.refusedUnsettled);
    expect(c.pairedRemoteId, isNot('AA:BB:CC'),
        reason: 'the pairing must not move when the switch is refused');
    c.dispose();
  });
}
