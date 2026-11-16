// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/telemetry/coverage_session.dart';

import '../meshcore/fake_transport.dart';

class _Clock {
  DateTime now = DateTime.utc(2026, 11, 5, 12);
  DateTime call() => now;
}

/// A connected fake radio that has reported a fix at [lat]/[lon].
Future<MeshcoreController> _withFix(FakeMeshcoreTransport fake) async {
  final MeshcoreController mc = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await mc.connect();
  fake.emit(Uint8List.fromList(<int>[
    ...selfInfoFrameAt(lat: 51.5, lon: -0.12),
    ...utf8.encode('W1ABC'),
  ]));
  await Future<void>.delayed(Duration.zero);
  return mc;
}

void main() {
  late FakeMeshcoreTransport fake;
  late MeshcoreController mc;
  late _Clock clock;

  setUp(() async {
    fake = FakeMeshcoreTransport(connected: true);
    mc = await _withFix(fake);
    clock = _Clock();
  });

  tearDown(() => mc.dispose());

  CoverageSession session(CoveragePinger pinger) =>
      CoverageSession(mc: mc, pinger: pinger, clock: clock.call);

  test('an answered ping is one sample per responder and one answered ping',
      () async {
    final CoverageSession s = session(() async => <CoverageResponder>[
          const CoverageResponder(key: <int>[1, 2, 3], snr: 7),
          const CoverageResponder(key: <int>[4, 5, 6], snr: 2),
        ]);
    s.start();
    expect(await s.ping(), CoveragePingOutcome.sent);
    expect(s.samples.length, 2);
    expect(s.tried, 1);
    expect(s.answeredPings, 1);
    expect(s.edges().length, 2);
  });

  test('a ping nobody answered is one unanswered sample, and does not count '
      'as answered', () async {
    final CoverageSession s =
        session(() async => const <CoverageResponder>[]);
    s.start();
    expect(await s.ping(), CoveragePingOutcome.sent);
    expect(s.tried, 1);
    expect(s.answeredPings, 0);
    expect(s.samples.single.answered, isFalse);
    expect(s.edges(), isEmpty);
  });

  test('a second ping inside thirty seconds is refused, and nothing is sent',
      () async {
    int calls = 0;
    final CoverageSession s = session(() async {
      calls++;
      return const <CoverageResponder>[];
    });
    s.start();
    await s.ping();
    expect(await s.ping(), CoveragePingOutcome.refused);
    expect(calls, 1);
    expect(s.lastRefusal, isNotNull);
    expect(s.tried, 1);
  });

  test('the cell window refuses a second ping from the same place an hour '
      'later', () async {
    final CoverageSession s = session(() async => const <CoverageResponder>[]);
    s.start();
    await s.ping();
    clock.now = clock.now.add(const Duration(minutes: 5));
    expect(await s.ping(), CoveragePingOutcome.refused);
    clock.now = clock.now.add(const Duration(hours: 1));
    expect(await s.ping(), CoveragePingOutcome.sent);
    expect(s.tried, 2);
  });

  test('the manual override is spent once an hour and never lifts the floor',
      () async {
    final CoverageSession s = session(() async => const <CoverageResponder>[]);
    s.start();
    await s.ping();
    clock.now = clock.now.add(const Duration(minutes: 2));
    expect(await s.ping(manual: true), CoveragePingOutcome.sent);
    clock.now = clock.now.add(const Duration(minutes: 2));
    expect(await s.ping(manual: true), CoveragePingOutcome.refused);
  });

  test('a blocked responder is hidden from the drawn edges', () async {
    final CoverageSession s = session(() async => <CoverageResponder>[
          const CoverageResponder(key: <int>[0xaa, 0xbb], snr: 4),
        ]);
    s.start();
    await s.ping();
    expect(s.edges().length, 1);
    expect(s.edges(blockedKeys: <String>{'aabb'}), isEmpty);
  });

  test('no fix sends nothing', () async {
    final FakeMeshcoreTransport empty = FakeMeshcoreTransport(connected: true);
    final MeshcoreController bare = MeshcoreController(
      transportFactory: () async => empty,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await bare.connect();
    final CoverageSession s = CoverageSession(
      mc: bare,
      pinger: () async => const <CoverageResponder>[],
      clock: clock.call,
    );
    s.start();
    expect(await s.ping(), CoveragePingOutcome.noFix);
    expect(s.tried, 0);
    bare.dispose();
  });

  test('clearSamples empties the record but keeps the session running', () async {
    final CoverageSession s = session(() async => const <CoverageResponder>[]);
    s.start();
    await s.ping();
    s.clearSamples();
    expect(s.running, isTrue);
    expect(s.samples, isEmpty);
    expect(s.tried, 0);
  });
}
