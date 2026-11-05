// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/sos/checkin.dart';
import 'package:meshmore_sns_app/sos/sos_controller.dart';
import 'package:meshmore_sns_app/sos/sos_engine.dart';

import '../meshcore/fake_transport.dart';

/// A clock the test moves by hand, so the alarm's hour and the check-in's
/// deadline cost no wall time and the assertions cannot race a real timer.
class _Clock {
  DateTime now = DateTime.utc(2026, 11, 5, 12);
  DateTime call() => now;
}

Future<MeshcoreController> _ready(FakeMeshcoreTransport fake) async {
  final MeshcoreController mc = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await mc.connect();
  // SELF_INFO ends with the device name; the alarm cannot be raised without
  // one, so the fake radio answers with a name the way a real one does.
  final Uint8List named = Uint8List.fromList(
      <int>[...selfInfoFrame(), ...utf8.encode('W1ABC')]);
  fake.emit(named);
  await Future<void>.delayed(Duration.zero);
  return mc;
}

void main() {
  late FakeMeshcoreTransport fake;
  late MeshcoreController mc;
  late _Clock clock;
  late SosController sos;

  setUp(() async {
    fake = FakeMeshcoreTransport(connected: true);
    mc = await _ready(fake);
    clock = _Clock();
    sos = SosController(mc: mc, clock: clock.call, autoTick: false)..start();
  });

  tearDown(() {
    sos.dispose();
    mc.dispose();
  });

  /// Raises and confirms, returning once the first packet is on air.
  Future<void> raiseAndConfirm() async {
    expect(sos.arm(words: 'trail washed out'), isNull);
    clock.now = clock.now.add(SosEngine.hold);
    expect(sos.confirm(), isNull);
    await Future<void>.delayed(Duration.zero);
  }

  List<String> sentTexts() => <String>[
        for (final Uint8List f in fake.sent)
          if (f.isNotEmpty && f[0] == MeshcoreCommand.sendChannelMessage.code)
            // `[03][txtType][ch][ts u32][text]` — the text is the tail.
            utf8.decode(f.sublist(7)),
      ];

  test('the hold is not a formality: confirming before three seconds sends '
      'nothing', () async {
    expect(sos.arm(words: 'need help'), isNull);
    expect(sos.state, SosState.arming);
    clock.now = clock.now.add(const Duration(seconds: 2));
    expect(sos.confirm(), SosRefusal.holdNotComplete);
    expect(sos.state, SosState.arming);
    expect(sentTexts(), isEmpty);
    sos.abort();
    expect(sos.state, SosState.idle);
  });

  test('a confirmed alarm puts one [SOS:<id>] on the active channel', () async {
    await raiseAndConfirm();
    expect(sos.state, SosState.active);
    final List<String> sent = sentTexts();
    expect(sent, hasLength(1));
    expect(sent.single, startsWith('[SOS:'));
    expect(sent.single, contains('W1ABC'));
    expect(sent.single, hasLength(lessThanOrEqualTo(160)));
  });

  test('cancelling mid-run stops the next send', () async {
    await raiseAndConfirm();
    expect(sentTexts(), hasLength(1));

    clock.now = clock.now.add(const Duration(seconds: 61));
    sos.pump();
    await Future<void>.delayed(Duration.zero);
    expect(sentTexts(), hasLength(2), reason: 'the second send is due at 60 s');

    sos.cancel();
    expect(sos.state, SosState.cancelled);

    clock.now = clock.now.add(const Duration(minutes: 10));
    sos.pump();
    await Future<void>.delayed(Duration.zero);
    expect(sentTexts(), hasLength(2), reason: 'nothing is due after a cancel');
  });

  test('a channel ACK is claimed and the alarm keeps running', () async {
    await raiseAndConfirm();
    final String id = sos.request!.id;

    sos.attributeInbound(
      'SEEN1: [ACK:$id] W9XYZ on my way',
      direct: false,
    );
    expect(sos.state, SosState.active);
    expect(sos.acks, hasLength(1));
    expect(sos.acks.single.claimed, isTrue);
    expect(sos.acks.single.name, 'W9XYZ');

    // The schedule still owes packets: the claim stops nothing.
    clock.now = clock.now.add(const Duration(seconds: 61));
    sos.pump();
    await Future<void>.delayed(Duration.zero);
    expect(sentTexts(), hasLength(2));
  });

  test('only a direct ACK from an addressed key stops the alarm', () async {
    // The alarm is addressed to one contact, so its key is a target.
    final List<int> target = List<int>.generate(32, (int i) => i);
    final String targetHex =
        target.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
    sos.setDestination(contactKeysHex: <String>[targetHex]);
    await raiseAndConfirm();
    final String id = sos.request!.id;

    // A stranger's direct ACK is counted, not obeyed.
    final List<int> other = List<int>.generate(32, (int i) => 255 - i);
    sos.attributeInbound('[ACK:$id] W1STR', direct: true, fromKey: other);
    expect(sos.state, SosState.active);
    expect(sos.acks.single.claimed, isFalse);

    // The addressed key's ACK stops it.
    sos.attributeInbound('[ACK:$id] W1TGT', direct: true, fromKey: target);
    expect(sos.state, SosState.acknowledged);
    expect(sos.acks, hasLength(2));
    expect(sos.stoppedBy?.name, isNotNull);

    // And nothing more goes out.
    clock.now = clock.now.add(const Duration(minutes: 5));
    sos.pump();
    await Future<void>.delayed(Duration.zero);
    expect(sentTexts(), hasLength(1));
  });

  test('"I\'m safe" sends exactly one [SAFE] and stops the schedule', () async {
    await raiseAndConfirm();
    final String id = sos.request!.id;
    await sos.iAmSafe();
    expect(sos.state, SosState.cancelled);
    final List<String> sent = sentTexts();
    expect(sent, hasLength(2));
    expect(sent.last, contains('[SAFE:$id]'));

    clock.now = clock.now.add(const Duration(minutes: 10));
    sos.pump();
    await Future<void>.delayed(Duration.zero);
    expect(sentTexts(), hasLength(2), reason: 'one SAFE, then nothing');
  });

  test('a check-in is one send and expires to the overdue state', () async {
    await sos.sendCheckin(within: const Duration(minutes: 15));
    expect(sos.checkin?.state, CheckinState.watching);
    expect(sentTexts(), hasLength(1));
    expect(sentTexts().single, startsWith('[CHK:'));
    expect(sentTexts().single, contains('until '));

    clock.now = clock.now.add(const Duration(minutes: 14));
    sos.pump();
    expect(sos.checkin!.state, CheckinState.watching);

    clock.now = clock.now.add(const Duration(minutes: 1));
    sos.pump();
    expect(sos.checkin!.state, CheckinState.overdue);
    expect(sentTexts(), hasLength(1), reason: 'a check-in never repeats');
  });

  test('a [SAFE:<id>] naming the check-in answers it', () async {
    await sos.sendCheckin(within: const Duration(minutes: 30));
    final String id = sos.checkin!.checkin.id;
    sos.attributeInbound('[SAFE:$id] W1ABC', direct: true);
    expect(sos.checkin!.state, CheckinState.answered);
  });
}
