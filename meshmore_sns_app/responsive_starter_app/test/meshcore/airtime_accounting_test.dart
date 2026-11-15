// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';

/// Airtime is **channel** time. Most of this app's frames are BLE questions to
/// the radio in the reader's hand and never touch the shared channel, so charging
/// them made the meter answer the wrong question — and on a busy session that
/// inflated window is what refuses the reader's next message.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<(MeshcoreController, FakeMeshcoreTransport)> ready() async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await mc.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return (mc, fake);
  }

  test('a BLE read of the battery costs no airtime', () async {
    final (MeshcoreController mc, _) = await ready();
    final Duration before = mc.airtimeSpent;
    await mc.send(MeshcoreFrameCodec.getBatteryStorage());
    expect(mc.airtimeSpent, before,
        reason: 'reading the battery is a question to the radio, not a '
            'transmission on the shared channel');
    mc.dispose();
  });

  test('a channel message is charged', () async {
    final (MeshcoreController mc, _) = await ready();
    final Duration before = mc.airtimeSpent;
    await mc.send(MeshcoreFrameCodec.sendChannelTextMessage(
      channelIdx: 0,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      text: 'hello',
    ));
    expect(mc.airtimeSpent, greaterThan(before),
        reason: 'this one does occupy the channel');
    mc.dispose();
  });

  test('a self advert is charged', () async {
    final (MeshcoreController mc, _) = await ready();
    final Duration before = mc.airtimeSpent;
    await mc.send(MeshcoreFrameCodec.sendSelfAdvert(flood: false));
    expect(mc.airtimeSpent, greaterThan(before));
    mc.dispose();
  });

  test('the classification names exactly the transmitters', () {
    // The codec's own transmitters; anything else is a local request.
    for (final int op in <int>[0x02, 0x03, 0x07, 0x19, 0x1B, 0x24, 0x27,
      0x32, 0x37, 0x3E, 0x41]) {
      expect(MeshcoreController.isOverTheAir(op), isTrue,
          reason: '0x${op.toRadixString(16)} transmits and must be charged');
    }
    // 0x0E is `CMD_SET_ADVERT_LATLON`, which sets the position the radio will
    // advertise next rather than transmitting anything: charging it made every
    // auto-publish pay twice for one advert.
    for (final int op in <int>[0x01, 0x04, 0x05, 0x0A, 0x0E, 0x14, 0x1F, 0x28]) {
      expect(MeshcoreController.isOverTheAir(op), isFalse,
          reason: '0x${op.toRadixString(16)} is a BLE request');
    }
    expect(MeshcoreController.isOverTheAir(0xFF), isFalse);
  });

  test('an empty frame cannot confuse the classifier', () async {
    final (MeshcoreController mc, _) = await ready();
    final Duration before = mc.airtimeSpent;
    await mc.send(Uint8List(0));
    expect(mc.airtimeSpent, before);
    mc.dispose();
  });
}
