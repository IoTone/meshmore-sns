// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/discovered_node.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';
import 'package:meshcore/meshcore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a contact sync must not wipe a position learned from an advert',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeMeshcoreTransport fake =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await ctrl.connect();

    // 1) An advert carrying a position creates the node with a real fix.
    fake.emit(advertFrameAt(
      lat: 38.920045,
      lon: -104.772826,
      name: 'PeerAt',
      firstPubByte: 0x10,
    ));
    await Future<void>.delayed(Duration.zero);

    final DiscoveredNode adv = ctrl.nodes.single;
    expect(adv.latitude, closeTo(38.920045, 1e-5));
    expect(adv.longitude, closeTo(-104.772826, 1e-5));

    // 2) A contact sync for the same key. MeshCore's contact record
    //    carries no RSSI/SNR/altitude and reports (0,0) for a node that
    //    hides its position, so it has nothing to say about any of them.
    //    Before the fix this rebuilt the node with nulls and threw the
    //    advert's fix away — which also fed the radar's RSSI-ring
    //    placement and the per-peer reach estimate wrong data.
    fake.emit(contactFrame(name: 'PeerAt', firstPubByte: 0x10));
    await Future<void>.delayed(Duration.zero);

    final DiscoveredNode synced = ctrl.nodes.single;
    expect(synced.pubKeyHex, adv.pubKeyHex);
    expect(synced.latitude, closeTo(38.920045, 1e-5),
        reason: 'the sync has no position of its own; it must not clear one');
    expect(synced.longitude, closeTo(-104.772826, 1e-5),
        reason: 'the sync has no position of its own; it must not clear one');
    ctrl.dispose();
  });
}