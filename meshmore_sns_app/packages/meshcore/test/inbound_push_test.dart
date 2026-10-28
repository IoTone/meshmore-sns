// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:test/test.dart';

/// Layouts transcribed from `examples/companion_radio/MyMesh.cpp`:
/// `onRawDataRecv` (:801-818), `onContactPathUpdated` (:404-410),
/// `onChannelDataRecv` (:588-618), `onContactsFull` (:346-350).
void main() {
  test('PUSH_CODE_RAW_DATA 0x84: snr*4, rssi, 0xFF reserved, then payload', () {
    final MeshcoreInbound f = MeshcoreFrameCodec.decode(Uint8List.fromList(
        <int>[0x84, 0xF4 /* -12 -> -3.0 dB */, 0xA6 /* -90 */, 0xFF, 9, 8, 7]));
    expect(f, isA<RawDataFrame>());
    final RawDataFrame r = f as RawDataFrame;
    expect(r.snrDb, -3.0);
    expect(r.rssi, -90);
    expect(r.payload, <int>[9, 8, 7]);
  });

  test('a raw data push with no payload decodes to an empty payload', () {
    final RawDataFrame r = MeshcoreFrameCodec.decode(
        Uint8List.fromList(<int>[0x84, 4, 0xB0, 0xFF])) as RawDataFrame;
    expect(r.snrDb, 1.0);
    expect(r.payload, isEmpty);
  });

  test('a truncated raw data push is a DecodeFailure, never a throw', () {
    expect(MeshcoreFrameCodec.decode(Uint8List.fromList(<int>[0x84, 1])),
        isA<DecodeFailure>());
  });

  test('PUSH_CODE_PATH_UPDATED 0x81 carries only the 32-byte key', () {
    final Uint8List key = Uint8List.fromList(List<int>.generate(32, (int i) => i));
    final MeshcoreInbound f =
        MeshcoreFrameCodec.decode(Uint8List.fromList(<int>[0x81, ...key]));
    expect((f as PathUpdatedFrame).publicKey, key);
    expect(MeshcoreFrameCodec.decode(Uint8List.fromList(<int>[0x81, 1, 2])),
        isA<DecodeFailure>());
  });

  test('RESP_CODE_CHANNEL_DATA_RECV 0x1B: little-endian data_type, flood path',
      () {
    final MeshcoreInbound f = MeshcoreFrameCodec.decode(Uint8List.fromList(<int>[
      0x1B, 8, 0, 0, 2, 0xFF, 0x34, 0xFF, 3, 1, 2, 3,
    ]));
    final ChannelDataFrame d = f as ChannelDataFrame;
    expect(d.snrDb, 2.0);
    expect(d.channelIndex, 2);
    expect(d.pathLen, 0xFF);
    expect(d.dataType, 0xFF34);
    expect(d.data, <int>[1, 2, 3]);
  });

  test('a channel data length that overruns the frame is a DecodeFailure', () {
    expect(
        MeshcoreFrameCodec.decode(Uint8List.fromList(
            <int>[0x1B, 0, 0, 0, 0, 0, 1, 0, 9, 1])),
        isA<DecodeFailure>());
  });

  test('PUSH_CODE_CONTACTS_FULL 0x90 and its constant exist', () {
    expect(MeshcoreFrameCodec.decode(Uint8List.fromList(<int>[0x90])),
        isA<ContactsFullFrame>());
    expect(MeshcoreResponse.contactsFull.code, 0x90);
    expect(MeshcoreResponse.rawData.code, 0x84);
    expect(MeshcoreResponse.pathUpdated.code, 0x81);
  });
}
