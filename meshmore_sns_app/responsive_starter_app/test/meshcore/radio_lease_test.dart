// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/radio_lease.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// The radio lease: another app on this phone can ask for the BLE companion,
/// and Meshmore has to be able to let go and come back without treating it as a
/// disconnect the operator asked for.
///
/// A MeshCore BLE companion takes one central at a time by firmware design, and
/// Android has no way to close another app's GATT link, so the two apps would
/// otherwise evict each other in a loop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('meshmore/radio_lease');
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    // A paired radio, because coming back after a yield is `autoConnectIfPaired`
    // doing what it says, and that needs a pair to come back to.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mm.paired.id': 'AA:BB:CC',
      'mm.paired.name': 'T1000-E',
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'isYielded') return false;
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// How many times a connection was attempted, counted where the controller
  /// asks for a transport: the fake has no counter of its own, and "did it try
  /// again" is the question that matters.
  late int attempts;

  MeshcoreController controller(FakeMeshcoreTransport fake) {
    attempts = 0;
    return MeshcoreController(
      transportFactory: () async {
        attempts++;
        return fake;
      },
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
  }

  group('the answer about who holds the radio', () {
    test('nothing read yet means not yielded', () {
      // The controller reads this synchronously so a widget test cannot
      // deadlock on a platform channel that never answers before the first
      // pump: that hang is why this getter exists instead of an await.
      expect(RadioLease.yieldedNow, isFalse);
    });

    test('a refresh caches the platform report', () async {
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        return call.method == 'isYielded' ? true : null;
      });
      expect(await RadioLease.refresh(), isTrue);
      expect(RadioLease.yieldedNow, isTrue);

      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        return call.method == 'isYielded' ? false : null;
      });
      expect(await RadioLease.refresh(), isFalse);
      expect(RadioLease.yieldedNow, isFalse);
    });

    test('a channel that throws is not yielded, not a crash', () async {
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        throw PlatformException(code: 'boom');
      });
      expect(await RadioLease.refresh(), isFalse);
    });
  });

  group('yielding the radio', () {
    test('a yield drops the link and suppresses the retry ladder', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = controller(fake);
      await mc.connect();
      fake.emit(selfInfoFrame());
      for (int i = 0; i < 50 && !mc.isReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(mc.isReady, isTrue);

      await mc.yieldRadio();
      expect(mc.yielded, isTrue);
      expect(mc.isReady, isFalse, reason: 'the link is let go');
      // No retry is scheduled: being asked to yield is not a failure, so the
      // backoff ladder must not fight the other app for the radio.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(attempts, lessThan(2),
          reason: 'no reconnect storm while another app holds the radio');
      mc.dispose();
    });

    test('a scheduled retry does nothing while yielded, a tap connects',
        () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = controller(fake);
      await mc.connect();
      await mc.yieldRadio();
      final int afterYield = attempts;

      // The ladder trying again must not steal the radio back.
      await mc.connect(isRetry: true);
      expect(attempts, afterYield);
      expect(mc.yielded, isTrue);

      // The operator asking is a decision that the radio is theirs.
      await mc.connect();
      expect(mc.yielded, isFalse);
      expect(attempts, greaterThan(afterYield));
      mc.dispose();
    });

    test('a resume takes the radio back', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = controller(fake);
      // Hydrate the pairing first: coming back from a yield is
      // `autoConnectIfPaired`, and with nothing paired it does nothing.
      await mc.autoConnectIfPaired();
      await mc.connect();
      expect(mc.hasPairedDevice, isTrue,
          reason: 'the mock preferences carry a paired radio');
      await mc.yieldRadio();
      final int afterYield = attempts;
      mc.resumeRadio();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(mc.yielded, isFalse);
      expect(attempts, greaterThan(afterYield));
      mc.dispose();
    });

    test('the platform request reaches the controller through the channel',
        () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = controller(fake);
      RadioLease.attach(mc);
      await mc.connect();
      fake.emit(selfInfoFrame());
      for (int i = 0; i < 50 && !mc.isReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(mc.isReady, isTrue);

      // What RadioLeaseReceiver sends when another app wants the radio.
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('yield')),
        (_) {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(mc.yielded, isTrue);
      expect(mc.isReady, isFalse);

      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('resume')),
        (_) {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(mc.yielded, isFalse);
      mc.dispose();
    });
  });
}
