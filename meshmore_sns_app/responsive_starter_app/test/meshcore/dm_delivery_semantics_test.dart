// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/airtime_meter.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/failure.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// What a send that did not go says about itself.
///
/// The channel path has always distinguished "the meter refused this, so the
/// radio never saw it" from "the write threw, so it may have reached the radio's
/// buffer". The DM path did not: it called `_markOutgoingFailed` for both, which
/// claims the message never left — the one claim the app cannot make, and the one
/// that makes a reader send it twice.
final class _Clock {
  _Clock(this.now);
  DateTime now;
}

const String _peer =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

Future<MeshcoreController> _ready(FakeMeshcoreTransport fake,
    {AirtimeMeter? meter}) async {
  final MeshcoreController c = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    airtimeMeter: meter,
  );
  await c.connect();
  fake.emit(selfInfoFrame());
  await Future<void>.delayed(Duration.zero);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a DM the airtime meter refuses says so, and names the budget', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final _Clock clock = _Clock(DateTime.utc(2026, 11, 5, 12));
    final AirtimeMeter meter = AirtimeMeter(clock: () => clock.now);
    meter.charge(const Duration(seconds: 36));
    final MeshcoreController c = await _ready(fake, meter: meter);

    final ChatMessage? m = await c.sendDirectText(_peer, 'hello');
    expect(m, isNotNull, reason: 'the row exists so the reader can see it');
    expect(m!.delivery, MessageDelivery.failed);
    expect(m.failCause, FailureCause.airtimeBudget,
        reason: 'a refusal by the app\'s own meter is not a link failure');
    expect(m.failReason, contains('airtime'));
    c.dispose();
  });

  test('a DM whose write threw is unknown, not failed', () async {
    // The write may have reached the radio's buffer before the link went, so
    // "did not send" is a claim the app cannot make.
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    // Drop the link under the send: the transport refuses the write.
    fake.setConnected(false);

    final ChatMessage? m = await c.sendDirectText(_peer, 'hello');
    expect(m, isNotNull);
    expect(m!.delivery, MessageDelivery.unknown,
        reason: 'a thrown write is unprovable, not a failure');
    expect(m.delivery, isNot(MessageDelivery.failed));
    c.dispose();
  });

  test('a channel send that threw is unknown too, and the two agree', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = await _ready(fake);
    fake.setConnected(false);

    final ChatMessage? m = await c.sendChannelTextTo(0, 'hello');
    expect(m, isNotNull);
    expect(m!.delivery, MessageDelivery.unknown);
    c.dispose();
  });
}
