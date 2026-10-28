// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:test/test.dart';

/// A 32-byte peer key that is also seeded as a contact.
final Uint8List peerKey = Uint8List.fromList(
  List<int>.generate(32, (int i) => i + 1),
);

typedef Harness = ({
  Gateway gateway,
  NoopMeshSender mesh,
  GatewayClient client,
});

Future<Harness> startGateway({
  Governor? governor,
  int uplinkRecordMax = 160,
  Duration preAuthTimeout = const Duration(milliseconds: 300),
  int airtimeOverheadBytes = 0,
  AirtimeEstimator estimator = const AirtimeEstimator(),
}) async {
  final NoopMeshSender mesh = NoopMeshSender(
    uplinkRecordMax: uplinkRecordMax,
    airtimeOverheadBytes: airtimeOverheadBytes,
    contacts: <String>{meshKeyHex(peerKey)},
  );
  final Gateway gateway = Gateway(
    mesh: mesh,
    governor: governor,
    estimator: estimator,
    port: 0,
    preAuthTimeout: preAuthTimeout,
  );
  await gateway.start();
  final GatewayClient client = GatewayClient();
  await client.connect(port: gateway.port);
  return (gateway: gateway, mesh: mesh, client: client);
}

Future<void> stopHarness(Harness h) async {
  await h.client.close();
  await h.gateway.stop();
  await h.mesh.dispose();
}

Future<void> handshake(Harness h, {int capabilities = 0}) async {
  await h.client.hello(capabilities: capabilities);
  await h.client.pair(h.gateway.pairingToken);
  await h.client.bind(peerKey);
}

void main() {
  group('handshake', () {
    test('hello, pair and bind reach a bound session', () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));

      final ({int capabilities, RadioState radioState}) hello =
          await h.client.hello();
      expect(hello.radioState, RadioState.connected);

      await h.client.pair(h.gateway.pairingToken);

      final ({int capabilities, int uplinkRecordMax}) bind =
          await h.client.bind(peerKey);
      expect(bind.uplinkRecordMax, 160);
    });

    test('a wrong version is refused and closed', () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));

      await expectLater(
        h.client.hello(versionOverride: 9),
        throwsA(isA<GatewayClientException>()),
      );
      await h.client.waitFor(() => h.client.closeReason != null);
      expect(h.client.closeReason, CloseReason.version);
    });

    test('a wrong token is refused and closed', () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));

      await h.client.hello();
      await expectLater(
        h.client.pair(Uint8List(16)),
        throwsA(isA<GatewayClientException>()),
      );
      await h.client.waitFor(() => h.client.closeReason != null);
      expect(h.client.closeReason, CloseReason.protocol);
    });

    test('binding a non-contact is refused and closed', () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));

      await h.client.hello();
      await h.client.pair(h.gateway.pairingToken);

      final Uint8List stranger = Uint8List.fromList(List<int>.filled(32, 7));
      await expectLater(
        h.client.bind(stranger),
        throwsA(isA<GatewayClientException>()),
      );
      await h.client.waitFor(() => h.client.closeReason != null);
      expect(h.client.closeReason, CloseReason.protocol);
    });
  });

  group('peer binding', () {
    test('BIND tells the radio bridge which peer to address', () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));

      await handshake(h);
      expect(h.mesh.boundPeer, peerKey);
    });

    test('a peer with no usable path is refused with no_path', () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));
      h.mesh.bindError = BindError.noPath;

      await h.client.hello();
      await h.client.pair(h.gateway.pairingToken);
      await expectLater(
        h.client.bind(peerKey),
        throwsA(isA<GatewayClientException>()
            .having((e) => e.message, 'message', contains('no_path'))),
      );
      expect(h.mesh.boundPeer, isNull);
    });
  });

  group('data plane', () {
    test('a record reaches the radio and the result echoes its seq', () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));

      await handshake(h);
      h.client.sendRecord(seq: 42, record: List<int>.filled(100, 0xAA));

      final ({int seq, SendOutcome outcome}) result =
          await h.client.nextSendResult();
      expect(result.seq, 42);
      expect(result.outcome, SendOutcome.sentDirect);
      expect(h.mesh.sent, hasLength(1));
      expect(h.mesh.sent.single.seq, 42);
      expect(h.mesh.sent.single.record, hasLength(100));
    });

    test('a record longer than the advertised capacity is refused', () async {
      final Harness h = await startGateway(uplinkRecordMax: 160);
      addTearDown(() => stopHarness(h));

      await handshake(h);
      h.client.sendRecord(seq: 7, record: List<int>.filled(170, 1));

      final ({int seq, SendOutcome outcome}) result =
          await h.client.nextSendResult();
      expect(result.seq, 7);
      expect(result.outcome, SendOutcome.errTooLong);
      expect(h.mesh.sent, isEmpty);
    });

    test('an exhausted governor refuses the next record', () async {
      final Harness h = await startGateway(
        governor: Governor(budget: const Duration(milliseconds: 10)),
      );
      addTearDown(() => stopHarness(h));

      await handshake(h);
      // 100 bytes at 4 ms/byte is 400 ms, far past a 10 ms budget.
      h.client.sendRecord(seq: 1, record: List<int>.filled(100, 0));
      final ({int seq, SendOutcome outcome}) result =
          await h.client.nextSendResult();
      expect(result.outcome, SendOutcome.errBusy);
      expect(h.mesh.sent, isEmpty);
    });

    test('an inbound record is forwarded as RECV', () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));

      await handshake(h);
      final Future<Uint8List> next = h.client.records.first;
      h.mesh.receive(<int>[1, 2, 3, 4]);
      expect(await next, <int>[1, 2, 3, 4]);
    });

    test('only transmitted outcomes are charged to the governor', () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));

      await handshake(h);
      h.mesh.sendOutcome = SendOutcome.errNotFound;
      h.client.sendRecord(seq: 1, record: List<int>.filled(10, 0));
      await h.client.nextSendResult();
      expect(h.gateway.governor.used, Duration.zero);

      h.mesh.sendOutcome = SendOutcome.sentDirect;
      h.client.sendRecord(seq: 2, record: List<int>.filled(10, 0));
      await h.client.nextSendResult();
      expect(h.gateway.governor.used, isNot(Duration.zero));
    });
  });

  group('lifecycle', () {
    test('a second client is told the gateway is busy', () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));
      final GatewayClient second = GatewayClient();
      addTearDown(second.close);

      await handshake(h);
      await second.connect(port: h.gateway.port);
      await second.waitFor(() => second.closeReason != null);
      expect(second.closeReason, CloseReason.busy);
    });

    test('an unauthenticated squatter is evicted, not allowed to deny the slot',
        () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));
      final GatewayClient squatter = GatewayClient();
      addTearDown(squatter.close);

      // Connected and past HELLO, but never PAIRed: holds no state.
      await squatter.connect(port: h.gateway.port);
      await squatter.hello();
      await squatter.waitFor(() => h.gateway.hasSession);
      expect(h.gateway.hasAuthenticatedSession, isFalse);

      // A second connection must get the slot rather than `busy`.
      await h.client.connect(port: h.gateway.port);
      await squatter.waitFor(() => squatter.closeReason != null);
      expect(squatter.closeReason, CloseReason.shutdown);

      await h.client.hello();
      await h.client.pair(h.gateway.pairingToken);
      final ({int capabilities, int uplinkRecordMax}) bind =
          await h.client.bind(peerKey);
      expect(bind.uplinkRecordMax, 160);
    });

    test('a paired connection is never evicted, only refused busy', () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));
      final GatewayClient second = GatewayClient();
      addTearDown(second.close);

      await handshake(h);
      expect(h.gateway.hasAuthenticatedSession, isTrue);
      await second.connect(port: h.gateway.port);
      await second.waitFor(() => second.closeReason != null);
      expect(second.closeReason, CloseReason.busy);
    });

    test('an unauthenticated connection times out', () async {
      final Harness h =
          await startGateway(preAuthTimeout: const Duration(milliseconds: 80));
      addTearDown(() => stopHarness(h));

      await h.client.hello();
      await h.client.waitFor(() => h.client.closeReason != null);
      expect(h.client.closeReason, CloseReason.preAuthTimeout);
    });

    test('an unknown frame type is ignored, not fatal', () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));

      await handshake(h);
      h.client.sendRaw(Frame(type: FrameType(0x7F), payload: <int>[1, 2, 3]));
      h.client.sendRecord(seq: 9, record: List<int>.filled(5, 0));

      final ({int seq, SendOutcome outcome}) result =
          await h.client.nextSendResult();
      expect(result.seq, 9);
    });

    test('a malformed frame closes the connection as a protocol error',
        () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));

      await h.client.hello();
      h.client.sendBytes(<int>[0, 0, 0, 0, 0, 0, 0]);
      await h.client.waitFor(() => h.client.closeReason != null);
      expect(h.client.closeReason, CloseReason.protocol);
    });

    test('reissuing the pairing token revokes the old one', () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));

      final Uint8List oldToken =
          Uint8List.fromList(h.gateway.pairingToken);
      await h.gateway.reissuePairing();
      expect(h.gateway.pairingToken, isNot(oldToken));

      // Release the single session slot, or the fresh client is told busy.
      // The server frees the slot when its read loop sees the disconnect, so
      // wait for that rather than assuming close() is synchronous on its side.
      await h.client.close();
      await h.client.waitFor(() => !h.gateway.hasSession);

      final GatewayClient fresh = GatewayClient();
      addTearDown(fresh.close);
      await fresh.connect(port: h.gateway.port);
      await fresh.hello();
      await expectLater(
        fresh.pair(oldToken),
        throwsA(isA<GatewayClientException>()),
      );
    });

    test('STATUS is pushed on a radio state change', () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));

      await handshake(h, capabilities: GatewayCapability.statusPush.mask);
      final Future<GatewayStatus> next = h.client.statuses.first;
      h.mesh.radioState = RadioState.radioLost;
      final GatewayStatus status = await next;
      expect(status.radioState, RadioState.radioLost);
    });

    test('STATUS carries opsLeft from the preset estimate and follows sends',
        () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));
      await handshake(h, capabilities: GatewayCapability.statusPush.mask);
      final List<GatewayStatus> seen = <GatewayStatus>[];
      final StreamSubscription<GatewayStatus> sub =
          h.client.statuses.listen(seen.add);
      addTearDown(sub.cancel);
      h.client.sendRecord(seq: 1, record: List<int>.filled(100, 0));
      await h.client.nextSendResult();
      await h.client.waitFor(() => seen.isNotEmpty);
      // The charge happened, so the pushed airtime is non-zero.
      expect(seen.last.txAirtimeTenthsThisHour, greaterThan(0));
      // Default estimator: 4 ms/B, advertised capacity 160 B = 640 ms/record.
      // 36 s budget, 400 ms spent => (36000-400)/640 = 55 records.
      expect(h.client.lastOpsLeft, 55);
    });

    test('STATUS is not pushed when the client did not negotiate it',
        () async {
      final Harness h = await startGateway();
      addTearDown(() => stopHarness(h));

      await handshake(h);
      bool pushed = false;
      final StreamSubscription<GatewayStatus> sub =
          h.client.statuses.listen((_) => pushed = true);
      addTearDown(sub.cancel);
      h.mesh.radioState = RadioState.radioLost;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(pushed, isFalse);
    });
  });

  group('session unit', () {
    test('a record before PAIR is ignored, and the session stays open',
        () async {
      final NoopMeshSender mesh = NoopMeshSender(
        contacts: <String>{meshKeyHex(peerKey)},
      );
      addTearDown(mesh.dispose);
      final List<Frame> out = <Frame>[];
      bool closed = false;
      final GatewaySession session = GatewaySession(
        pairing: PairingStore(),
        mesh: mesh,
        governor: Governor(),
        send: out.add,
        onClosed: () => closed = true,
      );
      addTearDown(session.dispose);
      session.start();

      await session.handleFrame(
        GatewayMessages.record(seq: 1, opaqueRecord: <int>[1, 2]),
      );
      expect(out, isEmpty);
      expect(closed, isFalse);
      expect(session.state, GatewaySessionState.disconnected);
    });
  });

  group('governor and pairing units', () {
    test('the governor meters on-air overhead, not just payload bytes',
        () async {
      // 40 payload + 100 framing = 1400 ms at 10 ms/byte, over a 500 ms
      // budget. Without the overhead the same record is 400 ms and fits.
      final Harness withOverhead = await startGateway(
        governor: Governor(budget: const Duration(milliseconds: 500)),
        airtimeOverheadBytes: 100,
        estimator: const AirtimeEstimator(millisPerByte: 10),
      );
      addTearDown(() => stopHarness(withOverhead));
      await handshake(withOverhead);
      withOverhead.client
          .sendRecord(seq: 1, record: List<int>.filled(40, 0));
      expect((await withOverhead.client.nextSendResult()).outcome,
          SendOutcome.errBusy);

      final Harness withoutOverhead = await startGateway(
        governor: Governor(budget: const Duration(milliseconds: 500)),
        airtimeOverheadBytes: 0,
        estimator: const AirtimeEstimator(millisPerByte: 10),
      );
      addTearDown(() => stopHarness(withoutOverhead));
      await handshake(withoutOverhead);
      withoutOverhead.client
          .sendRecord(seq: 1, record: List<int>.filled(40, 0));
      expect((await withoutOverhead.client.nextSendResult()).outcome,
          SendOutcome.sentDirect);
    });

    test('the governor is a rolling window', () async {
      DateTime now = DateTime(2026);
      final Governor gov = Governor(
        budget: const Duration(seconds: 10),
        window: const Duration(hours: 1),
        clock: () => now,
      );
      gov.charge(const Duration(seconds: 6));
      expect(gov.remaining, const Duration(seconds: 4));
      expect(gov.canSend(const Duration(seconds: 5)), isFalse);
      expect(gov.canSend(const Duration(seconds: 4)), isTrue);

      now = now.add(const Duration(hours: 1, seconds: 1));
      expect(gov.remaining, const Duration(seconds: 10));
    });

    test('pairing verification refuses a one-byte change', () {
      final PairingStore store = PairingStore();
      expect(store.verify(store.token), isTrue);
      final Uint8List tampered = Uint8List.fromList(store.token);
      tampered[15] ^= 0xFF;
      expect(store.verify(tampered), isFalse);
      expect(store.verify(<int>[]), isFalse);
    });

    test('the persisted token survives a reload', () async {
      final InMemoryPairingPersistence persistence =
          InMemoryPairingPersistence();
      final PairingStore first = PairingStore(persistence: persistence);
      await first.reissue();
      final Uint8List saved = Uint8List.fromList(first.token);

      final PairingStore second = PairingStore(persistence: persistence);
      await second.load();
      expect(second.token, saved);
    });
  });
}
