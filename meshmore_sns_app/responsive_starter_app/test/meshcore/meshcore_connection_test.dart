// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';

import 'fake_transport.dart';

void main() {
  test('attach to a connected transport → handshaking + APP_START sent',
      () async {
    final FakeMeshcoreTransport t = FakeMeshcoreTransport(connected: true);
    final MeshcoreConnection c = MeshcoreConnection(appName: 'unit-test');
    c.attach(t);

    expect(c.state, MeshcoreConnectionState.handshaking);
    expect(t.sent, hasLength(1));
    expect(t.sent.first,
        MeshcoreFrameCodec.appStart(appName: 'unit-test'));
    await c.dispose();
  });

  test('SELF_INFO completes the handshake → ready + selfInfo set',
      () async {
    final FakeMeshcoreTransport t = FakeMeshcoreTransport(connected: true);
    final MeshcoreConnection c = MeshcoreConnection();
    final List<MeshcoreConnectionState> seen = <MeshcoreConnectionState>[];
    c.states.listen(seen.add);
    c.attach(t);

    t.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);

    expect(c.state, MeshcoreConnectionState.ready);
    expect(c.selfInfo, isNotNull);
    expect(seen, contains(MeshcoreConnectionState.ready));
    await c.dispose();
  });

  test('inbound frames are decoded and forwarded', () async {
    final FakeMeshcoreTransport t = FakeMeshcoreTransport(connected: true);
    final MeshcoreConnection c = MeshcoreConnection();
    c.attach(t);
    final Future<MeshcoreInbound> next =
        c.inbound.firstWhere((MeshcoreInbound f) => f is CurrentTimeFrame);

    t.emit(currentTimeFrame());
    final MeshcoreInbound f = await next;

    expect(f, isA<CurrentTimeFrame>());
    expect((f as CurrentTimeFrame).unixSeconds, 1700000000);
    await c.dispose();
  });

  test('link drop after ready → reconnecting', () async {
    final FakeMeshcoreTransport t = FakeMeshcoreTransport(connected: true);
    final MeshcoreConnection c = MeshcoreConnection();
    c.attach(t);
    t.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);
    expect(c.state, MeshcoreConnectionState.ready);

    t.setConnected(false);
    await Future<void>.delayed(Duration.zero);
    expect(c.state, MeshcoreConnectionState.reconnecting);
    await c.dispose();
  });

  test('no SELF_INFO before timeout → failed', () async {
    final FakeMeshcoreTransport t = FakeMeshcoreTransport(connected: true);
    final MeshcoreConnection c = MeshcoreConnection(
        handshakeTimeout: const Duration(milliseconds: 40));
    c.attach(t);
    expect(c.state, MeshcoreConnectionState.handshaking);

    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(c.state, MeshcoreConnectionState.failed);
    await c.dispose();
  });

  test('a notification that ends mid-frame is counted, not just dropped',
      () async {
    final FakeMeshcoreTransport t = FakeMeshcoreTransport(connected: true);
    final MeshcoreConnection c = MeshcoreConnection();
    c.attach(t);
    expect(c.truncatedFrames, 0);

    // SELF_INFO is 58 bytes; half of one is a frame the decoder cannot
    // finish, which is what a link below the required MTU produces.
    t.emit(Uint8List.fromList(<int>[0x05, 0x00, 0x01]));
    await Future<void>.delayed(Duration.zero);
    expect(c.truncatedFrames, 1);
    expect(c.trailingBytesFrames, 0);
    await c.dispose();
  });

  test('two frames in one notification leaves bytes over and is counted',
      () async {
    final FakeMeshcoreTransport t = FakeMeshcoreTransport(connected: true);
    final MeshcoreConnection c = MeshcoreConnection();
    c.attach(t);

    // CURRENT_TIME (0x09, 4-byte epoch) followed by a second frame in the
    // same buffer: the decoder finishes the first and reports the rest.
    final Uint8List two = Uint8List.fromList(<int>[
      0x09, 0x00, 0x00, 0x00, 0x00, //
      0x09, 0x01, 0x00, 0x00, 0x00,
    ]);
    t.emit(two);
    await Future<void>.delayed(Duration.zero);
    expect(c.trailingBytesFrames, 1);
    expect(c.truncatedFrames, 0);
    await c.dispose();
  });

  test('the transport\'s MTU is reported, and null when it has none',
      () async {
    final FakeMeshcoreTransport t = FakeMeshcoreTransport(connected: true);
    final MeshcoreConnection c = MeshcoreConnection();
    c.attach(t);
    expect(c.mtu, isNull);
    t.mtuValue = 247;
    expect(c.mtu, 247);
    await c.dispose();
  });

  test('sendCommand throws when not connected', () async {
    final FakeMeshcoreTransport t = FakeMeshcoreTransport(connected: false);
    final MeshcoreConnection c = MeshcoreConnection();
    c.attach(t);
    expect(
      () => c.sendCommand(Uint8List.fromList(<int>[0x0A])),
      throwsStateError,
    );
    await c.dispose();
  });
}
