// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:meshmore_sns_app/meshcore/gateway/mesh_sender_adapter.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_connection.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fake_transport.dart';

Uint8List _key(int first) => Uint8List.fromList(
    <int>[for (int i = 0; i < 32; i++) (first + i) & 0xFF]);

Future<(MeshcoreController, FakeMeshcoreTransport)> _ready() async {
  final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
  final MeshcoreController c = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await c.connect();
  fake.emit(selfInfoFrame());
  for (int i = 0; i < 50 && !c.isReady; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return (c, fake);
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  late MeshcoreController mc;
  late FakeMeshcoreTransport fake;
  late MeshcoreMeshSender sender;
  bool up = false;

  Future<void> setUpRadio({
    int outPathLen = 0,
    List<int> path = const <int>[],
    Duration timeout = const Duration(seconds: 2),
  }) async {
    (mc, fake) = await _ready();
    up = true;
    fake.emit(contactFrame(
        name: 'peer', firstPubByte: 70, outPathLen: outPathLen, path: path));
    await _tick();
    sender = MeshcoreMeshSender(mc, answerTimeout: timeout);
  }

  tearDown(() async {
    if (!up) return;
    up = false;
    await sender.dispose();
    mc.dispose();
  });

  List<Uint8List> rawSends() =>
      fake.sent.where((Uint8List f) => f.isNotEmpty && f[0] == 0x19).toList();

  group('binding', () {
    test('a known contact with a direct path binds', () async {
      await setUpRadio(outPathLen: 2, path: <int>[0xAA, 0xBB]);
      expect(await sender.isContact(_key(70)), isTrue);
      expect(await sender.bindPeer(_key(70)), isNull);
      // 174 - 2 path bytes = 172, which is the absolute ceiling.
      expect(sender.uplinkRecordMax, 172);
    });

    test('a stranger is not a contact', () async {
      await setUpRadio();
      expect(await sender.isContact(_key(1)), isFalse);
      expect(await sender.bindPeer(_key(1)), BindError.notAContact);
    });

    test('0xFF (no path) is refused, not read as a 64-byte path', () async {
      await setUpRadio(outPathLen: 0xFF);
      expect(await sender.bindPeer(_key(70)), BindError.noPath);
    });

    test('a path too long to carry the 160 B floor is refused', () async {
      // 15 one-byte hops leaves 174 - 15 = 159 B.
      await setUpRadio(outPathLen: 15, path: List<int>.filled(15, 7));
      expect(await sender.bindPeer(_key(70)), BindError.noPath);
    });

    test('a 14-hop path is the longest that still binds', () async {
      await setUpRadio(outPathLen: 14, path: List<int>.filled(14, 7));
      expect(await sender.bindPeer(_key(70)), isNull);
      expect(sender.uplinkRecordMax, 160);
    });

    test('a 2-byte hash path counts bytes, not hops', () async {
      // raw = (hashSize-1)<<6 | hops = 0x40 | 8 -> 8 hops x 2 B = 16 B,
      // which leaves 158 B: refused. Reading the raw byte (72) or the hop
      // count (8) would get this wrong either way.
      await setUpRadio(outPathLen: 0x48, path: List<int>.filled(16, 9));
      expect(await sender.bindPeer(_key(70)), BindError.noPath);
    });
  });

  group('sending', () {
    test('writes CMD_SEND_RAW_DATA with the contact path and the record',
        () async {
      await setUpRadio(outPathLen: 2, path: <int>[0xAA, 0xBB]);
      await sender.bindPeer(_key(70));
      final Uint8List record = Uint8List.fromList(List<int>.filled(10, 0x5A));

      final Future<SendOutcome> out = sender.sendRecord(record, seq: 1);
      await _tick();
      await _tick();
      expect(rawSends(), hasLength(1));
      expect(rawSends().single,
          <int>[0x19, 2, 0xAA, 0xBB, ...List<int>.filled(10, 0x5A)]);

      fake.emit(Uint8List.fromList(<int>[0x00])); // RESP_CODE_OK
      expect(await out, SendOutcome.sentDirect);
    });

    test('ERR not_found maps to errNotFound; table_full to errBusy',
        () async {
      await setUpRadio();
      await sender.bindPeer(_key(70));

      final Future<SendOutcome> a =
          sender.sendRecord(Uint8List(8), seq: 1);
      await _tick();
      await _tick();
      fake.emit(errorFrame(2));
      expect(await a, SendOutcome.errNotFound);

      final Future<SendOutcome> b =
          sender.sendRecord(Uint8List(8), seq: 2);
      await _tick();
      await _tick();
      fake.emit(errorFrame(3));
      expect(await b, SendOutcome.errBusy);
    });

    test('no answer is localTimeout and frees the slot for the next send',
        () async {
      await setUpRadio(timeout: const Duration(milliseconds: 40));
      await sender.bindPeer(_key(70));
      expect(await sender.sendRecord(Uint8List(8), seq: 1),
          SendOutcome.localTimeout);

      final Future<SendOutcome> next =
          sender.sendRecord(Uint8List(8), seq: 2);
      await _tick();
      await _tick();
      fake.emit(Uint8List.fromList(<int>[0x00]));
      expect(await next, SendOutcome.sentDirect);
    });

    test('sends are serialised: the second waits for the first answer',
        () async {
      await setUpRadio();
      await sender.bindPeer(_key(70));
      final Future<SendOutcome> a = sender.sendRecord(Uint8List(8), seq: 1);
      final Future<SendOutcome> b = sender.sendRecord(Uint8List(8), seq: 2);
      await _tick();
      await _tick();
      expect(rawSends(), hasLength(1), reason: 'second must not be written');
      fake.emit(Uint8List.fromList(<int>[0x00]));
      expect(await a, SendOutcome.sentDirect);
      await _tick();
      await _tick();
      expect(rawSends(), hasLength(2));
      fake.emit(Uint8List.fromList(<int>[0x00]));
      expect(await b, SendOutcome.sentDirect);
    });

    test('a record under the 4-byte raw-data minimum is refused locally',
        () async {
      await setUpRadio();
      await sender.bindPeer(_key(70));
      expect(await sender.sendRecord(Uint8List(3), seq: 1),
          SendOutcome.errTooLong);
      expect(rawSends(), isEmpty);
    });

    test('a record over the path-dependent maximum is refused locally',
        () async {
      await setUpRadio(outPathLen: 14, path: List<int>.filled(14, 7));
      await sender.bindPeer(_key(70));
      expect(await sender.sendRecord(Uint8List(161), seq: 1),
          SendOutcome.errTooLong);
      expect(rawSends(), isEmpty);
    });

    test('the OK for a raw send is not credited to a chat message',
        () async {
      await setUpRadio();
      await sender.bindPeer(_key(70));
      final Future<SendOutcome> out = sender.sendRecord(Uint8List(8), seq: 1);
      await _tick();
      await _tick();
      // A channel message queued behind it must still be waiting for ITS OK.
      await mc.sendChannelText('hello');
      fake.emit(Uint8List.fromList(<int>[0x00]));
      await out;
      await _tick();
      expect(mc.messagesFor(0).single.delivery, MessageDelivery.sending,
          reason: 'the raw OK was consumed by the raw marker, not the chat');
    });
  });

  group('receiving and status', () {
    test('PUSH_CODE_RAW_DATA payload reaches inbound and updates rssi',
        () async {
      await setUpRadio();
      final Future<Uint8List> next = sender.inbound.first;
      // [84][snr*4][rssi][reserved FF][payload]
      fake.emit(Uint8List.fromList(
          <int>[0x84, 20, (-90) & 0xFF, 0xFF, 1, 2, 3, 4]));
      expect(await next, <int>[1, 2, 3, 4]);
      expect(sender.rssiDbm, -90);
    });

    test('radio state follows the link and is pushed on change', () async {
      await setUpRadio();
      expect(sender.radioState, RadioState.connected);
      final Future<RadioState> change = sender.radioStateChanges.first;
      fake.setConnected(false);
      expect(await change.timeout(const Duration(seconds: 2)),
          isNot(RadioState.connected));
    });

    test('dispose is idempotent', () async {
      await setUpRadio();
      await sender.dispose();
      await sender.dispose();
    });
  });

  group('estimatorFor', () {
    SelfInfo radio({required double bw, required int sf, required int cr}) {
      return SelfInfo(
        advType: 1,
        txPowerDbm: 20,
        maxTxPowerDbm: 22,
        publicKey: Uint8List(32),
        latitude: 0,
        longitude: 0,
        multiAcks: 0,
        advertLocPolicy: 0,
        telemetryModeRaw: 0,
        manualAddContacts: false,
        frequencyMhz: 910.525,
        bandwidthKhz: bw,
        spreadingFactor: sf,
        codingRate: cr,
        name: 'x',
      );
    }

    test('a slower radio is estimated slower (not the flat 4 ms/B default)',
        () {
      final Duration usa =
          estimatorFor(radio(bw: 62.5, sf: 7, cr: 5)).forBytes(160);
      final Duration eu =
          estimatorFor(radio(bw: 62.5, sf: 8, cr: 8)).forBytes(160);
      expect(eu, greaterThan(usa * 2));
    });

    test('unknown radio uses the slowest preset, never less than any',
        () {
      final Duration unknown = estimatorFor(null).forBytes(172);
      final Duration usa =
          estimatorFor(radio(bw: 62.5, sf: 7, cr: 5)).forBytes(172);
      expect(unknown, greaterThanOrEqualTo(usa));
      expect(unknown, greaterThan(const Duration(milliseconds: 1500)));
    });
  });
}
