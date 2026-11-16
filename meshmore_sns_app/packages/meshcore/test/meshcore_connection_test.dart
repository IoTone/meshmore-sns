// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:test/test.dart';

/// The owner reported this stall eight times between 2026-11-01 and
/// 2026-11-06: "it said hand shaking for like a long time. And I pressed
/// refreshed and it suddenly worked."
///
/// A handshake needs exactly one frame from the radio (SELF_INFO), and the
/// connection used to ask for it exactly once. One notification lost on the
/// way, which the phone's GATT stack does under load, therefore cost the whole
/// eight-second window and ended in `failed`; the retry ladder after that took
/// minutes. These cases pin the recovery: one repeat at half the window, one
/// terminal timeout, and no polling once ready.
class _ScriptedTransport implements MeshcoreTransport {
  _ScriptedTransport({required this.answersAfter, required this.selfInfo});

  /// How many APP_STARTs are ignored before the radio answers. 1 is the
  /// reported case: the first frame is lost.
  final int answersAfter;
  final Uint8List selfInfo;

  final List<Uint8List> sent = <Uint8List>[];
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  final StreamController<bool> _connected = StreamController<bool>.broadcast();
  bool _isConnected = true;

  @override
  int? get mtu => null;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Stream<bool> get connected => _connected.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> send(Uint8List frame) async {
    sent.add(frame);
    if (sent.length > answersAfter) _incoming.add(selfInfo);
  }

  @override
  Future<void> close() async {
    _isConnected = false;
    await _incoming.close();
    await _connected.close();
  }

  void setLinkUp(bool up) => _connected.add(up);
}

/// A 0x05 SELF_INFO: opcode plus 57 fixed bytes and an empty name.
Uint8List _selfInfo() => Uint8List(58)..[0] = 0x05;

void main() {
  group('handshake recovery', () {
    test('a lost app-start is answered on the repeat, inside the window',
        () async {
      final _ScriptedTransport t = _ScriptedTransport(
        answersAfter: 1,
        selfInfo: _selfInfo(),
      );
      final MeshcoreConnection conn = MeshcoreConnection(
        handshakeTimeout: const Duration(milliseconds: 120),
      );
      addTearDown(conn.dispose);

      conn.attach(t);
      expect(conn.state, MeshcoreConnectionState.handshaking);

      // Past the repeat (half the window), still inside it.
      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(conn.state, MeshcoreConnectionState.ready,
          reason: 'one lost notification must not cost the whole window');
      expect(t.sent.length, 2,
          reason:
              'the radio ignored the first app-start, so a second went out');
      expect(conn.handshakeAttempts, 1, reason: 'one handshake, not two');
      expect(conn.handshakeTimeouts, 0);
      expect(conn.selfInfo, isNotNull);
    });

    test('a radio that never answers fails once and counts the timeout',
        () async {
      final _ScriptedTransport t = _ScriptedTransport(
        answersAfter: 99,
        selfInfo: _selfInfo(),
      );
      final MeshcoreConnection conn = MeshcoreConnection(
        handshakeTimeout: const Duration(milliseconds: 60),
      );
      addTearDown(conn.dispose);

      conn.attach(t);
      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(conn.state, MeshcoreConnectionState.failed);
      expect(conn.handshakeTimeouts, 1);
      expect(conn.handshakeAttempts, 1);
      expect(t.sent.length, 2,
          reason: 'the repeat is one extra frame, not a poll');
    });

    test('a handshake that answers first time sends no repeat', () async {
      final _ScriptedTransport t = _ScriptedTransport(
        answersAfter: 0,
        selfInfo: _selfInfo(),
      );
      final MeshcoreConnection conn = MeshcoreConnection(
        handshakeTimeout: const Duration(milliseconds: 60),
      );
      addTearDown(conn.dispose);

      conn.attach(t);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(conn.state, MeshcoreConnectionState.ready);

      // Well past both the repeat and the window: still exactly one frame.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(t.sent.length, 1,
          reason: 'the repeat is cancelled when the answer arrives');
      expect(conn.handshakeTimeouts, 0);
    });

    test('a reconnect handshakes again and counts the second attempt',
        () async {
      final _ScriptedTransport t = _ScriptedTransport(
        answersAfter: 0,
        selfInfo: _selfInfo(),
      );
      final MeshcoreConnection conn = MeshcoreConnection(
        handshakeTimeout: const Duration(milliseconds: 60),
      );
      addTearDown(conn.dispose);

      conn.attach(t);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(conn.handshakeAttempts, 1);

      t.setLinkUp(false);
      await Future<void>.delayed(Duration.zero);
      expect(conn.state, MeshcoreConnectionState.reconnecting);

      t.setLinkUp(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(conn.state, MeshcoreConnectionState.ready);
      expect(conn.handshakeAttempts, 2,
          reason: 'each link open starts one handshake of its own');
    });
  });
}
