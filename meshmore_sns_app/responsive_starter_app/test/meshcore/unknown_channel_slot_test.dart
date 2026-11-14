// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// A message for a channel the app has not named yet.
///
/// The row was always stored, but the strip is built from `channels`, so a slot
/// with no entry had no chip: the message existed and the reader could not reach
/// it. That is the difference between "handled" and "lost".
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

  test('a message on an unnamed slot makes that slot reachable', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    // Slot 3 has never been named: the probe has not reached it, or its name is
    // empty on the radio.
    expect(c.channels.any((MapEntry<int, String> e) => e.key == 3), isFalse);

    fake.emit(channelMsgFrame(idx: 3, text: 'anyone there?'));
    await Future<void>.delayed(Duration.zero);

    expect(c.channels.any((MapEntry<int, String> e) => e.key == 3), isTrue,
        reason: 'the row is stored but the strip has no chip for it');
    expect(c.messagesFor(3).map((ChatMessage m) => m.text),
        contains('anyone there?'));
    c.dispose();
  });

  test('a named slot keeps its name when a message arrives', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    fake.emit(channelInfoFrame(idx: 2, name: '#basecamp'));
    await Future<void>.delayed(Duration.zero);

    fake.emit(channelMsgFrame(idx: 2, text: 'hello'));
    await Future<void>.delayed(Duration.zero);

    expect(
        c.channels
            .firstWhere((MapEntry<int, String> e) => e.key == 2)
            .value,
        '#basecamp',
        reason: 'the placeholder overwrote a real name');
    c.dispose();
  });
}
