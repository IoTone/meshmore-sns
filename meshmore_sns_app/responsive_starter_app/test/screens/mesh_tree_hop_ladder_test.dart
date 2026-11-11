// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/screens/mesh_tree_view.dart';

/// The hop slider's ladder.
///
/// "All" was the top of a 0..6 range, so the last step before everything was
/// five hops. On a MeshCore mesh those are the same picture: the peers the
/// radio has not learned a route for are the ones a depth limit cannot touch,
/// so five hops and All differ by nothing the user can see. Ten hops is the
/// real next step down, and it now has its own stop.
void main() {
  test('the ladder runs direct, one through five, ten, then All', () {
    expect(MeshTreeView.hopStops,
        <int>[0, 1, 2, 3, 4, 5, 10, MeshTreeView.allHops]);
  });

  test('every stop round-trips to itself', () {
    for (int i = 0; i < MeshTreeView.hopStops.length; i++) {
      expect(MeshTreeView.hopIndex(MeshTreeView.hopStops[i]), i,
          reason: 'stop $i is ${MeshTreeView.hopStops[i]} hops');
    }
  });

  test('All is its own stop, and nothing else selects it', () {
    final int all = MeshTreeView.hopStops.length - 1;
    expect(MeshTreeView.hopIndex(MeshTreeView.allHops), all);
    expect(MeshTreeView.hopIndex(1000), all, reason: 'anything past All');
    // Ten hops is the stop below All, not All.
    expect(MeshTreeView.hopIndex(10), all - 1);
    expect(MeshTreeView.hopIndex(5), all - 2);
  });

  test('a depth that is not a stop lands below itself, never on All', () {
    // A stored depth from another build must not read as "show everything".
    expect(MeshTreeView.hopIndex(7), MeshTreeView.hopIndex(5));
    expect(MeshTreeView.hopIndex(9), MeshTreeView.hopIndex(5));
    expect(MeshTreeView.hopIndex(11), MeshTreeView.hopIndex(10));
  });
}
