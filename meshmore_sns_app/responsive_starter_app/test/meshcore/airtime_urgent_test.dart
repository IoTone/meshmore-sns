// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/airtime_meter.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';

/// An alarm is not subject to the budget this app invented for itself.
///
/// The duty cycle exists to keep ordinary traffic polite. Refusing an SOS
/// repeat because the user chatted too much would make the meter the reason
/// nobody was told, so an urgent send is written even when the window is full —
/// and still charged, so the meter keeps telling the truth.
Future<MeshcoreController> _controller(FakeMeshcoreTransport fake) async {
  final MeshcoreController c = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    airtimeMeter: AirtimeMeter(),
  );
  await c.connect();
  fake.emit(selfInfoFrame());
  await Future<void>.delayed(Duration.zero);
  return c;
}

/// A frame the radio would transmit: 0x03 (channel text) with padding. Only the
/// first byte decides whether the meter charges it, and only the length is
/// estimated.
Uint8List otaFrame(int length) {
  final Uint8List f = Uint8List(length);
  if (length > 0) f[0] = 0x03;
  return f;
}

/// Spends the whole hourly window on the largest **over-the-air** frame.
///
/// The first byte has to be a command the radio transmits — a channel text frame
/// here — because a local BLE request costs no channel time and is no longer
/// charged. The rest of the buffer is padding: only the length is estimated.
///
/// 176 bytes is the frame ceiling, about 0.7 s of airtime at the flat
/// estimator, so a 36 s window takes ~50 frames. The loop stops as soon as
/// the meter refuses, which is the state under test.
Future<void> _exhaust(MeshcoreController c) async {
  final Uint8List big = otaFrame(176);
  for (int i = 0; i < 90; i++) {
    try {
      await c.send(big, gated: true);
    } on AirtimeRefused {
      return;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('an ordinary send is refused once the window is full', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _controller(fake);
    await _exhaust(c);
    final int before = fake.sent.length;

    await expectLater(
      c.send(otaFrame(64), gated: true),
      throwsA(isA<AirtimeRefused>()),
    );
    expect(fake.sent.length, before,
        reason: 'a refused frame never reaches the transport');
  });

  test('an urgent channel send is written when the window is full, and charged',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _controller(fake);
    await _exhaust(c);
    final Duration spentBefore = c.airtimeSpent;
    fake.sent.clear();

    final ChatMessage? m =
        await c.sendChannelTextTo(0, '[SOS:abc123] test', urgent: true);

    expect(m, isNotNull, reason: 'the row exists, so the send was attempted');
    expect(fake.sent, isNotEmpty,
        reason: 'an alarm must reach the radio even when the meter is full');
    expect(c.airtimeSpent, greaterThan(spentBefore),
        reason: 'and it is still charged, or the meter would lie');
  });

  test('an urgent direct message is written when the window is full', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _controller(fake);
    await _exhaust(c);
    fake.sent.clear();

    final String key = List<String>.filled(32, 'ab').join();
    final ChatMessage? m =
        await c.sendDirectText(key, '[SAFE:abc123]', urgent: true);

    expect(m, isNotNull);
    expect(fake.sent, isNotEmpty);
  });
}
