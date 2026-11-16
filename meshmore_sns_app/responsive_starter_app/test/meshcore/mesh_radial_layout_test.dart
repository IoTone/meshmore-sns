// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/meshcore/mesh_graph.dart';
import 'package:meshmore_sns_app/meshcore/mesh_radial_layout.dart';

/// The tree is a statement about hops, not a diagram of forces.
///
/// A MeshCore mesh reaches a peer *through* repeaters, so the two facts worth
/// drawing are how far away it is and whose route it comes by. The layout puts
/// the radio at the centre, hop distance on the radius and the shared route in
/// the angle, and it is a pure function of the graph — so both facts can be
/// asserted here rather than eyeballed on a phone.
void main() {
  MeshGraphNode node(String id) => MeshGraphNode(
      id: id, label: id, type: id == 'self' ? 0 : 2, isSelf: id == 'self');

  /// self — a — b — peer, plus a second peer direct, plus an advert-only one.
  MeshGraph sample() => MeshGraph(
        nodes: <MeshGraphNode>[
          node('self'),
          node('a'),
          node('b'),
          node('p1'),
          node('p2'),
          node('advert'),
        ],
        edges: <MeshGraphEdge>[
          const MeshGraphEdge('self', 'a'),
          const MeshGraphEdge('a', 'b'),
          const MeshGraphEdge('b', 'p1'),
          const MeshGraphEdge('self', 'p2'),
        ],
        peers: 3,
        routed: 2,
        deepestRouted: 3,
      );

  test('the radio is at the centre and depth is the radius', () {
    final RadialLayout l = radialHopLayout(sample());
    expect(l.byId['self']!.depth, 0);
    expect(l.byId['self']!.radius, 0);
    expect(l.byId['a']!.depth, 1);
    expect(l.byId['b']!.depth, 2);
    expect(l.byId['p1']!.depth, 3);
    expect(l.byId['p2']!.depth, 1);
    expect(l.maxDepth, 3);
    // Radius rises with depth, and nothing but the centre is at zero.
    expect(l.byId['a']!.radius, lessThan(l.byId['b']!.radius));
    expect(l.byId['b']!.radius, lessThan(l.byId['p1']!.radius));
  });

  test('a peer with no route sits on the question-marked outer ring', () {
    final RadialLayout l = radialHopLayout(sample());
    expect(l.hasUnknown, isTrue);
    expect(l.unreachable, <String>['advert']);
    final RadialPlace advert = l.byId['advert']!;
    expect(advert.unknownDepth, isTrue);
    expect(advert.radius, 1.0, reason: 'the outermost ring is the unknown one');
    expect(advert.radius, greaterThan(l.byId['p1']!.radius),
        reason: 'no route is further than the deepest measured route');
    expect(l.rings, 4, reason: 'three learned hops plus the unknown ring');
  });

  test('a subtree stays inside the sector of the hop it hangs from', () {
    final RadialLayout l = radialHopLayout(sample());
    // p1 arrives by a → b, so it has to be inside a's quadrant, and b's fan
    // sits inside the same one: the two facts a reader takes from the picture.
    double sectorOf(RadialPlace p) => p.angle;
    expect(_between(sectorOf(l.byId['p1']!), sectorOf(l.byId['a']!) - 0.01,
        sectorOf(l.byId['a']!) + math.pi / 2 + 0.01), isTrue,
        reason: 'p1 hangs off the a subtree');
    expect(_between(sectorOf(l.byId['b']!), sectorOf(l.byId['a']!) - 0.01,
        sectorOf(l.byId['a']!) + math.pi / 2 + 0.01), isTrue);
    // And the two children of the radio are in different halves.
    expect((sectorOf(l.byId['a']!) - sectorOf(l.byId['p2']!)).abs(),
        greaterThan(1.0));
  });

  test('the same graph draws the same picture every time', () {
    // The force layout this replaced re-randomised the whole cloud whenever the
    // node set changed, and every node drifted while you watched it.
    final RadialLayout first = radialHopLayout(sample());
    final RadialLayout second = radialHopLayout(sample());
    for (final RadialPlace p in first.places) {
      expect(second.byId[p.id]!.angle, p.angle);
      expect(second.byId[p.id]!.radius, p.radius);
    }
  });

  test('a flood-reached peer is marked, and sits one hop out', () {
    final MeshGraph g = MeshGraph(
      nodes: <MeshGraphNode>[node('self'), node('floodPeer')],
      edges: <MeshGraphEdge>[const MeshGraphEdge('self', 'floodPeer', flood: true)],
      peers: 1,
    );
    final RadialLayout l = radialHopLayout(g);
    expect(l.byId['floodPeer']!.depth, 1);
    expect(l.byId['floodPeer']!.flood, isTrue);
    expect(l.hasUnknown, isFalse);
  });

  test('everything unreachable still draws, on one ring', () {
    final MeshGraph g = MeshGraph(
      nodes: <MeshGraphNode>[node('self'), node('x'), node('y')],
      edges: const <MeshGraphEdge>[],
      peers: 2,
    );
    final RadialLayout l = radialHopLayout(g);
    expect(l.hasUnknown, isTrue);
    expect(l.rings, 1);
    expect(l.byId['x']!.radius, 1.0);
    expect(l.byId['y']!.radius, 1.0);
    expect(l.byId['x']!.angle, isNot(l.byId['y']!.angle),
        reason: 'two nodes on one ring must not be drawn on top of each other');
  });
}

bool _between(double v, double lo, double hi) => v >= lo && v <= hi;
