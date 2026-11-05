// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/channel_datagram.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

Future<MeshcoreController> _ready(FakeMeshcoreTransport fake) async {
  final MeshcoreController c = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    channelDataTimeout: const Duration(milliseconds: 40),
  );
  await c.connect();
  fake.emit(selfInfoFrame());
  await Future<void>.delayed(Duration.zero);
  return c;
}

String _hex(Uint8List b) =>
    b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a datagram leaves as one 0x3E frame and the radio\'s OK accepts it',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);

    final Future<ChannelDataSendResult> pending = c.sendChannelData(
      channelIdx: 2,
      dataType: kChannelDataTypeDev,
      blob: <int>[9, 8, 7],
    );
    await Future<void>.delayed(Duration.zero);
    expect(fake.sent.last[0], 0x3E);
    expect(_hex(fake.sent.last), '3e02ffffff090807');

    fake.emit(Uint8List.fromList(<int>[0x00]));
    final ChannelDataSendResult r = await pending;
    expect(r.status, ChannelDataSendStatus.accepted);
    expect(c.unclaimedReplies, 0);
    c.dispose();
  });

  test('an ERR comes back with the firmware code, not a vague failure',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);

    final Future<ChannelDataSendResult> pending = c.sendChannelData(
      channelIdx: 9,
      dataType: kChannelDataTypeDev,
      blob: <int>[1],
    );
    await Future<void>.delayed(Duration.zero);
    // ERR_CODE_NOT_FOUND: the radio has no such channel slot.
    fake.emit(Uint8List.fromList(<int>[0x01, MeshcoreErrorCode.notFound.code]));
    final ChannelDataSendResult r = await pending;

    expect(r.status, ChannelDataSendStatus.refusedByRadio);
    expect(r.errorCode, MeshcoreErrorCode.notFound.code);
    c.dispose();
  });

  test('an over-long blob is refused before anything is written', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    final int sentBefore = fake.sent.length;

    final ChannelDataSendResult r = await c.sendChannelData(
      channelIdx: 0,
      dataType: kChannelDataTypeDev,
      blob: List<int>.filled(ChannelDataLimits.maxBlob + 1, 0),
    );

    expect(r.status, ChannelDataSendStatus.refusedLocally);
    expect(r.refusal, ChannelDataRefusal.blobTooLongForDatagram);
    expect(fake.sent.length, sentBefore, reason: 'nothing reached the radio');
    c.dispose();
  });

  test('two datagrams in flight keep their own answers', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);

    int datagrams() => fake.sent.where((Uint8List f) => f[0] == 0x3E).length;
    final Future<ChannelDataSendResult> first =
        c.sendChannelData(channelIdx: 0, dataType: 0xFF01, blob: <int>[1]);
    final Future<ChannelDataSendResult> second =
        c.sendChannelData(channelIdx: 1, dataType: 0xFF02, blob: <int>[2]);
    await Future<void>.delayed(Duration.zero);
    expect(datagrams(), 1,
        reason: 'the answer has no tag, so the second waits its turn');

    fake.emit(Uint8List.fromList(<int>[0x00]));
    expect((await first).status, ChannelDataSendStatus.accepted);
    await Future<void>.delayed(Duration.zero);
    expect(datagrams(), 2);
    expect(fake.sent.last[1], 1, reason: 'the second datagram, channel 1');
    fake.emit(Uint8List.fromList(<int>[0x01, 6]));
    expect((await second).status, ChannelDataSendStatus.refusedByRadio);
    c.dispose();
  });

  test('an answer that never comes is reported, not assumed', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    final ChannelDataSendResult r = await c
        .sendChannelData(channelIdx: 0, dataType: 0xFF01, blob: <int>[1]);
    expect(r.status, ChannelDataSendStatus.noAnswer,
        reason: 'the deadline passed with no OK');
    c.dispose();
  });
}
