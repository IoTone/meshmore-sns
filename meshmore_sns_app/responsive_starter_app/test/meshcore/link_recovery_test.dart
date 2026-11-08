// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/failure.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/reconnect_policy.dart';

import 'fake_transport.dart';

/// The owner's report, as a defect: the app sat on "handshaking" for minutes
/// and recovered only when he pressed refresh.
///
/// Two mechanisms made that possible and neither is about the radio being
/// busy: a transport teardown the app waited on with no limit, which held
/// `_connecting` set so nothing could retry; and a retry ladder whose floor
/// applied even to a handshake the radio never answered. The handshake's own
/// recovery (one repeat of APP_START) is pinned in the codec package, where
/// the state machine lives.

/// A transport whose `close()` never completes, standing in for a phone whose
/// GATT stack has stopped answering.
class _HungCloseTransport extends FakeMeshcoreTransport {
  _HungCloseTransport() : super(connected: true);

  @override
  Future<void> close() => Completer<void>().future;
}

Future<void> _pump([int n = 10]) async {
  for (int i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a teardown that never finishes does not stop the next connect',
      () async {
    // The reported sequence: the link was up, the user moved through the app,
    // and the next connect found the old transport's close hanging. Before the
    // wait was bounded, `_connecting` stayed set and the screen kept reading
    // "handshaking" with nothing behind it.
    final _HungCloseTransport first = _HungCloseTransport();
    final FakeMeshcoreTransport second = FakeMeshcoreTransport(connected: true);
    int calls = 0;
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async {
        calls++;
        return calls == 1 ? first : second;
      },
      linkCloseTimeout: const Duration(milliseconds: 30),
      connection: MeshcoreConnection(
          handshakeTimeout: const Duration(milliseconds: 300)),
    );
    addTearDown(ctrl.dispose);

    await ctrl.connect();
    first.emit(selfInfoFrame());
    await _pump();
    expect(ctrl.isReady, isTrue, reason: 'the first link came up');

    // The retry whose teardown hangs.
    await ctrl.connect();
    second.emit(selfInfoFrame());
    await _pump();

    expect(ctrl.linkCloseTimeouts, 1,
        reason: 'the teardown was abandoned, not waited on forever');
    expect(calls, 2, reason: 'the second transport was still acquired');
    expect(ctrl.isReady, isTrue,
        reason: 'the hung close was abandoned and a new link opened');
  });

  test('a factory that never resolves fails as a named link timeout', () async {
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () => Completer<MeshcoreTransport>().future,
      linkOpenTimeout: const Duration(milliseconds: 30),
      reconnectPolicy: ReconnectPolicy(maxAttempts: 1),
      reconnectDelay: (Duration d) async {},
    );
    addTearDown(ctrl.dispose);

    await ctrl.connect();

    expect(ctrl.state, MeshcoreConnectionState.failed);
    expect(ctrl.failure?.cause, FailureCause.linkTimeout,
        reason: 'a platform call that never returns is not a radio refusal');
    expect(ctrl.failure, isA<Failure>());
  });

  test(
      'the first retry after a handshake timeout waits for nothing, the '
      'second waits out the ladder', () async {
    final List<Duration> delays = <Duration>[];
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      connection: MeshcoreConnection(
          handshakeTimeout: const Duration(milliseconds: 40)),
      // The production ladder: 6 s floor, full jitter, two attempts.
      reconnectPolicy: ReconnectPolicy(
        floor: const Duration(seconds: 6),
        random: () => 0.0,
        maxAttempts: 2,
      ),
      reconnectDelay: (Duration d) async => delays.add(d),
    );
    addTearDown(ctrl.dispose);

    await ctrl.connect();
    for (int i = 0; i < 200 && !ctrl.gaveUp; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(delays, isNotEmpty, reason: 'the ladder ran at all');
    expect(delays.first, Duration.zero,
        reason: 'a handshake nobody answered is not a busy mesh');
    expect(delays.skip(1),
        everyElement(greaterThanOrEqualTo(const Duration(seconds: 6))),
        reason: 'the scan-throttle floor still bounds a radio that is gone');
    expect(ctrl.gaveUp, isTrue, reason: 'bounded by maxAttempts');
    expect(ctrl.handshakeTimeouts, greaterThan(1),
        reason: 'the radio never answered, twice');
  });
}
