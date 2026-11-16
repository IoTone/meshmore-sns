// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/chat/reactions.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';

/// A reaction that arrives in a direct message is a chip on the message it
/// names, not a line of its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  test('a direct reaction folds into the message it names', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c =
        MeshcoreController(transportFactory: () async => fake);
    await c.connect();
    fake.emit(selfInfoFrame());
    await settle();

    const List<int> prefix = <int>[0x11, 0x22, 0x33, 0x44, 0x55, 0x66];
    const int ts = 1794806316;
    fake.emit(contactMessageFrame(
        prefix: prefix, text: 'reaction target one', ts: ts));
    await settle();

    final String hash =
        Reactions.hashFor(timestampSeconds: ts, text: 'reaction target one');
    fake.emit(contactMessageFrame(
        prefix: prefix, text: '\u{1F44D}\n$hash', ts: ts + 4));
    await settle();

    final List<ChatMessage> rows = c.dmHistoryFor('112233445566');
    expect(rows.length, 1,
        reason: 'the reaction is a gesture, not a second message');
    expect(rows.single.reactions['\u{1F44D}'], isNotNull,
        reason: 'the chip is on the message the hash names');
    c.dispose();
  });
}
