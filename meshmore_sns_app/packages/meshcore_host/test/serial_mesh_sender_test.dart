// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:meshcore_host/meshcore_host.dart';
import 'package:test/test.dart';

/// A link that records what was sent and lets the test answer.
class FakeLink implements CompanionLink {
  FakeLink({this.ready = true});

  final bool ready;
  final StreamController<MeshcoreInbound> inboundController =
      StreamController<MeshcoreInbound>.broadcast();
  final StreamController<MeshcoreConnectionState> statesController =
      StreamController<MeshcoreConnectionState>.broadcast();
  final List<Uint8List> sent = <Uint8List>[];
  MeshcoreConnectionState current =
      MeshcoreConnectionState.ready;

  @override
  MeshcoreConnectionState get state => current;

  @override
  Stream<MeshcoreConnectionState> get states => statesController.stream;

  @override
  Stream<MeshcoreInbound> get inbound => inboundController.stream;

  @override
  SelfInfo? get selfInfo => null;

  @override
  Future<void> sendCommand(Uint8List frame) async {
    sent.add(frame);
  }

  void push(MeshcoreInbound frame) => inboundController.add(frame);

  void setState(MeshcoreConnectionState s) {
    current = s;
    statesController.add(s);
  }

  Future<void> close() async {
    await inboundController.close();
    await statesController.close();
  }
}

const int _pubKeyLength = 32;

Uint8List _key(int fill) => Uint8List(_pubKeyLength)..fillRange(0, 32, fill);

Contact _contact({
  required Uint8List publicKey,
  required int outPathLen,
  List<int> path = const <int>[0x11],
}) {
  final Uint8List outPath = Uint8List(64);
  outPath.setRange(0, path.length, path);
  return Contact(
    publicKey: publicKey,
    type: 1,
    flags: 0,
    outPathLen: outPathLen,
    outPath: outPath,
    name: 'peer',
    lastAdvertTimestamp: 0,
    latitudeMicros: 0,
    longitudeMicros: 0,
    lastMod: 0,
  );
}

int _rawSends(FakeLink link) => link.sent
    .where((Uint8List f) => f.first == MeshcoreCommand.sendRawData.code)
    .length;

void main() {
  late FakeLink link;
  late SerialMeshSender sender;
  late Uint8List peerKey;

  setUp(() {
    link = FakeLink();
    peerKey = _key(0xAB);
    sender = SerialMeshSender(
      link: link,
      linkTimeout: const Duration(milliseconds: 100),
    )..start();
  });

  tearDown(() async {
    await sender.dispose();
    await link.close();
  });

  group('contacts', () {
    test('an empty table is synced once, then answered from cache', () async {
      final Future<bool> answer = sender.isContact(peerKey);
      await Future<void>.delayed(Duration.zero);
      expect(link.sent.single.first, MeshcoreCommand.getContacts.code);

      link
        ..push(ContactFrame(_contact(publicKey: peerKey, outPathLen: 1)))
        ..push(const EndOfContactsFrame(0));
      expect(await answer, isTrue);

      expect(await sender.isContact(peerKey), isTrue);
      expect(link.sent, hasLength(1), reason: 'second lookup is cached');
      expect(sender.contactCount, 1);
    });

    test('an unknown key stays unknown after a refresh', () async {
      final Future<bool> answer = sender.isContact(peerKey);
      await Future<void>.delayed(Duration.zero);
      link.push(const EndOfContactsFrame(0));
      expect(await answer, isFalse);
    });

    test('a contact deletion removes it from the cache', () async {
      final Future<bool> answer = sender.isContact(peerKey);
      await Future<void>.delayed(Duration.zero);
      link
        ..push(ContactFrame(_contact(publicKey: peerKey, outPathLen: 1)))
        ..push(const EndOfContactsFrame(0));
      await answer;

      link.push(ContactDeletedFrame(peerKey));
      await Future<void>.delayed(Duration.zero);
      expect(sender.contactCount, 0);
    });
  });

  group('bindPeer', () {
    test('refuses a non-contact', () async {
      final Future<BindError?> bind = sender.bindPeer(peerKey);
      await Future<void>.delayed(Duration.zero);
      link.push(const EndOfContactsFrame(0));
      expect(await bind, BindError.notAContact);
    });

    test('accepts a zero-hop path: a neighbour in range is not a missing route',
        () async {
      final Future<BindError?> bind = sender.bindPeer(peerKey);
      await Future<void>.delayed(Duration.zero);
      link
        ..push(ContactFrame(_contact(
          publicKey: peerKey,
          outPathLen: 0,
          path: const <int>[],
        )))
        ..push(const EndOfContactsFrame(0));
      expect(await bind, isNull);
      // 176 - 2 - 0 = 174, capped at the contract's 172.
      expect(sender.uplinkRecordMax, GatewayLimits.recordMax);
      expect(sender.airtimeOverheadBytes, 2,
          reason: 'header and path length byte, no path bytes');
    });

    test('refuses a contact with no direct path', () async {
      final Future<BindError?> bind = sender.bindPeer(peerKey);
      await Future<void>.delayed(Duration.zero);
      link
        ..push(ContactFrame(_contact(publicKey: peerKey, outPathLen: 0xFF)))
        ..push(const EndOfContactsFrame(0));
      expect(await bind, BindError.noPath);
    });

    test('refuses a path that leaves less than the record floor', () async {
      final Future<BindError?> bind = sender.bindPeer(peerKey);
      await Future<void>.delayed(Duration.zero);
      link
        ..push(ContactFrame(
          _contact(
            publicKey: peerKey,
            outPathLen: 20,
            path: List<int>.filled(20, 0x22),
          ),
        ))
        ..push(const EndOfContactsFrame(0));
      expect(await bind, BindError.noPath);
    });

    test('advertises the real capacity for a one-hop path', () async {
      final Future<BindError?> bind = sender.bindPeer(peerKey);
      await Future<void>.delayed(Duration.zero);
      link
        ..push(ContactFrame(_contact(publicKey: peerKey, outPathLen: 1)))
        ..push(const EndOfContactsFrame(0));
      expect(await bind, isNull);
      // 176 - 2 (opcode, path_len) - 1 (one path byte) = 173, capped at 172.
      expect(sender.uplinkRecordMax, GatewayLimits.recordMax);
      expect(sender.boundPeer, peerKey);
    });

    test('a dropped link invalidates the path, not the peer key', () async {
      final Future<BindError?> bind = sender.bindPeer(peerKey);
      await Future<void>.delayed(Duration.zero);
      link
        ..push(ContactFrame(_contact(publicKey: peerKey, outPathLen: 1)))
        ..push(const EndOfContactsFrame(0));
      await bind;

      link.setState(MeshcoreConnectionState.reconnecting);
      await Future<void>.delayed(Duration.zero);
      expect(sender.uplinkRecordMax, GatewayLimits.recordFloor);
      expect(sender.boundPeer, peerKey);
      expect(sender.radioState, RadioState.radioLost);
    });
  });

  group('sendRecord', () {
    Future<void> bind() async {
      final Future<BindError?> b = sender.bindPeer(peerKey);
      await Future<void>.delayed(Duration.zero);
      link
        ..push(ContactFrame(_contact(publicKey: peerKey, outPathLen: 1)))
        ..push(const EndOfContactsFrame(0));
      await b;
    }

    test('refuses before a bind', () async {
      expect(await sender.sendRecord(Uint8List(4), seq: 1),
          SendOutcome.errNotFound);
    });

    test('refuses a record above the advertised capacity', () async {
      await bind();
      final int before = _rawSends(link);
      expect(
        await sender.sendRecord(Uint8List(GatewayLimits.recordMax + 1), seq: 2),
        SendOutcome.errTooLong,
      );
      expect(_rawSends(link), before, reason: 'nothing was transmitted');
    });

    test('maps OK to sentDirect and carries the path', () async {
      await bind();
      final Future<SendOutcome> out =
          sender.sendRecord(Uint8List.fromList(<int>[1, 2, 3, 4]), seq: 3);
      await Future<void>.delayed(Duration.zero);
      final Uint8List frame = link.sent
          .lastWhere((Uint8List f) => f.first == MeshcoreCommand.sendRawData.code);
      expect(frame[0], MeshcoreCommand.sendRawData.code);
      expect(frame[1], 1, reason: 'one-hop path');
      expect(frame[2], 0x11);

      link.push(const OkFrame(null));
      expect(await out, SendOutcome.sentDirect);
    });

    test('maps ERR not_found to errNotFound', () async {
      await bind();
      final Future<SendOutcome> out =
          sender.sendRecord(Uint8List(4), seq: 4);
      await Future<void>.delayed(Duration.zero);
      link.push(ErrorFrame(MeshcoreErrorCode.notFound.code));
      expect(await out, SendOutcome.errNotFound);
    });

    test('maps every other ERR to errBusy', () async {
      await bind();
      final Future<SendOutcome> out =
          sender.sendRecord(Uint8List(4), seq: 5);
      await Future<void>.delayed(Duration.zero);
      link.push(ErrorFrame(MeshcoreErrorCode.tableFull.code));
      expect(await out, SendOutcome.errBusy);
    });

    test('reports a timeout when the radio never answers', () async {
      await bind();
      expect(await sender.sendRecord(Uint8List(4), seq: 6),
          SendOutcome.localTimeout);
    });

    test('serialises concurrent sends so a reply cannot be misattributed',
        () async {
      await bind();
      final int before = _rawSends(link);
      final Future<SendOutcome> a =
          sender.sendRecord(Uint8List(4), seq: 7);
      final Future<SendOutcome> b =
          sender.sendRecord(Uint8List(4), seq: 8);
      await Future<void>.delayed(Duration.zero);

      expect(_rawSends(link), before + 1,
          reason: 'the second send waits for the first reply');
      link.push(const OkFrame(null));
      expect(await a, SendOutcome.sentDirect);

      await Future<void>.delayed(Duration.zero);
      expect(_rawSends(link), before + 2);
      link.push(const OkFrame(null));
      expect(await b, SendOutcome.sentDirect);
    });
  });

  group('inbound and status', () {
    test('a raw-data push becomes an opaque record', () async {
      final Future<Uint8List> record = sender.inbound.first;
      link.push(RawDataFrame(
        snrDb: 6.25,
        rssi: -70,
        payload: Uint8List.fromList(<int>[9, 8, 7]),
      ));
      expect(await record, <int>[9, 8, 7]);
    });

    test('no bound peer reads as noContact, a bound one as connected', () async {
      expect(sender.radioState, RadioState.noContact);
      final Future<BindError?> b = sender.bindPeer(peerKey);
      await Future<void>.delayed(Duration.zero);
      link
        ..push(ContactFrame(_contact(publicKey: peerKey, outPathLen: 1)))
        ..push(const EndOfContactsFrame(0));
      await b;
      expect(sender.radioState, RadioState.connected);
    });

    test('a radio stats reply supplies the RSSI, otherwise it is unknown',
        () async {
      expect(sender.rssiDbm, GatewayLimits.unknownRssi);
      link.push(StatsFrame(
        radio: const RadioStats(
          noiseFloorDbm: -110,
          lastRssi: -71,
          lastSnrDb: 5,
          txAirSecs: 1,
          rxAirSecs: 2,
        ),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(sender.rssiDbm, -71);
    });

    test('battery stays an explicit unknown: the firmware reports millivolts',
        () async {
      expect(sender.batteryPercent, GatewayLimits.unknownBattery);
    });
  });
}
