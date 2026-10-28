// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:meshmore_sns_app/meshcore/gateway/gateway_service.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fake_transport.dart';
import 'package:meshcore/meshcore.dart';

class _ThrowingPersistence implements PairingPersistence {
  int loads = 0;
  @override
  Future<Uint8List?> load() async {
    loads++;
    throw StateError('keystore unavailable');
  }

  @override
  Future<void> save(Uint8List token) async =>
      throw StateError('keystore unavailable');

  @override
  Future<void> clear() async {}
}

Future<(MeshcoreController, FakeMeshcoreTransport)> _connected() async {
  final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
  final MeshcoreController c = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await c.connect();
  fake.emit(selfInfoFrame());
  for (int i = 0; i < 50 && !c.isReady; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return (c, fake);
}

Future<void> _until(bool Function() ok) async {
  for (int i = 0; i < 100 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  late MeshcoreController mc;
  late FakeMeshcoreTransport fake;
  late GatewayService svc;

  Future<void> make({PairingPersistence? persistence, int port = 0}) async {
    (mc, fake) = await _connected();
    svc = GatewayService(
      mc,
      persistence: persistence ?? InMemoryPairingPersistence(),
      port: port,
    );
    await svc.load();
  }

  tearDown(() async {
    svc.dispose();
    mc.dispose();
  });

  test('off by default: nothing listens until the user turns it on', () async {
    await make();
    expect(svc.enabled, isFalse);
    expect(svc.status, GatewayRunState.off);
    expect(svc.pairingToken, isNull);
  });

  test('enabling with a ready radio starts the listener and issues a token',
      () async {
    await make();
    await svc.setEnabled(true);
    expect(svc.status, GatewayRunState.running);
    expect(svc.pairingToken, hasLength(GatewayLimits.pairingTokenBytes));
    expect(svc.port, greaterThan(0));

    final GatewayClient client = GatewayClient();
    addTearDown(client.close);
    await client.connect(port: svc.port);
    await client.hello();
    await client.pair(svc.pairingToken!); // the token the UI would show
  });

  test('the switch persists across a restart', () async {
    await make();
    await svc.setEnabled(true);
    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(p.getBool(GatewayService.enabledKey), isTrue);
  });

  test('losing the radio stops the listener and reports waiting', () async {
    await make();
    await svc.setEnabled(true);
    final int port = svc.port;
    expect(svc.status, GatewayRunState.running);

    fake.setConnected(false);
    await _until(() => svc.status != GatewayRunState.running);
    expect(svc.status, GatewayRunState.waitingForRadio);
    await expectLater(Socket.connect('127.0.0.1', port),
        throwsA(isA<SocketException>()),
        reason: 'nothing may keep listening without a radio');
  });

  test('revoking replaces the token and the old one stops working', () async {
    await make();
    await svc.setEnabled(true);
    final Uint8List old = svc.pairingToken!;
    await svc.revokePairing();
    final Uint8List fresh = svc.pairingToken!;
    expect(fresh, isNot(old));

    final GatewayClient client = GatewayClient();
    addTearDown(client.close);
    await client.connect(port: svc.port);
    await client.hello();
    await expectLater(client.pair(old), throwsA(isA<GatewayClientException>()));
  });

  test('a taken port is reported, not thrown, and not retried every notify',
      () async {
    final ServerSocket squatter =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(squatter.close);
    await make(port: squatter.port);
    await svc.setEnabled(true);

    expect(svc.status, GatewayRunState.failed);
    expect(svc.error, isNotNull);
    expect(svc.pairingToken, isNull);

    int notices = 0;
    svc.addListener(() => notices++);
    mc.notifyListeners(); // the controller notifies constantly
    mc.notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notices, 0, reason: 'a failed start must not be re-announced');
  });

  test('a secure-storage failure stops the gateway; no insecure fallback',
      () async {
    final _ThrowingPersistence broken = _ThrowingPersistence();
    await make(persistence: broken);
    await svc.setEnabled(true);

    expect(svc.status, GatewayRunState.failed);
    expect(svc.error, contains('keystore unavailable'));
    expect(svc.pairingToken, isNull, reason: 'no token without storage');
    expect(broken.loads, 1);
  });

  test('turning it off stops listening', () async {
    await make();
    await svc.setEnabled(true);
    final int port = svc.port;
    await svc.setEnabled(false);
    expect(svc.status, GatewayRunState.off);
    await expectLater(Socket.connect('127.0.0.1', port),
        throwsA(isA<SocketException>()));
  });

  test('dispose is idempotent', () async {
    await make();
    await svc.setEnabled(true);
    svc.dispose();
    svc.dispose();
  });
}
