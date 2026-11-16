// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import '../meshcore/discovered_node.dart';

/// The node a hop hash names, or null when it names none or several.
///
/// A hop in a path is the first one, two or three bytes of the repeater's
/// public key, so it is a name only while it is unambiguous. One-byte mode has
/// 254 usable values (0x00 and 0xFF are reserved), and a real network reports
/// collisions on almost every value at a few hundred repeaters — so "the first
/// node whose key starts with these bytes" is a guess, and the three copies of
/// this loop that used to live in the node sheet and the trace screen each made
/// that guess silently. This returns null instead: a caller prints the hash,
/// which is what it actually knows.
///
/// [types] narrows the search where the caller's question is about a particular
/// kind of node: the trace screen asks a hop about repeaters and room servers
/// only, because that is all a trace passes through, while the advert-path line
/// asks about any node.
///
/// The node list is passed in, not read from a `BuildContext`, so a caller that
/// renders one path can read the list once instead of once per hop.
String? hopNodeName(
  Iterable<DiscoveredNode> nodes,
  String hashHex, {
  Set<int>? types,
}) {
  if (hashHex.isEmpty) return null;
  String? found;
  for (final DiscoveredNode n in nodes) {
    if (types != null && !types.contains(n.type)) continue;
    if (!n.pubKeyHex.startsWith(hashHex)) continue;
    // A second match means the prefix does not name anybody. Returning the
    // first one would put a name on a hop it may not belong to, and the reader
    // has no way to tell.
    if (found != null && found != n.name) return null;
    found = n.name;
  }
  return found;
}

/// The short form a hop line prints: the hash's first byte, then the name.
///
/// Kept here so the three surfaces that print a hop agree on its shape rather
/// than each choosing its own prefix, which is how the trace screen ended up
/// printing one byte where the node sheet printed two.
String hopLabel(String hashHex, String? name) {
  final String short = hashHex.length > 2 ? hashHex.substring(0, 2) : hashHex;
  return name == null || name.isEmpty ? short : '$short $name';
}
