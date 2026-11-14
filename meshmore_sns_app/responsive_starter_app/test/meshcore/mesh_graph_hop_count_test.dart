// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';

import 'package:meshmore_sns_app/meshcore/discovered_node.dart';
import 'package:meshmore_sns_app/meshcore/mesh_graph.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';

import 'fake_transport.dart';

/// The tree's hop filter counts **hops**, not path bytes.
///
/// `out_path_len` packs the hop count in its low six bits and the hash width
/// minus one in its top two, so a route's byte list is `hops × width` long. The
/// controller decodes both numbers and `DiscoveredNode.hopCount` is the depth;
/// `outPathHashes.length` is the raw bytes. The graph used the bytes, so on a
/// mesh that negotiated two- or three-byte hashes every route read as two or
/// three times deeper than it is, and a stop called "≤1 hop" hid peers that were
/// one hop away.
void main() {
  /// `PathLen` packs: `(hashSize - 1) << 6 | hopCount`.
  int pathLen({required int hops, required int hashSize}) =>
      ((hashSize - 1) << 6) | hops;

  test('a one-hop route at two bytes per hop is one hop deep', () async {
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

    // One hop, two-byte hash: two bytes on the wire, one hop of depth.
    fake.emit(contactFrame(
      name: 'twoByteHop',
      firstPubByte: 0xD0,
      outPathLen: pathLen(hops: 1, hashSize: 2),
      path: <int>[0xB1, 0xB2],
    ));
    await Future<void>.delayed(Duration.zero);

    final DiscoveredNode peer = ctrl.nodes
        .firstWhere((DiscoveredNode n) => n.name == 'twoByteHop');
    expect(peer.outPathHashes, hasLength(2),
        reason: 'the raw path really is two bytes');
    expect(peer.hopCount, 1, reason: 'and it is one hop deep');

    // ≤1 includes it, ≤0 does not — the depth it is, not the bytes it took.
    final MeshGraph one = MeshGraph.fromController(ctrl, maxHops: 1);
    expect(one.nodes.any((MeshGraphNode n) => n.label == 'twoByteHop'), isTrue,
        reason: 'a one-hop peer was filtered out by a one-hop limit');
    expect(one.routed, 1);

    final MeshGraph direct = MeshGraph.fromController(ctrl, maxHops: 0);
    expect(direct.nodes.any((MeshGraphNode n) => n.label == 'twoByteHop'),
        isFalse,
        reason: 'a one-hop peer must not be counted as direct');
    expect(direct.hidden, 1);
  });

  test('a two-hop route at three bytes per hop is two hops deep', () async {
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

    fake.emit(contactFrame(
      name: 'threeByteTwoHop',
      firstPubByte: 0xD1,
      outPathLen: pathLen(hops: 2, hashSize: 3),
      path: <int>[0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6],
    ));
    await Future<void>.delayed(Duration.zero);

    final DiscoveredNode peer = ctrl.nodes
        .firstWhere((DiscoveredNode n) => n.name == 'threeByteTwoHop');
    expect(peer.outPathHashes, hasLength(6));
    expect(peer.hopCount, 2);

    expect(
        MeshGraph.fromController(ctrl, maxHops: 2)
            .nodes
            .any((MeshGraphNode n) => n.label == 'threeByteTwoHop'),
        isTrue);
    expect(
        MeshGraph.fromController(ctrl, maxHops: 1)
            .nodes
            .any((MeshGraphNode n) => n.label == 'threeByteTwoHop'),
        isFalse);
  });

  test('the deepest-route figure the slider opens on is in hops', () async {
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

    // Two hops of two bytes: the deepest route is 2, so the tree opens on the
    // ≤2 stop rather than on ≤4 (which the byte count would have chosen).
    fake.emit(contactFrame(
      name: 'deep',
      firstPubByte: 0xD2,
      outPathLen: pathLen(hops: 2, hashSize: 2),
      path: <int>[0xB1, 0xB2, 0xB3, 0xB4],
    ));
    await Future<void>.delayed(Duration.zero);

    expect(MeshGraph.fromController(ctrl).deepestRouted, 2);
  });
}
