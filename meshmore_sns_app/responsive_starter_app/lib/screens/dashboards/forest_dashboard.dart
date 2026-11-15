// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../meshcore/discovered_node.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../theme/mm_skin.dart';
import '../../ui/mm_audio_toggle.dart';
import '../../ui/mm_components.dart';
import '../../ui/mm_scaffold.dart';
import '../../ui/mm_shape.dart';
import 'dashboard_model.dart';
import 'my_pubkey_line.dart';

/// Forest — a clearing where one green is the signal and everything else is
/// bark.
///
/// The other skins answer "how many". This one answers "how deep", because a
/// mesh's shape is the thing a reader cannot get from a count: twelve peers one
/// hop away is a different network from twelve peers behind three repeaters, and
/// every other dashboard draws them identically. The depth bar is the signature
/// and the only element in the app that shows the mesh's shape rather than its
/// size.
///
/// What it must not borrow: the animated sweep (this skin's ornament is calm, so
/// a moving element would be the only motion on a still page), saturated blocks,
/// and hazard stripes, which this palette has no role for.
class ForestDashboard extends StatelessWidget {
  const ForestDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final DashboardModel m = DashboardModel.gather(mc, l);
    final Color muted = skin.color.fgMuted;

    // Peers per learned hop depth. `hopCount` is the length of the route the
    // radio stored for that peer, so 0 is a direct neighbour and n is n
    // repeaters away. A peer with no stored route is not counted here: its depth
    // is unknown, and a bar that guessed would be the one thing this layout
    // exists to avoid.
    final Map<int, int> byDepth = <int, int>{};
    for (final DiscoveredNode n in mc.nodes) {
      final int? hops = n.hopCount;
      if (hops == null) continue;
      byDepth[hops] = (byDepth[hops] ?? 0) + 1;
    }
    final int deepest = byDepth.isEmpty
        ? 0
        : byDepth.keys.reduce((int a, int b) => a > b ? a : b);

    return MmScaffold(
      child: ListView(
        padding: EdgeInsets.fromLTRB(skin.space.rowInset, skin.space.rowInset,
            skin.space.rowInset, skin.space.sectionGap),
        children: <Widget>[
          _StatusRow(m: m, skin: skin),
          SizedBox(height: skin.space.rowInset),
          MmPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MmSectionHeader(l.dashForestCanopy),
                SizedBox(height: skin.space.rowInset),
                _DepthBar(
                  byDepth: byDepth,
                  deepest: deepest,
                  skin: skin,
                  emptyLabel: l.dashForestNoRoutes,
                ),
                SizedBox(height: skin.space.rowInset),
                // Counts under the bar, never inside a segment: a number in a
                // segment is unreadable the moment the segment is one peer wide,
                // and at 200 % text it is unreadable at any width.
                Wrap(
                  spacing: skin.space.sectionGap,
                  runSpacing: skin.space.rowGap,
                  children: <Widget>[
                    MmReadout(
                      label: m.peersLabel(l),
                      value: '${m.peersInRange}',
                      emphasize: true,
                    ),
                    MmReadout(
                      label: l.dashNervKnown,
                      value: '${m.knownCount}',
                    ),
                    if (m.contactsLabel != null)
                      MmReadout(
                        label: l.dashForestContacts,
                        value: m.contactsLabel!,
                      ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: skin.space.rowInset),
          MmPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MmSectionHeader(l.dashboardRadio),
                SizedBox(height: skin.space.rowInset),
                if (m.radioFields == null)
                  Text(l.dashboardAwaitingDevice,
                      style: TextStyle(color: muted))
                else
                  MmValueFields(
                    fields: m.radioFields!,
                    separator: '  ',
                    color: skin.color.fg,
                  ),
                SizedBox(height: skin.space.rowGap),
                Text(
                  '${l.dashNervRegion}  ${m.region}',
                  style: TextStyle(
                    color: muted,
                    fontFamily: skin.type.monoFamily,
                    fontSize: skin.type.sizeBody,
                  ),
                ),
                SizedBox(height: skin.space.rowGap),
                MyPubkeyLine(
                  pubKeyHex: m.pubKeyHex,
                  style: TextStyle(
                      color: muted,
                      fontFamily: skin.type.monoFamily,
                      fontSize: skin.type.sizeMicro),
                  iconColor: muted,
                ),
              ],
            ),
          ),
          SizedBox(height: skin.space.rowInset),
          MmPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MmSectionHeader(l.dashNervEvents),
                SizedBox(height: skin.space.rowGap),
                if (m.events.isEmpty)
                  Text(l.dashboardNoActivity,
                      style: TextStyle(color: muted))
                else
                  // A table, not a fixed-width column: the time is a different
                  // width in every skin and at every text size, and a guessed
                  // 64 dp left the stamp touching the event it describes
                  // ("16:36:44battery 4.07V" on the handset). An intrinsic
                  // column plus the row gap keeps the two apart in every theme.
                  Table(
                    columnWidths: const <int, TableColumnWidth>{
                      0: IntrinsicColumnWidth(),
                      1: FlexColumnWidth(),
                    },
                    children: <TableRow>[
                      for (final ({String time, String text}) e in m.events)
                        TableRow(children: <Widget>[
                          Padding(
                            padding: EdgeInsets.only(
                                right: skin.space.rowGap,
                                bottom: skin.space.labelToControl),
                            child: Text(
                              e.time,
                              style: TextStyle(
                                color: muted,
                                fontFamily: skin.type.monoFamily,
                                fontSize: skin.type.sizeSm,
                              ),
                            ),
                          ),
                          Padding(
                            padding:
                                EdgeInsets.only(bottom: skin.space.labelToControl),
                            child: Text(
                              e.text,
                              style: TextStyle(
                                  color: skin.color.fg,
                                  fontSize: skin.type.sizeBody),
                            ),
                          ),
                        ]),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The mesh's shape: one segment per learned hop depth, its width the share of
/// peers at that depth, its colour running from the accent at the root to the
/// hairline at the deepest route.
///
/// A `Row` of `Expanded` cells rather than a painter: the flex is the count, so
/// the geometry cannot disagree with the numbers under it, and there is nothing
/// to keep in sync.
class _DepthBar extends StatelessWidget {
  const _DepthBar({
    required this.byDepth,
    required this.deepest,
    required this.skin,
    required this.emptyLabel,
  });

  final Map<int, int> byDepth;
  final int deepest;
  final MmSkin skin;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (byDepth.isEmpty) {
      // No learned route is a fact, not an empty state to apologise for: the
      // radio has not been told how to reach anyone yet.
      return Text(
        emptyLabel,
        key: const ValueKey<String>('forest-depth-empty'),
        style: TextStyle(color: skin.color.fgMuted, fontSize: skin.type.sizeBody),
      );
    }
    final Color root = skin.color.accent;
    final Color leaf = skin.color.ok;
    final Color far = skin.color.line;
    return Semantics(
      label: 'Mesh depth, ${byDepth.length} levels',
      child: SizedBox(
        key: const ValueKey<String>('forest-depth-bar'),
        height: skin.space.step(4),
        child: Row(
          children: <Widget>[
            for (int d = 0; d <= deepest; d++)
              if ((byDepth[d] ?? 0) > 0)
                Expanded(
                  flex: byDepth[d]!,
                  child: Container(
                    margin: EdgeInsets.only(right: skin.space.step(1)),
                    decoration: BoxDecoration(
                      color: _depthColor(d, deepest, root, leaf, far),
                      borderRadius: mmRadius(context, skin.space.step(1)),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// Depth 0 is the accent, the deepest is the hairline, and the middle runs
  /// through `ok`: the signal fades as the route gets longer, which is the one
  /// thing the bar is saying.
  Color _depthColor(int depth, int deepest, Color root, Color leaf, Color far) {
    if (deepest == 0) return root;
    final double t = depth / deepest;
    return t <= .5
        ? Color.lerp(root, leaf, t * 2)!
        : Color.lerp(leaf, far, (t - .5) * 2)!;
  }
}

/// The status row every skin starts with: what the link is, and the audio gate.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.m, required this.skin});

  final DashboardModel m;
  final MmSkin skin;

  @override
  Widget build(BuildContext context) {
    final Color c = m.alert ? skin.color.alert : skin.color.fgMuted;
    return Row(
      children: <Widget>[
        Container(
          width: skin.space.step(3),
          height: skin.space.step(3),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        SizedBox(width: skin.space.rowGap),
        Expanded(
          child: Text(
            m.statusLabel,
            style: TextStyle(
              color: c,
              fontSize: skin.type.sizeSm,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const MmAudioToggle(),
      ],
    );
  }
}
