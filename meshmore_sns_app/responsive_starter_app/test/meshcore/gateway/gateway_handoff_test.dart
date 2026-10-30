// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/gateway/gateway_handoff.dart';
import 'package:meshmore_sns_app/meshcore/gateway/gateway_service.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fake_transport.dart';

class _Recorder implements GatewayHandoffPublisher {
  final List<GatewayOffer> published = <GatewayOffer>[];
  int clears = 0;
  @override
  Future<void> publish(GatewayOffer offer) async => published.add(offer);
  @override
  Future<void> clear() async => clears++;
}

Future<void> _until(bool Function() ok) async {
  for (int i = 0; i < 100 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('GatewayOffer', () {
    test('a token is never sent for a gateway that is not running', () {
      final GatewayOffer o = GatewayOffer(
          state: 'failed', port: 9, token: Uint8List.fromList(<int>[1, 2]));
      expect(o.toArguments()['token'], isNull);
    });

    test('a running offer carries the token', () {
      final GatewayOffer o = GatewayOffer(
          state: 'running', port: 9, token: Uint8List.fromList(<int>[1, 2]));
      expect(o.toArguments()['token'], <int>[1, 2]);
    });

    test('equal offers compare equal by token content', () {
      GatewayOffer make() => GatewayOffer(
          state: 'running', port: 9, token: Uint8List.fromList(<int>[1, 2]));
      expect(make(), make());
      expect(make() == GatewayOffer(state: 'running', port: 9), isFalse);
    });
  });

  group('ChannelGatewayHandoffPublisher', () {
    test('a platform with no handoff is a no-op, not an error', () async {
      final ChannelGatewayHandoffPublisher p =
          ChannelGatewayHandoffPublisher(const MethodChannel('no.such.channel'));
      await p.publish(GatewayOffer.off);
      await p.clear();
    });

    test('publish and clear go over the channel with the offer as arguments',
        () async {
      const MethodChannel ch = MethodChannel('test/handoff');
      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ch, (MethodCall c) async {
        calls.add(c);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ch, null));
      final ChannelGatewayHandoffPublisher p = ChannelGatewayHandoffPublisher(ch);
      await p.publish(const GatewayOffer(state: 'off', port: 0));
      await p.clear();
      expect(calls.map((MethodCall c) => c.method), <String>['publish', 'clear']);
      expect((calls.first.arguments as Map<Object?, Object?>)['state'], 'off');
    });
  });

  group('GatewayService publishes what it shows', () {
    late MeshcoreController mc;
    late FakeMeshcoreTransport fake;
    late GatewayService svc;
    late _Recorder rec;

    setUp(() async {
      fake = FakeMeshcoreTransport(connected: true);
      mc = MeshcoreController(
        transportFactory: () async => fake,
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      );
      await mc.connect();
      fake.emit(selfInfoFrame());
      await _until(() => mc.isReady);
      rec = _Recorder();
      svc = GatewayService(mc,
          persistence: InMemoryPairingPersistence(), port: 0, handoff: rec);
      await svc.load();
    });

    tearDown(() {
      svc.dispose();
      mc.dispose();
    });

    test('running publishes the live port and token; stopping withdraws them',
        () async {
      await svc.setEnabled(true);
      final GatewayOffer up = rec.published.last;
      expect(up.state, 'running');
      expect(up.port, svc.port);
      expect(up.token, svc.pairingToken);

      await svc.setEnabled(false);
      final GatewayOffer down = rec.published.last;
      expect(down.state, 'off');
      expect(down.token, isNull);
      expect(down.toArguments()['token'], isNull);
    });

    test('revoking publishes the new token, not the old one', () async {
      await svc.setEnabled(true);
      final Uint8List old = svc.pairingToken!;
      await svc.revokePairing();
      final GatewayOffer o = rec.published.last;
      expect(o.token, svc.pairingToken);
      expect(o.token, isNot(old));
    });

    test('dispose clears what was offered', () async {
      await svc.setEnabled(true);
      svc.dispose();
      expect(rec.clears, greaterThan(0));
    });
  });
}
