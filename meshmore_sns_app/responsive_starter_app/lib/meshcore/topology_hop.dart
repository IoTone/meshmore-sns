// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'discovered_node.dart';

/// One hop on a peer's learned route, resolved as far as it can be.
///
/// A MeshCore path is a list of truncated public keys, and each hop is only as
/// wide as the mesh's negotiated hash size (one to three bytes). On a real mesh
/// most repeaters are not in the contact list, so most hops name nothing.
///
/// The previous resolver gave up on the whole route in that case: one unresolved
/// hop made the entire chain null, and a null chain meant "unknown route", so
/// every peer whose path crossed a repeater we had never heard collapsed to a
/// single ring around us. That is the bug the owner reported, and it was not a
/// drawing problem — the depth was being discarded before it reached the drawer.
///
/// A hop is therefore one of two things, and both carry the depth the radio
/// actually reported: a repeater we can name, or the bytes of one we cannot.
class TopologyHop {
  const TopologyHop({required this.hash, this.node});

  /// The hop's own bytes, lowercase hex, at the route's width. Two nodes can
  /// share a one-byte hash, which is exactly why a name is a bonus and the depth
  /// is the fact.
  final String hash;

  /// The repeater this hop resolved to, or null when nothing in the node table
  /// starts with these bytes.
  final DiscoveredNode? node;

  /// Whether this hop can be named on screen.
  bool get known => node != null;

  /// The identity to draw. A resolved hop uses the node's key so two routes
  /// through the same repeater share a vertex. An unresolved hop is keyed by its
  /// bytes, so two routes through the same unnamed repeater also share one.
  String get id => node?.pubKeyHex ?? 'unk:$hash';

  /// What to write on the vertex: the repeater's name, or its bytes.
  String get label {
    final DiscoveredNode? n = node;
    if (n == null) return hash.toUpperCase();
    return n.name.isEmpty ? n.shortId : n.name;
  }
}
