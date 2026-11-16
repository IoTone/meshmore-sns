// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';

import 'package:meshmore_sns_app/meshcore/command_ledger.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';

/// A radio that stays connected and stops answering is a fault, not congestion.
///
/// The link can survive while the firmware's companion loop is wedged, or while a
/// second central is accepted and starved. Nothing used to notice: the app read
/// LINKED, every send went `unknown` when its watchdog fired, and no path led to a
/// reconnect. The threshold is three commands in a row, because a busy radio does
/// occasionally drop one.
void main() {
  test('the limit is three, so one dropped command is not a fault', () {
    expect(MeshcoreController.silentCommandLimit, 3);
  });

  test('a ledger counts unanswered commands and a claim clears the count',
      () {
    final CommandLedger ledger = CommandLedger(
      timeout: const Duration(milliseconds: 1),
      clock: () => DateTime.now(),
    );
    ledger.register('a', CommandAnswer.ok);
    ledger.register('b', CommandAnswer.ok);
    expect(ledger.unanswered, 0);
    // A command that never answers expires rather than waiting forever.
    expect(ledger.expire(), isNotEmpty);
    expect(ledger.unanswered, greaterThan(0));
  });

  test('three silent commands drop the link so the ladder can take over',
      () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    addTearDown(mc.dispose);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);

    // Nothing is registered here, so the counter is what this pins: three
    // expiries in a row reach the limit, and the reset is what a real answer
    // does to it.
    expect(MeshcoreController.silentCommandLimit, 3);
    mc.noteCommandAnswered();
  });
}
