// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/discovered_node.dart';
import 'package:meshmore_sns_app/peer/hop_names.dart';

/// A hop is a public-key prefix, so it names a node only while it is unique.
///
/// Three copies of this loop used to live in the node sheet and the trace
/// screen, and every one of them returned the first match: on a real network
/// with a few hundred repeaters in one-byte mode, collisions are common, so the
/// screen printed a name for a hop it could not know. The helper returns null
/// instead, and the caller prints the hash, which is what it does know.
DiscoveredNode node({
  required String key,
  required String name,
  int type = kAdvTypeRepeater,
}) =>
    DiscoveredNode(
      pubKeyHex: key,
      name: name,
      type: type,
      lastHeardUnix: 0,
      viaAdvert: true,
    );

void main() {
  test('an empty node list names nothing', () {
    expect(hopNodeName(const <DiscoveredNode>[], 'ab'), isNull);
  });

  test('an empty hash names nothing rather than everybody', () {
    // `startsWith('')` is true for every key, so this case is the one that
    // would silently return the first node in the table.
    expect(
      hopNodeName(<DiscoveredNode>[node(key: 'abcd', name: 'One')], ''),
      isNull,
    );
  });

  test('a unique prefix names its node', () {
    final List<DiscoveredNode> nodes = <DiscoveredNode>[
      node(key: 'abcd12', name: 'Ridge'),
      node(key: '99aa', name: 'Other'),
    ];
    expect(hopNodeName(nodes, 'ab'), 'Ridge');
  });

  test('two nodes sharing a prefix name nobody', () {
    final List<DiscoveredNode> nodes = <DiscoveredNode>[
      node(key: 'abcd12', name: 'Ridge'),
      node(key: 'abffee', name: 'Ridge Two'),
    ];
    expect(hopNodeName(nodes, 'ab'), isNull,
        reason: 'a one-byte hash collides often; a name here would be a guess');
  });

  test('two entries for one node are not a collision', () {
    final List<DiscoveredNode> nodes = <DiscoveredNode>[
      node(key: 'abcd12', name: 'Ridge'),
      node(key: 'abffee', name: 'Ridge'),
    ];
    expect(hopNodeName(nodes, 'ab'), 'Ridge');
  });

  test('a prefix shorter than the stored key still matches by prefix', () {
    final List<DiscoveredNode> nodes = <DiscoveredNode>[
      node(key: '00112233', name: 'Long key'),
    ];
    expect(hopNodeName(nodes, '0011'), 'Long key');
  });

  test('the type filter asks only the kinds the caller cares about', () {
    final List<DiscoveredNode> nodes = <DiscoveredNode>[
      node(key: 'abcd', name: 'Chatty', type: kAdvTypeChat),
      node(key: 'abef', name: 'Ridge'),
    ];
    expect(hopNodeName(nodes, 'ab', types: const <int>{kAdvTypeRepeater}),
        'Ridge',
        reason: 'a trace passes through repeaters, not chat nodes');
    expect(hopNodeName(nodes, 'ab'), isNull,
        reason: 'without the filter both match, so the hash names nobody');
  });

  test('the label is the first byte and the name, and the hash alone when the '
      'hash names nobody', () {
    expect(hopLabel('abcd', 'Ridge'), 'ab Ridge');
    expect(hopLabel('abcd', null), 'ab');
    expect(hopLabel('abcd', ''), 'ab');
    expect(hopLabel('ab', null), 'ab',
        reason: 'a one-byte hash has no shorter form to print');
    expect(hopLabel('abc', null), 'ab');
  });
}
