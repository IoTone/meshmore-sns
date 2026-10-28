// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:test/test.dart';

final Uint8List peer = Uint8List.fromList(List<int>.generate(32, (int i) => i));

/// A bridge whose calls can be made to throw or to stall.
class FlakyMesh extends NoopMeshSender {
  FlakyMesh() : super(contacts: <String>{meshKeyHex(peer)});
  bool throwOnSend = false;
  bool throwOnContact = false;
  Completer<void>? gate;

  @override
  Future<bool> isContact(List<int> pubKey) async {
    if (throwOnContact) throw StateError('radio gone');
    return super.isContact(pubKey);
  }

  @override
  Future<SendOutcome> sendRecord(Uint8List record, {required int seq}) async {
    if (throwOnSend) throw StateError('radio gone');
    final Future<void>? g = gate?.future;
    if (g != null) await g;
    return super.sendRecord(record, seq: seq);
  }
}

class Rig {
  Rig(this.mesh, this.store, this.governor, this.out, this.session);
  final FlakyMesh mesh;
  final PairingStore store;
  final Governor governor;
  final List<Frame> out;
  final GatewaySession session;
  bool closed = false;
}

Future<Rig> boundSession({Governor? governor}) async {
  final FlakyMesh mesh = FlakyMesh();
  final PairingStore store = PairingStore();
  final Governor gov = governor ?? Governor();
  final List<Frame> out = <Frame>[];
  late Rig rig;
  final GatewaySession session = GatewaySession(
    pairing: store,
    mesh: mesh,
    governor: gov,
    send: out.add,
    onClosed: () => rig.closed = true,
  );
  rig = Rig(mesh, store, gov, out, session);
  session.start();
  await session.handleFrame(GatewayMessages.hello());
  await session.handleFrame(GatewayMessages.pair(store.token));
  await session.handleFrame(GatewayMessages.bind(peer));
  addTearDown(() async {
    session.dispose();
    await mesh.dispose();
  });
  return rig;
}

void main() {
  test('a session really reaches bound through a shared store', () async {
    final Rig r = await boundSession();
    expect(r.session.state, GatewaySessionState.bound);
    expect(r.out.map((Frame f) => f.type.code), <int>[
      FrameType.helloOk.code,
      FrameType.pairOk.code,
      FrameType.bindOk.code,
    ]);
  });

  test('an exhausted governor refuses a bound record and never calls the radio',
      () async {
    final Rig r = await boundSession(governor: Governor(budget: Duration.zero));
    r.out.clear();
    await r.session.handleFrame(
        GatewayMessages.record(seq: 3, opaqueRecord: List<int>.filled(20, 1)));
    final ({int seq, SendOutcome outcome})? res =
        GatewayMessages.readSendResult(r.out.single);
    expect(res!.seq, 3);
    expect(res.outcome, SendOutcome.errBusy);
    expect(r.mesh.sent, isEmpty);
  });

  test('a throwing radio yields an attributable refusal, not silence',
      () async {
    final Rig r = await boundSession();
    r.out.clear();
    r.mesh.throwOnSend = true;
    await r.session.handleFrame(
        GatewayMessages.record(seq: 5, opaqueRecord: <int>[1, 2, 3]));
    expect(GatewayMessages.readSendResult(r.out.single)!.seq, 5);
    expect(r.governor.used, Duration.zero, reason: 'nothing was transmitted');
    expect(r.session.state, GatewaySessionState.bound);
  });

  test('a throwing contact lookup closes with a frame, not silently', () async {
    final FlakyMesh mesh = FlakyMesh()..throwOnContact = true;
    addTearDown(mesh.dispose);
    final PairingStore store = PairingStore();
    final List<Frame> out = <Frame>[];
    bool closed = false;
    final GatewaySession s = GatewaySession(
      pairing: store,
      mesh: mesh,
      governor: Governor(),
      send: out.add,
      onClosed: () => closed = true,
    );
    addTearDown(s.dispose);
    s.start();
    await s.handleFrame(GatewayMessages.hello());
    await s.handleFrame(GatewayMessages.pair(store.token));
    await s.handleFrame(GatewayMessages.bind(peer));
    expect(closed, isTrue);
    expect(GatewayMessages.readClose(out.last), isNotNull);
  });

  test('airtime is charged even if the client left while the radio sent',
      () async {
    final Rig r = await boundSession();
    r.mesh.gate = Completer<void>();
    final Future<void> pending = r.session.handleFrame(
        GatewayMessages.record(seq: 1, opaqueRecord: List<int>.filled(50, 9)));
    r.session.shutdown(); // client gone mid-send
    r.mesh.gate!.complete();
    await pending;
    expect(r.mesh.sent, hasLength(1));
    expect(r.governor.used, isNot(Duration.zero),
        reason: 'an unmetered transmission is a governor bypass');
  });

  test('the pre-auth timer is cancelled by a successful PAIR', () async {
    final FlakyMesh mesh = FlakyMesh();
    addTearDown(mesh.dispose);
    final PairingStore store = PairingStore();
    bool closed = false;
    final GatewaySession s = GatewaySession(
      pairing: store,
      mesh: mesh,
      governor: Governor(),
      send: (Frame _) {},
      onClosed: () => closed = true,
      preAuthTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(s.dispose);
    s.start();
    await s.handleFrame(GatewayMessages.hello());
    await s.handleFrame(GatewayMessages.pair(store.token));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(closed, isFalse);
  });

  group('AirtimeEstimator.lora matches the LoRa formula', () {
    double ms(AirtimeEstimator e) => e.forBytes(176).inMicroseconds / 1000;
    test('USA/Canada 62.5 kHz SF7 CR5: 613 ms', () {
      expect(
          ms(const AirtimeEstimator.lora(
              bandwidthHz: 62500, spreadingFactor: 7, codingRate: 5)),
          closeTo(613, 1));
    });
    test('SF7 500 kHz: 77 ms', () {
      expect(
          ms(const AirtimeEstimator.lora(
              bandwidthHz: 500000, spreadingFactor: 7, codingRate: 5)),
          closeTo(77, 1));
    });
    test('EU/UK Narrow 62.5 kHz SF8 CR8 is far above the flat 4 ms/B default',
        () {
      final double eu = ms(const AirtimeEstimator.lora(
          bandwidthHz: 62500, spreadingFactor: 8, codingRate: 8));
      expect(eu, closeTo(1656, 1));
      expect(eu, greaterThan(const AirtimeEstimator().forBytes(176).inMilliseconds * 2));
    });
  });
}
