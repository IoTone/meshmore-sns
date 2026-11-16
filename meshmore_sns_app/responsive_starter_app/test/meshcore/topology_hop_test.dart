// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/discovered_node.dart';
import 'package:meshmore_sns_app/meshcore/topology_hop.dart';


/// A route hop, and the depth rule the owner reported as a bug.
///
/// A MeshCore path is a list of truncated public keys, each only as wide as the
/// mesh's negotiated hash size. The previous resolver gave up on the whole route
/// when one hop named nothing, so every peer whose path crossed an unknown
/// repeater collapsed to a single ring around us. The depth is the fact; a name
/// is a bonus.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DiscoveredNode repeater(String key, {String name = ''}) => DiscoveredNode(
        pubKeyHex: key,
        name: name,
        type: kAdvTypeRepeater,
        lastHeardUnix: 0,
        viaAdvert: true,
      );

  group('TopologyHop', () {
    test('a named hop is keyed and labelled by its node', () {
      final DiscoveredNode n = repeater('ab' * 32, name: 'Ridge');
      final TopologyHop hop = TopologyHop(hash: 'ab', node: n);
      expect(hop.known, isTrue);
      expect(hop.id, n.pubKeyHex);
      expect(hop.label, 'Ridge');
    });

    test('an unnamed hop keeps its bytes, so two routes share one vertex', () {
      const TopologyHop a = TopologyHop(hash: 'ab');
      const TopologyHop b = TopologyHop(hash: 'ab');
      expect(a.known, isFalse);
      expect(a.id, 'unk:ab');
      expect(a.id, b.id);
      expect(a.label, 'AB');
    });

    test('a named node with no name falls back to its short id', () {
      final DiscoveredNode n = repeater('cd' * 32);
      final TopologyHop hop = TopologyHop(hash: 'cd', node: n);
      expect(hop.label, n.shortId);
    });
  });
}
