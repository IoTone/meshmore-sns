// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/airtime.dart';
import 'package:meshmore_sns_app/meshcore/airtime_meter.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/failure.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';

/// A clock a test moves by hand, so an hour of sending costs nothing.
final class _Clock {
  _Clock(this.now);
  DateTime now;
}

/// Builds a controller whose meter is already exhausted by [spent], so the very
/// next frame is the one the meter has to refuse.
MeshcoreController _exhausted(FakeMeshcoreTransport fake, AirtimeMeter meter) =>
    MeshcoreController(
      transportFactory: () async => fake,
      connection: MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      airtimeMeter: meter,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a frame the meter refuses never reaches the transport', () async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final _Clock clock = _Clock(DateTime.utc(2026, 11, 5, 12));
    final AirtimeMeter meter = AirtimeMeter(clock: () => clock.now);
    // Spend the whole window before the send under test.
    meter.charge(const Duration(seconds: 36));

    final MeshcoreController c = _exhausted(fake, meter);
    await c.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);

    final Duration spentBefore = meter.spent;
    final int before = fake.sent.length;
    final Uint8List probe = Uint8List.fromList(<int>[0x99, 0x01, 0x02]);
    await expectLater(
        c.send(probe, gated: true), throwsA(isA<AirtimeRefused>()));

    // The handshake's own frames may still be landing, so the assertion is
    // about this frame: it is absent, and the window did not move for it.
    expect(
        fake.sent.any((Uint8List f) =>
            f.length == probe.length && f[0] == probe[0]),
        isFalse,
        reason: 'a refused frame must not be written to the radio');
    expect(c.airtimeRefusals, 1);
    expect(meter.spent, spentBefore,
        reason: 'a refused frame is not charged');
  });

  test('a frame that fits is written and charged', () async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final _Clock clock = _Clock(DateTime.utc(2026, 11, 5, 12));
    final AirtimeMeter meter = AirtimeMeter(clock: () => clock.now);

    final MeshcoreController c = _exhausted(fake, meter);
    await c.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);

    final int before = fake.sent.length;
    await c.send(Uint8List.fromList(<int>[0x16, 0x03]), gated: true);

    expect(fake.sent.length, before + 1);
    expect(meter.spent, greaterThan(Duration.zero));
    expect(c.airtimeRefusals, 0);
  });

  test('a write that throws is refunded', () async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final AirtimeMeter meter = AirtimeMeter();
    final MeshcoreController c = _exhausted(fake, meter);
    await c.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);

    final Duration spentBefore = meter.spent;
    fake.failSend = true;
    await expectLater(
      c.send(Uint8List.fromList(<int>[0x16, 0x03])),
      throwsA(anything),
    );
    expect(meter.spent, spentBefore,
        reason: 'a frame that never left the phone costs nothing');
  });

  test('a refused channel send is recorded as a budget refusal', () async {
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final _Clock clock = _Clock(DateTime.utc(2026, 11, 5, 12));
    final AirtimeMeter meter = AirtimeMeter(clock: () => clock.now);
    meter.charge(const Duration(seconds: 36));

    final MeshcoreController c = _exhausted(fake, meter);
    await c.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);

    final ChatMessage? m = await c.sendChannelTextTo(0, 'hello');

    expect(m, isNotNull);
    expect(m!.delivery, MessageDelivery.failed);
    expect(m.failCause, FailureCause.airtimeBudget,
        reason: 'the row says why, and it is not a link failure');
  });

  test('the policy is persisted and the meter keeps its history', () async {
    final AirtimeMeter meter = AirtimeMeter();
    final MeshcoreController c = _exhausted(
        FakeMeshcoreTransport(connected: true), meter);
    meter.charge(const Duration(seconds: 5));

    await c.setAirtimePolicy(AirtimePolicy.ownedChannel);

    expect(c.airtimePolicy, AirtimePolicy.ownedChannel);
    expect(c.airtimeBudget, isNull);
    expect(meter.spent, const Duration(seconds: 5));
    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(p.getString('mm.airtime.policy'), 'ownedChannel');
  });
}
