// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'discovered_node.dart';
import 'topology_hop.dart';
import 'meshcore_controller.dart';

/// R50 — node in the topology tree. Either our own node, a known
/// repeater, or a leaf peer. Identity is the full pubkey hex (or
/// the sentinel "self" string for the root).
class MeshGraphNode {
  const MeshGraphNode({
    required this.id,
    required this.label,
    required this.type,
    this.isSelf = false,
  });

  final String id;
  final String label;

  /// Advert type byte. 0 = "self" (sentinel). 1–4 match
  /// `kAdvTypeChat / kAdvTypeRepeater / kAdvTypeRoom / kAdvTypeSensor`.
  final int type;

  final bool isSelf;

  @override
  String toString() => 'MeshGraphNode($id, $label, t=$type)';
}

/// Directed edge in the topology tree, oriented from us → repeaters
/// → leaf peer (i.e. the way our device sends to that peer).
class MeshGraphEdge {
  const MeshGraphEdge(this.fromId, this.toId, {this.flood = false});
  final String fromId;
  final String toId;

  /// True for a "reachable via flood" link (self → flood-routed
  /// contact) — drawn dashed, since there's no fixed path. Normal
  /// (solid) edges are direct / repeater-chain hops.
  final bool flood;

  String get key => '$fromId|$toId';

  @override
  String toString() =>
      'MeshGraphEdge($fromId → $toId${flood ? ' flood' : ''})';
}

/// The full mesh topology tree we can derive from the controller.
class MeshGraph {
  const MeshGraph({
    required this.nodes,
    required this.edges,
    this.peers = 0,
    this.routed = 0,
    this.deepestRouted = 0,
    this.hidden = 0,
  });

  /// No depth limit at all. Kept here rather than in the view because the
  /// filter needs to know which value means "show everything".
  static const int noLimit = 99;

  final List<MeshGraphNode> nodes;
  final List<MeshGraphEdge> edges;

  /// Peers the caller offered, not counting this device.
  final int peers;

  /// Peers shown whose *learned* route is known — the only ones a depth limit
  /// can actually talk about.
  final int routed;

  /// The deepest learned route among the peers, in hops. Zero when the radio has
  /// learned none.
  ///
  /// The tree asks this to choose the stop it opens on: a limit that just covers
  /// every learned route shows the whole routed tree at a *number* rather than
  /// opening on All, which is the state a reader is least able to reason about.
  final int deepestRouted;

  /// Peers left out because the limit could not include them.
  final int hidden;

  /// Build the graph from the controller's current node table.
  ///
  /// Sources:
  /// - Root is "self" (single pinned node).
  /// - Every `DiscoveredNode` with a resolved
  ///   `topologyChainFor(pubKey) == [r0, r1, ...]` contributes the
  ///   edge chain `self → r0 → r1 → ... → peer`.
  /// - **Flood-routed** peers (`viaFlood`, no fixed path) get a
  ///   dashed `self → peer` edge — reachable, but the route isn't
  ///   pinned. This mirrors the official app's "Flood" hop category.
  /// - Peers with `topologyChainFor == null` that are *not* flood
  ///   (advert-only-heard, unresolved chain) are added as
  ///   **disconnected** nodes — they float in the layout, which
  ///   honestly reflects "we know they exist but not where in the
  ///   tree they sit."
  /// - Peers with empty chain are direct neighbours: edge `self → peer`.
  ///
  /// Edge deduplication: many peers may share the same first hop;
  /// the same `repeater_A → repeater_B` edge only appears once.
  ///
  /// [filteredNodes] overrides which peers populate the graph (e.g.
  /// favourites-only). When null the controller's full node list is
  /// used. The path resolver still walks the controller's whole node
  /// table, so a repeater that's part of a peer's path but not in the
  /// filter still shows up as an intermediate hub.
  /// [maxHops] caps the resolved hop depth shown. A peer is included when its
  /// hop count (`DiscoveredNode.hopCount`, 0 = direct) is `<= maxHops`.
  ///
  /// **Below All, only a peer whose learned route is known is included.**
  ///
  /// This reverses the earlier rule, which kept every unknown-depth peer at
  /// every setting. That rule had one real merit: it kept the tree non-empty on
  /// a mesh where the radio has learned no routes. It had one fatal cost, which
  /// the owner reported: the ladder then filtered *nothing at all*, so All, ten,
  /// three, one and Direct drew the same picture and the control looked broken.
  ///
  /// Both rules have to guess, and they guess in opposite directions. Showing an
  /// unknown-depth peer says "this is within N hops", which nobody knows; hiding
  /// it says "this is deeper than N", which nobody knows either. The difference
  /// is which guess a given stop is making, and a control called "≤N hops" should
  /// only ever assert the thing it can check. So a stop below All means exactly
  /// "peers whose route the radio has learned, at most N deep", and All means
  /// "everything, including the peers whose depth is unknown" — which is also the
  /// default, so opening the tree never shows an empty field.
  ///
  /// [peers], [routed] and [hidden] exist so the control can say what it did
  /// instead of leaving the reader to guess: "≤3 hops · 12 routed", or
  /// "≤3 hops · no routes" when there is nothing for the limit to bite on.
  static MeshGraph fromController(
    MeshcoreController mc, {
    List<DiscoveredNode>? filteredNodes,
    int maxHops = noLimit,
  }) {
    // The tree asks for this on every controller notification, and a battery
    // poll or a contact timestamp is a notification that changes nothing the
    // drawing depends on. The signature covers exactly what the build reads, so
    // an unchanged mesh reuses the graph and any change rebuilds it.
    final String signature = _signature(mc, filteredNodes, maxHops);
    final MeshGraph? cached = _cached;
    if (cached != null && _cachedSignature == signature) return cached;
    final MeshGraph built =
        _build(mc, filteredNodes: filteredNodes, maxHops: maxHops);
    _cached = built;
    _cachedSignature = signature;
    return built;
  }

  /// One entry, because there is one tree: a per-controller cache would hold
  /// graphs for controllers that no longer exist.
  static MeshGraph? _cached;
  static String? _cachedSignature;

  /// Drop the memo. Called from `MeshcoreController.dispose`, so a controller
  /// that is gone does not leave its graph retained, and a new controller
  /// cannot match a dead one's signature through a reused `identityHashCode`.
  static void clearCache() {
    _cached = null;
    _cachedSignature = null;
  }

  /// Everything [_build] reads, and nothing else.
  ///
  /// `lastHeardUnix` is deliberately absent: it moves on every advert and every
  /// battery poll without moving a node, and including it would rebuild the tree
  /// for a change the tree cannot show. The entries are sorted by key so the
  /// controller's own "most recently heard first" ordering, which is a function
  /// of the timestamps, cannot reorder the signature.
  static String _signature(
    MeshcoreController mc,
    List<DiscoveredNode>? filteredNodes,
    int maxHops,
  ) {
    final List<String> rows = <String>[
      for (final DiscoveredNode n in mc.nodes)
        '${n.pubKeyHex}:${n.name}:${n.type}:${n.hopCount}:'
            '${n.viaFlood}:${n.outPathHashSize}:'
            '${n.outPathHashes?.join(',') ?? ''}',
    ]..sort();
    return <String>[
      '${identityHashCode(mc)}',
      '$maxHops',
      mc.selfInfo?.name ?? '',
      mc.ownPubKeyHex ?? '',
      filteredNodes == null ? '-' : '${identityHashCode(filteredNodes)}',
      ...rows,
    ].join('|');
  }

  static MeshGraph _build(
    MeshcoreController mc, {
    List<DiscoveredNode>? filteredNodes,
    int maxHops = noLimit,
  }) {
    const String selfId = 'self';
    final Map<String, MeshGraphNode> byId = <String, MeshGraphNode>{
      selfId: MeshGraphNode(
        id: selfId,
        label: mc.selfInfo?.name.isNotEmpty == true
            ? mc.selfInfo!.name
            : 'me',
        type: 0,
        isSelf: true,
      ),
    };
    final Set<String> seenEdges = <String>{};
    final List<MeshGraphEdge> edges = <MeshGraphEdge>[];

    void addEdge(String from, String to, {bool flood = false}) {
      final MeshGraphEdge e = MeshGraphEdge(from, to, flood: flood);
      if (seenEdges.add(e.key)) edges.add(e);
    }

    void addNode(DiscoveredNode n) {
      byId.putIfAbsent(
        n.pubKeyHex,
        () => MeshGraphNode(
          id: n.pubKeyHex,
          label: n.name.isEmpty ? n.shortId : n.name,
          type: n.type,
        ),
      );
    }

    final String? ownHex = mc.ownPubKeyHex;
    final List<DiscoveredNode> peers = filteredNodes ?? mc.nodes;
    final bool limited = maxHops < noLimit;
    int considered = 0;
    int routed = 0;
    int hidden = 0;
    int deepest = 0;
    for (final DiscoveredNode peer in peers) {
      if (peer.pubKeyHex == ownHex) continue; // don't double the root
      considered++;

      // The depth the radio learned, or null when it learned none.
      //
      // `hopCount`, not `outPathHashes.length`: a path is `hops × hashWidth`
      // bytes, and `out_path_len` packs the width in its top two bits. Reading
      // the byte list's length as a depth made a two-byte mesh report twice the
      // hops and a three-byte mesh three times, so the ladder's "≤2 hops" hid
      // peers that were one hop away. The controller decodes both numbers from
      // `PathLen` and `DiscoveredNode.hopCount` is the one that means depth.
      final int? hops = peer.hopCount;
      if (hops == null) {
        // No learned route: flood-routed or advert-only. Below All the limit
        // cannot be evaluated, and a stop that cannot be checked does not
        // claim the peer is inside it. At All everything is shown, which is
        // the default, so an unlearned mesh still opens with a full tree.
        if (limited) {
          hidden++;
          continue;
        }
      } else if (hops > maxHops) {
        hidden++;
        continue;
      } else {
        routed++;
        if (hops > deepest) deepest = hops;
      }

      addNode(peer);

      final List<TopologyHop>? chain = mc.topologyHopsFor(peer.pubKeyHex);
      if (chain == null) {
        if (peer.viaFlood) {
          // Reachable via flood — no fixed path, but it IS a contact
          // we can talk to. Tie it to self with a dashed edge so it
          // clusters near the root instead of floating off as if we'd
          // never reached it.
          addEdge(selfId, peer.pubKeyHex, flood: true);
        }
        // Otherwise unknown route (advert-only) — leave disconnected.
        // The layout floats it toward the rim where it can't pretend
        // to be a direct neighbour.
        continue;
      }
      String prev = selfId;
      for (final TopologyHop hop in chain) {
        // A hop we can name is the repeater itself. A hop we cannot is still a
        // vertex: the route reported that something sits there, and drawing it
        // as its own bytes is the difference between "three hops deep" and the
        // single ring the tree used to collapse to.
        byId.putIfAbsent(
          hop.id,
          () => MeshGraphNode(
            id: hop.id,
            label: hop.label,
            // Unnamed hops are drawn as repeaters, because that is the only
            // thing a hop in a route can be.
            type: hop.node?.type ?? 2,
          ),
        );
        addEdge(prev, hop.id);
        prev = hop.id;
      }
      addEdge(prev, peer.pubKeyHex);
    }

    return MeshGraph(
      nodes: byId.values.toList(growable: false),
      edges: edges,
      peers: considered,
      routed: routed,
      deepestRouted: deepest,
      hidden: hidden,
    );
  }
}
