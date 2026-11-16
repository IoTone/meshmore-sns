// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/mesh_graph.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';

/// The tree is rebuilt on every controller notification, and most notifications
/// change nothing the drawing depends on.
///
/// `MeshGraph.fromController` used to rebuild the whole graph each time, and the
/// build was quadratic in the contacts because the repeater prefix map was
/// rebuilt per peer. The map is cached in the controller now; this holds the
/// other half: an unchanged mesh reuses the graph, and anything the drawing
/// reads rebuilds it.
void main() {
  int pathLen({required int hops, required int hashSize}) =>
      ((hashSize - 1) << 6) | hops;

  Future<(MeshcoreController, FakeMeshcoreTransport)> ready() async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    addTearDown(ctrl.dispose);
    await ctrl.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);
    return (ctrl, fake);
  }

  test('an unchanged mesh reuses the graph', () async {
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake) = await ready();
    fake.emit(contactFrame(
      name: 'peer',
      firstPubByte: 0xD0,
      outPathLen: pathLen(hops: 1, hashSize: 2),
      path: <int>[0xB1, 0xB2],
    ));
    await Future<void>.delayed(Duration.zero);

    final MeshGraph first = MeshGraph.fromController(ctrl);
    final MeshGraph second = MeshGraph.fromController(ctrl);
    expect(identical(first, second), isTrue,
        reason: 'nothing the drawing reads changed');
  });

  test('a newer last-heard time alone does not rebuild it', () async {
    // A battery poll or a re-advert moves `lastHeardUnix` and nothing else. The
    // tree cannot show that, so rebuilding for it is work with no picture.
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake) = await ready();
    fake.emit(contactFrame(
      name: 'peer',
      firstPubByte: 0xD0,
      outPathLen: pathLen(hops: 1, hashSize: 2),
      path: <int>[0xB1, 0xB2],
    ));
    await Future<void>.delayed(Duration.zero);
    final MeshGraph first = MeshGraph.fromController(ctrl);

    fake.emit(contactFrame(
      name: 'peer',
      firstPubByte: 0xD0,
      lastAdvertTs: 1800000000,
      outPathLen: pathLen(hops: 1, hashSize: 2),
      path: <int>[0xB1, 0xB2],
    ));
    await Future<void>.delayed(Duration.zero);

    expect(identical(MeshGraph.fromController(ctrl), first), isTrue);
  });

  test('a route that changed rebuilds it', () async {
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake) = await ready();
    fake.emit(contactFrame(
      name: 'peer',
      firstPubByte: 0xD0,
      outPathLen: pathLen(hops: 1, hashSize: 2),
      path: <int>[0xB1, 0xB2],
    ));
    await Future<void>.delayed(Duration.zero);
    final MeshGraph first = MeshGraph.fromController(ctrl);
    expect(first.deepestRouted, 1);

    // Two hops now, through a different repeater.
    fake.emit(contactFrame(
      name: 'peer',
      firstPubByte: 0xD0,
      outPathLen: pathLen(hops: 2, hashSize: 2),
      path: <int>[0xC1, 0xC2, 0xC3, 0xC4],
    ));
    await Future<void>.delayed(Duration.zero);

    final MeshGraph second = MeshGraph.fromController(ctrl);
    expect(identical(first, second), isFalse);
    expect(second.deepestRouted, 2, reason: 'the new depth is drawn');
  });

  test('a renamed peer rebuilds it', () async {
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake) = await ready();
    fake.emit(contactFrame(name: 'before', firstPubByte: 0xD0));
    await Future<void>.delayed(Duration.zero);
    final MeshGraph first = MeshGraph.fromController(ctrl);

    fake.emit(contactFrame(name: 'after', firstPubByte: 0xD0));
    await Future<void>.delayed(Duration.zero);

    final MeshGraph second = MeshGraph.fromController(ctrl);
    expect(identical(first, second), isFalse);
    expect(second.nodes.any((MeshGraphNode n) => n.label == 'after'), isTrue);
  });

  test('a different hop limit is a different graph', () async {
    final (MeshcoreController ctrl, FakeMeshcoreTransport fake) = await ready();
    fake.emit(contactFrame(
      name: 'deep',
      firstPubByte: 0xD0,
      outPathLen: pathLen(hops: 3, hashSize: 2),
      path: <int>[0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6],
    ));
    await Future<void>.delayed(Duration.zero);

    final MeshGraph all = MeshGraph.fromController(ctrl);
    final MeshGraph one = MeshGraph.fromController(ctrl, maxHops: 1);
    expect(identical(all, one), isFalse);
    expect(one.hidden, greaterThan(all.hidden));
  });
}
