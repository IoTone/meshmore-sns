// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// A friendly acknowledgement reports this radio's own measurements of the
/// packet that carried the row, so the row has to hold them first: the SNR comes
/// with the message, and the RSSI and the route only with the RF-log capture of
/// the same packet.
///
/// V3 channel message: `[0x11][snr*4][rsvd][rsvd][ch][path_len][txt_type][ts][text]`.
Uint8List channelMsgV3({
  int idx = 0,
  required String text,
  required double snrDb,
  int pathLen = 0xFF,
  int ts = 1700000000,
}) =>
    Uint8List.fromList(<int>[
      0x11,
      (snrDb * 4).round() & 0xFF,
      0,
      0,
      idx,
      pathLen,
      0x00,
      ts & 0xFF,
      (ts >> 8) & 0xFF,
      (ts >> 16) & 0xFF,
      (ts >> 24) & 0xFF,
      ...text.codeUnits,
    ]);

/// `PUSH_CODE_LOG_RX_DATA`: `[0x88][snr*4][rssi][raw OTA packet]`, where the OTA
/// packet is a GRP_TXT that collected [path] in [hashSize]-byte hashes.
Uint8List rfLogGrpTxt({
  required double snrDb,
  required int rssi,
  required List<int> path,
  int hashSize = 2,
  int? channelHash,
}) {
  // A Public-channel packet carries the Public channel's own hash, which is what
  // the app compares a capture against before lending its measurements to a row.
  final int hash = channelHash ??
      MeshcoreChannelCrypto.channelHashFromPsk(List<int>.from(kPublicChannelPsk));
  final int header =
      kRouteFlood | (kPayloadTypeGrpTxt << kPktPayloadTypeShift);
  final int hops = path.length ~/ hashSize;
  final int pathLen = hops | ((hashSize - 1) << kPathHashSizeShift);
  return Uint8List.fromList(<int>[
    0x88,
    (snrDb * 4).round() & 0xFF,
    rssi & 0xFF,
    header,
    pathLen,
    ...path,
    hash, 0x01, 0x02, // GRP_TXT payload stub: channel hash + MAC
  ]);
}

void main() {
  test('a captured packet gives the row its RSSI, hops and route', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    addTearDown(mc.dispose);
    await mc.connect();
    fake.emit(selfInfoFrame());
    // The radio logs the packet it heard, then pushes the message for it.
    fake.emit(rfLogGrpTxt(
        snrDb: 12.5, rssi: -38, path: <int>[0x44, 0x90, 0xDF, 0x7C, 0x7F, 0x47]));
    fake.emit(channelMsgV3(text: 'Half Live: insomnia crew check in', snrDb: 12.5));
    await Future<void>.delayed(Duration.zero);

    final ChatMessage row = mc.messagesFor(0).first;
    expect(row.snrDb, 12.5);
    expect(row.rssiDbm, -38, reason: 'the RSSI is only in the RF log');
    expect(row.hopCount, 3, reason: 'a flood reports 0xFF, so the count is the capture');
    expect(row.pathHashes, <String>['4490', 'DF7C', '7F47']);

    // The line is composed for the composer, never sent by the action: the
    // reader decides when it goes.
    expect(
        mc.friendlyAckLineFor(row),
        '@[Half Live] ack: SNR 12.5 dB, RSSI -38 dBm, 3 hops via 4490, DF7C, 7F47',
        reason: 'the line other clients parse, naming the reader');
    expect(mc.messagesFor(0).length, 1,
        reason: 'composing an ack puts nothing on the air');
  });

  test('a message with no capture reports only what the frame carried', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    addTearDown(mc.dispose);
    await mc.connect();
    fake.emit(selfInfoFrame());
    // No RF log this time: a direct-path message carries its own hop count.
    fake.emit(channelMsgV3(
        text: 'St. Joseph: Good morning', snrDb: 9.25, pathLen: 2));
    await Future<void>.delayed(Duration.zero);

    final ChatMessage row = mc.messagesFor(0).first;
    expect(row.rssiDbm, isNull);
    expect(row.hopCount, 2);
    expect(row.pathHashes, isEmpty);

    expect(mc.friendlyAckLineFor(row),
        '@[St. Joseph] ack: SNR 9.3 dB, 2 hops');
  });

  test('two messages inside the window do not share one capture', () async {
    // The radio logs each packet once, so a capture answers one row. Pairing on
    // the SNR keeps them apart when their measurements differ.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    addTearDown(mc.dispose);
    await mc.connect();
    fake.emit(selfInfoFrame());
    fake.emit(rfLogGrpTxt(snrDb: 12.5, rssi: -38, path: <int>[0x44, 0x90]));
    fake.emit(rfLogGrpTxt(snrDb: 6.25, rssi: -95, path: <int>[0xAA, 0xBB]));
    fake.emit(channelMsgV3(text: 'A: first', snrDb: 6.25));
    fake.emit(channelMsgV3(text: 'B: second', snrDb: 12.5));
    await Future<void>.delayed(Duration.zero);

    final List<ChatMessage> rows = mc.messagesFor(0).where((ChatMessage m) => !m.outgoing).toList();
    final ChatMessage first = rows.firstWhere((ChatMessage m) => m.text == 'A: first');
    final ChatMessage second = rows.firstWhere((ChatMessage m) => m.text == 'B: second');
    expect(first.rssiDbm, -95, reason: 'paired on the SNR the two share');
    expect(first.pathHashes, <String>['AABB']);
    expect(second.rssiDbm, -38);
    expect(second.pathHashes, <String>['4490']);
  });

  test('a capture on another channel is never lent to this row', () async {
    // The message frame carries no route, so the RSSI and the path come from the
    // RF-log capture of the same packet. The capture carries the packet's own
    // channel hash, and comparing it is what stops a `#cos` row reporting the
    // signal of a packet heard on `#public`.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    addTearDown(mc.dispose);
    await mc.connect();
    fake.emit(selfInfoFrame());
    // A GRP_TXT capture with a channel hash that is not slot 0's.
    Uint8List otherChannel(int hash) => Uint8List.fromList(<int>[
          0x88,
          (6.25 * 4).round(),
          (-90) & 0xFF,
          kRouteFlood | (kPayloadTypeGrpTxt << kPktPayloadTypeShift),
          2 | ((2 - 1) << kPathHashSizeShift),
          0xAA, 0xBB, 0xCC, 0xDD,
          hash, 0x00, 0x01,
        ]);
    // Slot 0's PSK is the public one; use a hash that cannot be it.
    final int publicHash = MeshcoreChannelCrypto.channelHashFromPsk(
        List<int>.from(kPublicChannelPsk));
    fake.emit(otherChannel((publicHash + 7) & 0xFF));
    fake.emit(channelMsgV3(text: 'A: hi', snrDb: 6.25));
    await Future<void>.delayed(Duration.zero);

    final ChatMessage row = mc.messagesFor(0).first;
    expect(row.snrDb, 6.25, reason: 'the SNR comes with the message itself');
    expect(row.rssiDbm, isNull,
        reason: 'the capture was on another channel, so it is not this row\'s');
    expect(row.pathHashes, isEmpty);
  });
}
