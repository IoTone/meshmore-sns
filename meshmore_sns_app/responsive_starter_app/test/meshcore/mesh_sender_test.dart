// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/mesh_sender.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

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

String _hex(int first) =>
    <int>[for (int i = 0; i < 32; i++) (first + i) & 0xFF]
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

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

  /// The contact the radio reported, as the app's cache holds it.
  Contact peer() => mc.contactRecordFor(_hex(70))!;

  List<Uint8List> rawSends() =>
      fake.sent.where((Uint8List f) => f.isNotEmpty && f[0] == 0x19).toList();

  group('addressing', () {
    test('a contact with a direct path sets the record budget from its path',
        () async {
      await setUpRadio(outPathLen: 2, path: <int>[0xAA, 0xBB]);
      // 176 - 1 opcode - 1 path_len - 2 path bytes.
      expect(MeshcoreMeshSender.recordMaxFor(peer()), 172);
      expect(MeshcoreMeshSender.airtimeOverheadFor(peer()), 4);
    });

    test('a zero-hop neighbour is a real route, not "no route"', () async {
      await setUpRadio(outPathLen: 0);
      expect(MeshcoreMeshSender.recordMaxFor(peer()), 174);
      final Future<SendOutcome> out =
          sender.sendRecord(Uint8List(8), to: peer());
      await _tick();
      await _tick();
      expect(rawSends().single.sublist(0, 2), <int>[0x19, 0]);
      fake.emit(Uint8List.fromList(<int>[0x00]));
      expect(await out, SendOutcome.sentDirect);
    });

    test('0xFF (no path) refuses the send and writes nothing', () async {
      await setUpRadio(outPathLen: 0xFF);
      expect(await sender.sendRecord(Uint8List(8), to: peer()),
          SendOutcome.errNotFound);
      expect(rawSends(), isEmpty);
    });

    test('a 14-hop one-byte path leaves exactly the 160-byte budget',
        () async {
      await setUpRadio(outPathLen: 14, path: List<int>.filled(14, 7));
      expect(MeshcoreMeshSender.recordMaxFor(peer()), 160);
      expect(MeshcoreMeshSender.airtimeOverheadFor(peer()), 16);
    });

    test('a two-byte hash path counts bytes, not hops', () async {
      // raw = (hashSize-1)<<6 | hops = 0x40 | 8 -> 8 hops x 2 B = 16 B.
      // Reading the raw byte (72) or the hop count (8) gets this wrong.
      await setUpRadio(outPathLen: 0x48, path: List<int>.filled(16, 9));
      expect(MeshcoreMeshSender.recordMaxFor(peer()), 158);
    });

    test('a contact the radio does not hold is refused, not guessed', () async {
      // The radio is the authority for routes: a key the app cannot resolve
      // to a current contact record has no path to address, whatever the
      // caller believes.
      await setUpRadio(outPathLen: 2, path: <int>[0xAA, 0xBB]);
      final Contact stranger = Contact(
        publicKey: Uint8List.fromList(
            <int>[for (int i = 0; i < 32; i++) (200 + i) & 0xFF]),
        type: 0,
        flags: 0,
        outPathLen: 2,
        outPath: Uint8List.fromList(<int>[0xAA, 0xBB, ...List<int>.filled(62, 0)]),
        name: 'stranger',
        lastAdvertTimestamp: 0,
        latitudeMicros: 0,
        longitudeMicros: 0,
        lastMod: 0,
      );
      expect(await sender.sendRecord(Uint8List(8), to: stranger),
          SendOutcome.errNotFound);
      expect(rawSends(), isEmpty);
    });
  });

  group('sending', () {
    test('writes CMD_SEND_RAW_DATA with the contact path and the record',
        () async {
      await setUpRadio(outPathLen: 2, path: <int>[0xAA, 0xBB]);
      final Uint8List record = Uint8List.fromList(List<int>.filled(10, 0x5A));

      final Future<SendOutcome> out = sender.sendRecord(record, to: peer());
      await _tick();
      await _tick();
      expect(rawSends(), hasLength(1));
      expect(rawSends().single,
          <int>[0x19, 2, 0xAA, 0xBB, ...List<int>.filled(10, 0x5A)]);

      fake.emit(Uint8List.fromList(<int>[0x00])); // RESP_CODE_OK
      expect(await out, SendOutcome.sentDirect);
    });

    test('a radio refusal keeps its own code; table_full is errBusy',
        () async {
      await setUpRadio();
      final Future<SendOutcome> a = sender.sendRecord(Uint8List(8), to: peer());
      await _tick();
      await _tick();
      fake.emit(errorFrame(2));
      // The radio answered, so this is its refusal with its code, not the
      // app's own "no route" state.
      expect(await a, const SendOutcome.refused(2));
      expect((await a).kind, SendOutcomeKind.refusedByRadio);

      final Future<SendOutcome> b = sender.sendRecord(Uint8List(8), to: peer());
      await _tick();
      await _tick();
      fake.emit(errorFrame(3));
      expect(await b, SendOutcome.errBusy);
    });

    test('no answer is localTimeout and frees the slot for the next send',
        () async {
      await setUpRadio(timeout: const Duration(milliseconds: 40));
      expect(await sender.sendRecord(Uint8List(8), to: peer()),
          SendOutcome.localTimeout);

      final Future<SendOutcome> next =
          sender.sendRecord(Uint8List(8), to: peer());
      await _tick();
      await _tick();
      fake.emit(Uint8List.fromList(<int>[0x00]));
      expect(await next, SendOutcome.sentDirect);
    });

    test('sends are serialised: the second waits for the first answer',
        () async {
      await setUpRadio();
      final Future<SendOutcome> a = sender.sendRecord(Uint8List(8), to: peer());
      final Future<SendOutcome> b = sender.sendRecord(Uint8List(8), to: peer());
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
      expect(await sender.sendRecord(Uint8List(3), to: peer()),
          SendOutcome.errTooLong);
      expect(rawSends(), isEmpty);
    });

    test('a record over the path-dependent maximum is refused locally',
        () async {
      await setUpRadio(outPathLen: 14, path: List<int>.filled(14, 7));
      expect(await sender.sendRecord(Uint8List(161), to: peer()),
          SendOutcome.errTooLong);
      expect(rawSends(), isEmpty);
    });

    test('the OK for a raw send is not credited to a chat message', () async {
      await setUpRadio();
      final Future<SendOutcome> out =
          sender.sendRecord(Uint8List(8), to: peer());
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

  test('dispose is idempotent', () async {
    await setUpRadio();
    await sender.dispose();
    await sender.dispose();
  });
}
