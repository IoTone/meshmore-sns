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

/// Spend the flood warm-up a fresh bind starts with, so a test can look at what comes after it.
Future<void> drainWarmup(SerialMeshSender sender, FakeLink link, Uint8List key) async {
  for (int i = 0; i < SerialMeshSender.WARMUP_SENDS; i++) {
    final Future<SendOutcome> o = sender.sendRecord(Uint8List(4), seq: i);
    await Future<void>.delayed(Duration.zero);
    link.push(const OkFrame(null));
    await o;
  }
}

int _rawSends(FakeLink link) => link.sent
    .where((Uint8List f) => f.first == MeshcoreCommand.sendRawData.code)
    .length;

/// The hop count on the last raw send: byte 1 of `41 [pathLen] [path...]`.
int _pathLen(FakeLink link) => link.sent
    .lastWhere((Uint8List f) => f.first == MeshcoreCommand.sendRawData.code)[1];

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

  group('path trust', () {
    // A chain the radio learned once is a claim about the mesh at that moment. A record sent
    // down a dead chain is answered OK by the firmware and delivered nowhere, which looked
    // exactly like "the host stopped answering" for a whole afternoon.
    late DateTime now;
    late SerialMeshSender aged;

    Future<void> bindHeard({required bool heard}) async {
      aged = SerialMeshSender(
        link: link,
        linkTimeout: const Duration(milliseconds: 100),
        clock: () => now,
      )..start();
      final Future<BindError?> b = aged.bindPeer(peerKey);
      await Future<void>.delayed(Duration.zero);
      link
        ..push(ContactFrame(_contact(publicKey: peerKey, outPathLen: 1)))
        ..push(const EndOfContactsFrame(0));
      await b;
      if (heard) {
        link.push(RawDataFrame(
          snrDb: 7,
          rssi: -60,
          payload: Uint8List.fromList(<int>[9, 9]),
        ));
        await Future<void>.delayed(Duration.zero);
      }
    }

    setUp(() => now = DateTime.utc(2026, 10, 31, 12));

    test('an unproven chain floods instead of promising a route', () async {
      await bindHeard(heard: false);
      final Future<SendOutcome> out = aged.sendRecord(Uint8List(4), seq: 1);
      await Future<void>.delayed(Duration.zero);
      expect(_pathLen(link), 0, reason: 'nothing heard on this chain yet');
      link.push(const OkFrame(null));
      expect(await out, SendOutcome.sentDirect);
    });

    test('a chain proved by a record from the peer is used, and expires', () async {
      await bindHeard(heard: true);
      await drainWarmup(aged, link, peerKey);
      link.push(RawDataFrame(
        snrDb: 7,
        rssi: -60,
        payload: Uint8List.fromList(<int>[9, 9]),
      ));
      await Future<void>.delayed(Duration.zero);
      final Future<SendOutcome> out = aged.sendRecord(Uint8List(4), seq: 2);
      await Future<void>.delayed(Duration.zero);
      expect(_pathLen(link), 1, reason: 'the peer was just heard on it');
      link.push(const OkFrame(null));
      await out;

      now = now.add(const Duration(seconds: 11));
      final Future<SendOutcome> stale = aged.sendRecord(Uint8List(4), seq: 3);
      await Future<void>.delayed(Duration.zero);
      expect(_pathLen(link), 0, reason: 'the proof has decayed');
      link.push(const OkFrame(null));
      await stale;
    });
  });

  group('path reset', () {
    // `CMD_RESET_PATH` is the documented cure for a chain that stopped delivering, and it is the
    // only cure the companion API offers: a send along a dead chain is answered OK, so the radio
    // never learns on its own.
    late DateTime now;
    late SerialMeshSender aged;

    setUp(() => now = DateTime.utc(2026, 10, 31, 12));

    Future<void> bound() async {
      aged = SerialMeshSender(
        link: link,
        linkTimeout: const Duration(milliseconds: 50),
        clock: () => now,
      )..start();
      final Future<BindError?> b = aged.bindPeer(peerKey);
      await Future<void>.delayed(Duration.zero);
      link
        ..push(ContactFrame(_contact(publicKey: peerKey, outPathLen: 1)))
        ..push(const EndOfContactsFrame(0));
      await b;
      now = now.add(const Duration(seconds: 30));
    }

    int resets() => link.sent
        .where((Uint8List f) => f.first == MeshcoreCommand.resetPath.code)
        .length;

    Future<void> sendUnanswered(int seq) async {
      final Future<SendOutcome> o = aged.sendRecord(Uint8List(4), seq: seq);
      await Future<void>.delayed(Duration.zero);
      // The radio answers; the peer does not.
      link.push(ErrorFrame(MeshcoreErrorCode.tableFull.code));
      await o;
    }

    test('a chain that stops answering is reset before the next record', () async {
      await bound();
      await drainWarmup(aged, link, peerKey);
      link.push(RawDataFrame(
        snrDb: 6,
        rssi: -70,
        payload: Uint8List.fromList(<int>[1, 2]),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(resets(), 0, reason: 'the chain just answered');

      // A path is suspect on silence *and* unanswered sends: the peer's own acknowledgements keep
      // arriving on a working chain, so ten seconds of nothing is the evidence.
      now = now.add(const Duration(seconds: 11));
      for (int i = 0; i < SerialMeshSender.SUSPECT_SENDS; i++) {
        await sendUnanswered(i);
      }
      expect(resets(), 0, reason: 'the suspicion is not raised yet');

      final Future<SendOutcome> o = aged.sendRecord(Uint8List(4), seq: 99);
      await Future<void>.delayed(Duration.zero);
      expect(resets(), 1, reason: 'three unanswered records is a dead chain');
      expect(_pathLen(link), 0, reason: 'and this record floods');
      link.push(const OkFrame(null));
      await o;
    });

    test('hearing the peer again clears the suspicion', () async {
      await bound();
      await drainWarmup(aged, link, peerKey);
      // It answered once during the warm-up, so the chain starts proven.
      link.push(RawDataFrame(
        snrDb: 6,
        rssi: -70,
        payload: Uint8List.fromList(<int>[1, 2]),
      ));
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 11));
      for (int i = 0; i < SerialMeshSender.SUSPECT_SENDS - 1; i++) {
        await sendUnanswered(i);
      }
      // A record from the peer lands between the second and third unanswered send.
      link.push(RawDataFrame(
        snrDb: 6,
        rssi: -70,
        payload: Uint8List.fromList(<int>[1, 2]),
      ));
      await Future<void>.delayed(Duration.zero);
      await sendUnanswered(50);
      expect(resets(), 0, reason: 'the chain answered, so it is not suspect');
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
      // A fresh bind floods its first window, and a path learned at bind time is a claim about
      // the mesh then, not now: the rule is to flood until the peer has been heard. Both first.
      await drainWarmup(sender, link, peerKey);
      link.push(RawDataFrame(
        snrDb: 7,
        rssi: -60,
        payload: Uint8List.fromList(<int>[9, 9]),
      ));
      await Future<void>.delayed(Duration.zero);
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
