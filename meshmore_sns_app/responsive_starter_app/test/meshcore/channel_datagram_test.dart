// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/channel_datagram.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// `RESP_CODE_CHANNEL_DATA_RECV` as the radio writes it
/// (`MyMesh.cpp:592-616`): `[1B][snr*4][reserved1][reserved2][channel]
/// [path_len][type u16][len][blob]`.
Uint8List channelDataFrame({
  int snrTimesFour = 12,
  int reserved1 = 0,
  int channel = 1,
  int pathLen = 0xFF,
  required int dataType,
  required List<int> blob,
}) {
  final Uint8List out = Uint8List(9 + blob.length);
  out[0] = 0x1B;
  out[1] = snrTimesFour;
  out[2] = reserved1;
  out[3] = 0;
  out[4] = channel;
  out[5] = pathLen;
  out[6] = dataType & 0xFF;
  out[7] = (dataType >> 8) & 0xFF;
  out[8] = blob.length;
  out.setRange(9, 9 + blob.length, blob);
  return out;
}

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

  test('a datagram of a type this build never heard of still reaches the app',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);

    final Future<ChannelDatagram> next = c.channelDatagramStream.first;
    fake.emit(channelDataFrame(
      dataType: 0xFF01,
      channel: 3,
      blob: const <int>[1, 2, 3, 4],
      reserved1: 0xA1,
    ));
    final ChannelDatagram d = await next.timeout(const Duration(seconds: 1));

    expect(d.channelIndex, 3);
    expect(d.dataType, 0xFF01);
    expect(d.blob, const <int>[1, 2, 3, 4]);
    expect(d.rxVia, RxVia.secondary);
    expect(d.snrDb, 3.0);
    expect(d.isFlood, isTrue);
    expect(c.channelDatagrams.single.dataType, 0xFF01);
    expect(c.channelDatagramsUnrecognised, 1,
        reason: 'only DATA_TYPE_DEV is a type this build interprets');
    c.dispose();
  });

  test('the dev type is recognised, and the ring keeps the newest 32',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);

    for (int i = 0; i < 40; i++) {
      fake.emit(channelDataFrame(dataType: kChannelDataTypeDev, blob: <int>[i]));
      await Future<void>.delayed(Duration.zero);
    }
    expect(c.channelDatagrams.length, 32);
    expect(c.channelDatagrams.last.blob.single, 39);
    expect(c.channelDatagrams.first.blob.single, 8);
    expect(c.channelDatagramsUnrecognised, 0);
    c.dispose();
  });

  test('a truncated datagram is counted as a truncation, not delivered',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    // Says nine bytes follow, carries two.
    fake.emit(Uint8List.fromList(<int>[
      0x1B, 0x0C, 0x00, 0x00, 0x01, 0xFF, 0x01, 0xFF, 0x09, 0xAA, 0xBB,
    ]));
    await Future<void>.delayed(Duration.zero);
    expect(c.channelDatagrams, isEmpty);
    expect(c.truncatedFrames, greaterThan(0));
    c.dispose();
  });
}
