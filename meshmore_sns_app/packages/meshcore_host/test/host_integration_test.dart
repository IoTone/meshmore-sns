// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:meshcore_host/meshcore_host.dart';
import 'package:test/test.dart';

/// A fake companion radio that speaks the firmware's USB-serial framing.
///
/// It answers only what the host path actually needs, using the same codec
/// the host uses, so this test proves the composition (framing -> L1 link ->
/// MeshSender -> L2 Gateway -> loopback client) rather than a mock of it.
class FakeRadio {
  FakeRadio({required this.selfKey, required this.peerKey});

  final Uint8List selfKey;
  final Uint8List peerKey;
  final StreamController<List<int>> _out = StreamController<List<int>>();
  final SerialFrameDecoder _decoder =
      SerialFrameDecoder(header: SerialFraming.hostHeader);
  final List<Uint8List> sentRawPayloads = <Uint8List>[];

  Stream<List<int>> get out => _out.stream;

  void _emit(List<int> frame) {
    _out.add(encodeRadioFrame(frame));
  }

  Future<void> receive(List<int> bytes) async {
    for (final Uint8List frame in _decoder.add(bytes)) {
      switch (frame.first) {
        case 0x01: // APP_START
          _emit(_selfInfo());
        case 0x04: // GET_CONTACTS
          _emit(<int>[0x02, 0x00, 0x01, 0x00]); // CONTACTS_START, count 1
          _emit(_contact());
          _emit(<int>[0x04, 0x00, 0x00, 0x00, 0x00]); // END_OF_CONTACTS
        case 0x38: // GET_STATS
          if (frame.length > 1 && frame[1] == kStatsTypeRadio) {
            _emit(<int>[
              0x18, 0x01, // RESP_CODE_STATS, radio
              0x92, // noise -110
              185, // lastRssi -71 as signed byte
              20, // snr 5.0 in quarters
              1, 0, 0, 0, // txAirSecs
              2, 0, 0, 0, // rxAirSecs
            ]);
          }
        case 0x19: // SEND_RAW_DATA
          final int pathLen = frame[1];
          sentRawPayloads
              .add(Uint8List.fromList(frame.sublist(2 + pathLen)));
          _emit(<int>[0x00, 0x00, 0x00, 0x00, 0x00]); // OK
        default:
          _emit(<int>[0x01, 0x01]); // ERR unsupported
      }
    }
  }

  Uint8List _selfInfo() {
    final BytesBuilder b = BytesBuilder()
      ..addByte(0x05) // SELF_INFO
      ..addByte(1) // advType
      ..addByte(22) // txPower
      ..addByte(22) // maxTxPower
      ..add(selfKey)
      ..add(<int>[0, 0, 0, 0]) // lat
      ..add(<int>[0, 0, 0, 0]) // lon
      ..addByte(0) // multiAcks
      ..addByte(0) // advertLocPolicy
      ..addByte(0) // telemetryMode
      ..addByte(0) // manualAddContacts
      ..add(_u32(910525)) // 910.525 MHz
      ..add(_u32(62500)) // 62.5 kHz
      ..addByte(7) // SF7
      ..addByte(5) // CR5
      ..add('host-radio'.codeUnits);
    return b.takeBytes();
  }

  Uint8List _contact() {
    final Uint8List path = Uint8List(kMaxPathSize)..[0] = 0x11;
    final Uint8List name = Uint8List(kContactNameSize)
      ..setRange(0, 4, 'peer'.codeUnits);
    final BytesBuilder b = BytesBuilder()
      ..addByte(0x03) // CONTACT
      ..add(peerKey)
      ..addByte(1) // type
      ..addByte(0) // flags
      ..addByte(1) // out_path_len: one hop, one-byte hash
      ..add(path)
      ..add(name)
      ..add(_u32(0)) // lastAdvertTimestamp
      ..add(_u32(0)) // lat
      ..add(_u32(0)) // lon
      ..add(_u32(0)); // lastMod
    return b.takeBytes();
  }

  Future<void> close() => _out.close();
}

List<int> _u32(int v) => <int>[
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
    ];

Uint8List encodeRadioFrame(List<int> payload) {
  final Uint8List out = Uint8List(3 + payload.length);
  out[0] = 0x3C; // '<'
  out[1] = payload.length & 0xFF;
  out[2] = (payload.length >> 8) & 0xFF;
  out.setRange(3, out.length, payload);
  return out;
}

void main() {
  test('framing + L1 link + MeshSender + L2 gateway carry a real record',
      () async {
    final Uint8List selfKey = Uint8List(32)..fillRange(0, 32, 0x5A);
    final Uint8List peerKey = Uint8List(32)..fillRange(0, 32, 0xAB);
    final FakeRadio radio = FakeRadio(selfKey: selfKey, peerKey: peerKey);

    final SerialFrameTransport transport = SerialFrameTransport(
      inboundBytes: radio.out,
      write: radio.receive,
    )..start();
    transport.setConnected(true);

    final MeshcoreConnection link =
        MeshcoreConnection(appName: 'host-test')..attach(transport);

    await link.states
        .firstWhere((MeshcoreConnectionState s) =>
            s == MeshcoreConnectionState.ready)
        .timeout(const Duration(seconds: 2));
    expect(link.selfInfo?.name, 'host-radio');

    final SerialMeshSender sender =
        SerialMeshSender(link: MeshcoreConnectionLink(link))..start();

    final Gateway gateway = Gateway(mesh: sender, port: 0);
    await gateway.start();
    addTearDown(() async {
      await gateway.stop();
      await sender.dispose();
      await link.dispose();
      await transport.close();
      await radio.close();
    });

    final GatewayClient client = GatewayClient();
    await client.connect(port: gateway.port);
    final ({int capabilities, RadioState radioState}) hello =
        await client.hello();
    expect(hello.capabilities, isNonNegative);
    await client.pair(gateway.pairingToken);

    final ({int capabilities, int uplinkRecordMax}) bound =
        await client.bind(peerKey);
    expect(bound.uplinkRecordMax, GatewayLimits.recordMax);

    final Uint8List record = Uint8List.fromList(<int>[0xDE, 0xAD, 0xBE, 0xEF]);
    client.sendRecord(seq: 1, record: record);
    final ({int seq, SendOutcome outcome}) result =
        await client.nextSendResult();
    expect(result.outcome, SendOutcome.sentDirect);

    // The radio saw the record, behind the one-hop path, exactly once.
    expect(radio.sentRawPayloads, hasLength(1));
    expect(radio.sentRawPayloads.single, record);

    await client.close();
  }, timeout: const Timeout(Duration(seconds: 20)));
}
