// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'mesh_graph.dart';

/// One node's place in the radial hop tree.
@immutable
class RadialPlace {
  const RadialPlace({
    required this.id,
    required this.depth,
    required this.angle,
    required this.radius,
    required this.flood,
    required this.unknownDepth,
  });

  final String id;

  /// Hops from the radio. 0 is the radio itself.
  final int depth;

  /// Radians, 0 pointing up and increasing clockwise.
  final double angle;

  /// Distance from the centre as a fraction of the outer ring, 0..1.
  final double radius;

  /// Reached only across a flood edge: talkable to, but with no learned route,
  /// so its position is the honest "next to me, route unknown" rather than a
  /// measured depth.
  final bool flood;

  /// Heard by advert with no route at all: drawn on the outer ring, whose ring
  /// is labelled with a question mark rather than a number.
  final bool unknownDepth;
}

/// The radial tree: the radio at the centre, **hop distance as the radius**, and
/// the route a node comes by as the angle.
///
/// The mesh this app talks to is not peer-to-peer. A MeshCore network is a set of
/// repeaters, and a peer reaches you *through* one of them: the route is a chain
/// of one-byte hashes, and two peers whose chains start with the same repeater
/// arrive by the same road. A force-directed cloud cannot show that — it spends
/// its edges making the picture not overlap, and the one thing worth reading,
/// "how many hops away and by whose route", ends up as a shapeless blob whose
/// every node is equidistant in meaning.
///
/// So the layout is deterministic and polar:
///
///   * **Radius is depth.** Ring 1 is everything learned one hop away, ring 2 two
///     hops, and the outermost ring is the peers nobody has a route for, marked
///     `?`. The picture is a statement about distance rather than a diagram of
///     forces, and the hop slider now hides *rings*, which is what it always
///     claimed to do.
///   * **Angle is the route.** Each node's children split the sector it sits in,
///     evenly, so a repeater's subtree fans out around that repeater. Peers that
///     share a road are adjacent; peers two roads apart are not.
///   * **Nothing moves between frames.** The previous layout ran a force
///     simulation on a ticker, so the same mesh drew a different picture every
///     time it was opened and every node shifted while you looked at it. This is
///     a function of the graph, so it is stable, testable and instantly
///     re-laid out when a contact arrives.
@immutable
class RadialLayout {
  const RadialLayout({
    required this.places,
    required this.byId,
    required this.maxDepth,
    required this.rings,
    required this.hasUnknown,
    required this.unreachable,
  });

  final List<RadialPlace> places;
  final Map<String, RadialPlace> byId;

  /// The deepest *learned* hop count. 0 when the radio has learned no routes.
  final int maxDepth;

  /// How many rings are drawn: the learned depths, plus one for the peers with
  /// no route when there are any.
  final int rings;

  /// Whether any peer is on the outer, question-marked ring.
  final bool hasUnknown;

  /// Peers with no route at all, in the order they are drawn.
  final List<String> unreachable;
}

/// Lay [graph] out as a radial tree, in hops.
RadialLayout radialHopLayout(MeshGraph graph) {
  const String selfId = 'self';

  // Deterministic child order: the graph's node order comes from a map, so
  // sorting by id is what keeps the same mesh drawing the same picture on every
  // rebuild.
  final Map<String, List<MeshGraphEdge>> children =
      <String, List<MeshGraphEdge>>{};
  for (final MeshGraphEdge e in graph.edges) {
    if (e.fromId == e.toId) continue;
    children.putIfAbsent(e.fromId, () => <MeshGraphEdge>[]).add(e);
  }
  for (final List<MeshGraphEdge> list in children.values) {
    list.sort((MeshGraphEdge a, MeshGraphEdge b) {
      // Flood edges hang last: they are the "no learned route" half of a node's
      // children and reading them after the routed ones matches the picture.
      if (a.flood != b.flood) return a.flood ? 1 : -1;
      return a.toId.compareTo(b.toId);
    });
  }

  // Breadth-first from the radio: the first time a node is reached is its
  // shortest learned route, which is the depth the picture should state.
  final Map<String, int> depth = <String, int>{selfId: 0};
  final Map<String, bool> floodOnly = <String, bool>{selfId: false};
  final Map<String, String?> parent = <String, String?>{selfId: null};
  final List<String> order = <String>[selfId];
  final List<String> queue = <String>[selfId];
  while (queue.isNotEmpty) {
    final String id = queue.removeAt(0);
    final int d = depth[id]!;
    for (final MeshGraphEdge e in children[id] ?? const <MeshGraphEdge>[]) {
      if (depth.containsKey(e.toId)) continue;
      depth[e.toId] = d + 1;
      parent[e.toId] = id;
      // A node reached only by a flood edge from *its* parent counts as
      // flood-reached; a routed chain is not.
      floodOnly[e.toId] =
          e.flood && (id == selfId || floodOnly[id] == true);
      order.add(e.toId);
      queue.add(e.toId);
    }
  }

  // Peers nobody has a route for. They are the honest outer ring.
  final List<String> unreachable = <String>[
    for (final MeshGraphNode n in graph.nodes)
      if (!depth.containsKey(n.id)) n.id,
  ]..sort();
  for (final String id in unreachable) {
    depth[id] = -1;
    parent[id] = null;
    order.add(id);
  }

  int maxDepth = 0;
  for (final int d in depth.values) {
    if (d > maxDepth) maxDepth = d;
  }
  final bool hasUnknown = unreachable.isNotEmpty;
  final int rings = math.max(1, maxDepth + (hasUnknown ? 1 : 0));

  // Depth-first sector split: every node hands its children equal slices of the
  // sector it owns, so a subtree never crosses a neighbouring subtree.
  final Map<String, double> angle = <String, double>{};
  // Peers with no route hang from nothing, so they are spread evenly around
  // their own ring instead of all landing at angle zero.
  for (int i = 0; i < unreachable.length; i++) {
    angle[unreachable[i]] =
        2 * math.pi * (i + 0.5) / math.max(1, unreachable.length);
  }
  void assign(String id, double from, double to) {
    angle[id] = (from + to) / 2;
    final List<String> kids = <String>[
      for (final MeshGraphEdge e in children[id] ?? const <MeshGraphEdge>[])
        if (parent[e.toId] == id) e.toId,
    ];
    if (kids.isEmpty) return;
    final double step = (to - from) / kids.length;
    for (int i = 0; i < kids.length; i++) {
      assign(kids[i], from + step * i, from + step * (i + 1));
    }
  }

  assign(selfId, 0, 2 * math.pi);

  final List<RadialPlace> places = <RadialPlace>[];
  final Map<String, RadialPlace> byId = <String, RadialPlace>{};
  for (final String id in order) {
    final int d = depth[id]!;
    final bool unknown = d < 0;
    final int shownDepth = unknown ? rings : d;
    final RadialPlace p = RadialPlace(
      id: id,
      depth: d,
      angle: angle[id] ?? 0,
      radius: rings == 0 ? 0 : shownDepth / rings,
      flood: floodOnly[id] ?? false,
      unknownDepth: unknown,
    );
    places.add(p);
    byId[id] = p;
  }

  return RadialLayout(
    places: places,
    byId: byId,
    maxDepth: maxDepth,
    rings: rings,
    hasUnknown: hasUnknown,
    unreachable: unreachable,
  );
}
