// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/meshcore_connection.dart';
import '../meshcore/meshcore_controller.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';
import '../util/geo.dart' as geo;
import 'node_detail_sheet.dart';
import '../ui/mm_shape.dart';

/// Nodes "in the area" — the hyperlocal-discovery view (R6/R8).
///
/// Discovery in MeshCore is **advert-driven**: a node appears here only
/// when this radio *hears that node's advert* (then auto-added as a
/// contact, pushed via `PUSH_CODE_ADVERTISEMENT`, or drained from the
/// queue). Channel/Public traffic does NOT create a node — you can
/// chat on Public with a peer that never shows up here. So discovery
/// is bilateral: **Advertise** makes this node findable by others;
/// **Scan area** broadcasts our advert *and* collects the adverts we
/// have heard.
class NodesScreen extends StatefulWidget {
  const NodesScreen({super.key});

  @override
  State<NodesScreen> createState() => _NodesScreenState();
}

class _NodesScreenState extends State<NodesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  bool _starredOnly = false;
  bool _inRangeOnly = false;
  // Tags the node must ALL carry to pass (AND). Empty = no tag filter.
  final Set<String> _selectedTags = <String>{};
  // null = any; otherwise hide nodes whose lastHeard is older than this.
  Duration? _maxAge;
  // null = any; otherwise hide GPS-positioned nodes farther than this
  // (in metres). Nodes without distance pass through regardless.
  double? _maxDistanceMeters;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _ago(int unix) {
    if (unix <= 0) return '—';
    final int s = DateTime.now().millisecondsSinceEpoch ~/ 1000 - unix;
    if (s < 0) return 'now';
    if (s < 60) return '${s}s';
    if (s < 3600) return '${s ~/ 60}m';
    if (s < 86400) return '${s ~/ 3600}h';
    return '${s ~/ 86400}d';
  }

  bool _passesFilters(
      DiscoveredNode n, MeshcoreController mc, Set<String> favs) {
    final List<String> tags = mc.tagsFor(n.pubKeyHex);
    if (_query.isNotEmpty) {
      final String q = _query.toLowerCase();
      final bool nameHit = n.name.toLowerCase().contains(q);
      final bool idHit = n.shortId.toLowerCase().contains(q);
      final bool pkHit = n.pubKeyHex.toLowerCase().contains(q);
      final bool tagHit =
          tags.any((String t) => t.toLowerCase().contains(q));
      if (!nameHit && !idHit && !pkHit && !tagHit) return false;
    }
    if (_selectedTags.isNotEmpty) {
      final Set<String> lower =
          tags.map((String t) => t.toLowerCase()).toSet();
      for (final String want in _selectedTags) {
        if (!lower.contains(want.toLowerCase())) return false;
      }
    }
    if (_starredOnly && !favs.contains(n.pubKeyHex)) return false;
    if (_inRangeOnly) {
      // "In-range only" now means spatially near OR (when GPS is
      // unknown) recently heard. FAR / MID / unknown are hidden so a
      // user a thousand km from a repeater they once heard a few
      // minutes ago doesn't see it after toggling the filter on.
      final NodeProximity p = mc.proximityFor(n);
      if (p != NodeProximity.near && p != NodeProximity.recent) {
        return false;
      }
    }
    if (_maxAge != null) {
      final int s =
          DateTime.now().millisecondsSinceEpoch ~/ 1000 - n.lastHeardUnix;
      if (s > _maxAge!.inSeconds) return false;
    }
    if (_maxDistanceMeters != null && n.hasLocation) {
      final double? d = mc.distanceMetersTo(n.latitude!, n.longitude!);
      if (d != null && d > _maxDistanceMeters!) return false;
    }
    return true;
  }

  /// How many filters are on, for the badge on the Filters button.
  int get _activeFilterCount =>
      (_starredOnly ? 1 : 0) +
      (_inRangeOnly ? 1 : 0) +
      _selectedTags.length +
      (_maxAge != null ? 1 : 0) +
      (_maxDistanceMeters != null ? 1 : 0);

  bool get _anyFilterActive =>
      _query.isNotEmpty ||
      _starredOnly ||
      _inRangeOnly ||
      _selectedTags.isNotEmpty ||
      _maxAge != null ||
      _maxDistanceMeters != null;

  /// Every list filter in one sheet: starred, in range, last seen, within a
  /// distance, and the tags in use (AND). Changes apply live; the sheet
  /// stays open so several can be set in one go.
  Future<void> _openFilters(MeshcoreController mc, AppLocalizations l) async {
    final ColorScheme cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext _) => StatefulBuilder(
        builder: (BuildContext _, void Function(void Function()) setSheet) {
          void both(VoidCallback f) {
            setSheet(f);
            setState(f);
          }

          Widget label(String t) => Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: Text(t,
                    style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600)),
              );

          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilterChip(
                        label: Text(l.nodesFilterStarred),
                        selected: _starredOnly,
                        onSelected: (bool v) => both(() => _starredOnly = v),
                      ),
                      FilterChip(
                        label: Text(l.nodesFilterInRange),
                        selected: _inRangeOnly,
                        onSelected: (bool v) => both(() => _inRangeOnly = v),
                      ),
                    ],
                  ),
                  label(l.nodesFilterLastSeenTitle),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final (Duration?, String) opt in <(Duration?, String)>[
                        (null, l.nodesAgeAny),
                        (const Duration(hours: 1), l.nodesAgeHour),
                        (const Duration(hours: 24), l.nodesAge24h),
                        (const Duration(days: 7), l.nodesAge7d),
                      ])
                        ChoiceChip(
                          label: Text(opt.$2),
                          selected: _maxAge == opt.$1,
                          onSelected: (_) => both(() => _maxAge = opt.$1),
                        ),
                    ],
                  ),
                  label(l.nodesFilterWithinTitle),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final (double?, String) opt in <(double?, String)>[
                        (null, l.nodesDistAny),
                        (100, l.nodesDist100m),
                        (500, l.nodesDist500m),
                        (5000, l.nodesDist5km),
                        (25000, l.nodesDist25km),
                      ])
                        ChoiceChip(
                          label: Text(opt.$2),
                          selected: _maxDistanceMeters == opt.$1,
                          onSelected: (_) =>
                              both(() => _maxDistanceMeters = opt.$1),
                        ),
                    ],
                  ),
                  if (mc.allTags.isNotEmpty) ...<Widget>[
                    label(l.nodesTagFilter),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final String t in mc.allTags)
                          FilterChip(
                            label: Text(t),
                            selected: _selectedTags.contains(t),
                            onSelected: (bool v) => both(() {
                              if (v) {
                                _selectedTags.add(t);
                              } else {
                                _selectedTags.remove(t);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      TextButton(
                        onPressed: _anyFilterActive
                            ? () => both(_clearFilters)
                            : null,
                        child: Text(l.nodesFilterClear),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l.nodesFiltersDone),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showDetail(MeshcoreController mc, DiscoveredNode n) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => NodeDetailSheet(
        node: n,
        distanceMeters: n.hasLocation
            ? mc.distanceMetersTo(n.latitude!, n.longitude!)
            : null,
        isFavourite: mc.favorites.contains(n.pubKeyHex),
        isKnown: mc.known.contains(n.pubKeyHex),
        onToggleFavourite: () => mc.toggleFavorite(n.pubKeyHex),
        recentDms: mc.dmHistoryFor(n.pubKeyHex),
        proximity: mc.proximityFor(n),
        tags: mc.tagsFor(n.pubKeyHex),
        tagSuggestions: mc.allTags,
        onAddTag: (String t) => mc.addTagTo(n.pubKeyHex, t),
        onRemoveTag: (String t) => mc.removeTagFrom(n.pubKeyHex, t),
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _searchCtrl.clear();
      _query = '';
      _starredOnly = false;
      _inRangeOnly = false;
      _selectedTags.clear();
      _maxAge = null;
      _maxDistanceMeters = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final MmSkin skin = context.skin;
    // Loud skins (NERV: chamfer + ornament) render node rows as framed
    // panel cards; calm skins (SEELE) keep flat hairline rows.
    final bool cardRows =
        skin.shape.corner != MmCorner.sharp || skin.ornament.any;
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ready = mc.state == MeshcoreConnectionState.ready;
    final Set<String> favs = mc.favorites;
    // Self gets excluded — we never want to DM ourselves and we're
    // already on the dashboard, not in the discovered-fabric list.
    final String? selfPk = mc.ownPubKeyHex;
    final List<DiscoveredNode> nodes = <DiscoveredNode>[
      for (final DiscoveredNode n in mc.nodes)
        if (n.pubKeyHex != selfPk && _passesFilters(n, mc, favs)) n
    ]..sort((DiscoveredNode a, DiscoveredNode b) {
        final bool af = favs.contains(a.pubKeyHex);
        final bool bf = favs.contains(b.pubKeyHex);
        if (af != bf) return af ? -1 : 1;
        return 0;
      });

    // Spatial-aware: counts nodes the user would actually see as
    // "IN RANGE" (near or — when location is unknown — recent).
    final int inRange = nodes.where((DiscoveredNode n) {
      final NodeProximity p = mc.proximityFor(n);
      return p == NodeProximity.near || p == NodeProximity.recent;
    }).length;
    final int totalFabric = mc.nodes
        .where((DiscoveredNode n) => n.pubKeyHex != selfPk)
        .length;

    void advertise(bool flood) {
      mc.sendSelfAdvert(flood: flood);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(flood
              ? l.nodesFloodAdvertSent
              : l.nodesZeroHopAdvertSent),
        ));
    }

    return MmScaffold(
      child: Column(
      children: <Widget>[
        // R91 — three radio actions that used to sit in a Row with one
        // Expanded child, so at 320 dp the other two squeezed it until the
        // row overflowed. A Wrap lays them out at their natural width and
        // drops to a second line when the row is too narrow.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              SizedBox(
                child: FilledButton.icon(
                  icon: mc.isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.radar),
                  label: Text(mc.isScanning ? l.nodesScanning : l.nodesScanArea),
                  onPressed: ready && !mc.isScanning ? mc.scan : null,
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.podcasts),
                label: Text(l.nodesAdvertise),
                onPressed: ready
                    ? () async {
                        final bool? flood =
                            await showModalBottomSheet<bool>(
                          context: context,
                          showDragHandle: true,
                          builder: (BuildContext _) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                ListTile(
                                  leading:
                                      const Icon(Icons.travel_explore),
                                  title: Text(l.nodesFloodAdvert),
                                  subtitle: Text(l.nodesFloodAdvertBody),
                                  onTap: () =>
                                      Navigator.pop(context, true),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.podcasts),
                                  title: Text(l.nodesZeroHopAdvert),
                                  subtitle: Text(l.nodesZeroHopAdvertBody),
                                  onTap: () =>
                                      Navigator.pop(context, false),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (flood != null) advertise(flood);
                      }
                    : null,
              ),
              IconButton(
                tooltip: l.nodesSyncContacts,
                icon: const Icon(Icons.sync),
                onPressed: ready ? () => mc.requestContacts() : null,
              ),
            ],
          ),
        ),
        // R91 — one row of chrome: search plus a Filters button. The
        // seven-chip horizontal scroller that used to sit here (with two
        // menus positioned by a hard-coded RelativeRect) needed 44 dp and
        // hid both the active filters and the Clear action past the right
        // edge. Same controls, one sheet, laid out where they can breathe.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (String v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l.nodesClearSearch,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  hintText: l.nodesSearchHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: _activeFilterCount > 0,
              label: Text('$_activeFilterCount'),
              child: IconButton.filledTonal(
                tooltip: l.nodesFiltersTitle,
                icon: const Icon(Icons.tune),
                onPressed: () => _openFilters(mc, l),
              ),
            ),
          ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Text(
            ready
                ? l.nodesStatusReady(
                    nodes.length, totalFabric, inRange, favs.length)
                : l.nodesStatusOffline,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: nodes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      _anyFilterActive
                          ? l.nodesEmptyFiltered
                          : ready
                              ? l.nodesEmptyReady
                              : l.nodesEmptyOffline,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: cardRows
                      ? const EdgeInsets.fromLTRB(12, 8, 12, 12)
                      : EdgeInsets.zero,
                  itemCount: nodes.length,
                  separatorBuilder: (_, __) => SizedBox(height: cardRows ? 8 : 0),
                  itemBuilder: (BuildContext c, int i) {
                    final DiscoveredNode n = nodes[i];
                    return MmListRow(
                      alignTop: true,
                      onTap: () => _showDetail(mc, n),
                      leading: Builder(builder: (BuildContext _) {
                        final NodeProximity p = mc.proximityFor(n);
                        final bool near = p == NodeProximity.near ||
                            p == NodeProximity.recent;
                        return Icon(
                          near
                              ? Icons.sensors
                              : (n.viaAdvert
                                  ? Icons.podcasts
                                  : Icons.contacts),
                          color:
                              near ? cs.primary : cs.onSurfaceVariant,
                        );
                      }),
                      title: Builder(builder: (BuildContext _) {
                        final int dmN = mc.dmCountFor(n.pubKeyHex);
                        final int unread = dmN == 0
                            ? 0
                            : mc.unreadDmCountFor(n.pubKeyHex);
                        // Alt-colour the badge when unread > 0 so the
                        // user can tell at a glance which threads
                        // have new traffic since they last opened them.
                        final Color badgeFg =
                            unread > 0 ? cs.tertiary : cs.primary;
                        return Row(
                          children: <Widget>[
                            Flexible(
                                child: Text(
                                    n.name.isEmpty ? n.shortId : n.name)),
                            Builder(builder: (BuildContext _) {
                              // Spatial-aware badge: IN RANGE for
                              // <10 km / recently heard; FAR for
                              // >50 km. Middle ground (10-50 km) has
                              // no badge — distance text already
                              // communicates it.
                              final NodeProximity p =
                                  mc.proximityFor(n);
                              if (p == NodeProximity.near ||
                                  p == NodeProximity.recent) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(left: 8),
                                  child: Text(l.nodesInRangeBadge,
                                      style: TextStyle(
                                          fontSize: 10,
                                          letterSpacing: 1,
                                          color: cs.primary)),
                                );
                              }
                              if (p == NodeProximity.far) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(left: 8),
                                  child: Text(l.nodesFarBadge,
                                      style: TextStyle(
                                          fontSize: 10,
                                          letterSpacing: 1,
                                          color: cs.onSurfaceVariant)),
                                );
                              }
                              return const SizedBox.shrink();
                            }),
                            if (dmN > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                        unread > 0
                                            ? Icons.mark_unread_chat_alt
                                            : Icons.chat_bubble,
                                        size: 12,
                                        color: badgeFg),
                                    const SizedBox(width: 3),
                                    Text(
                                      unread > 0
                                          ? '$unread / $dmN'
                                          : '$dmN',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: badgeFg,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      }),
                      subtitle: Builder(builder: (BuildContext _) {
                        String? distance;
                        if (n.hasLocation) {
                          distance = geo.formatDistance(
                              mc.distanceMetersTo(
                                  n.latitude!, n.longitude!));
                        }
                        // R28 — tag chips inline below the regular
                        // metadata line. Hidden when no tags so the
                        // row stays compact for untagged nodes.
                        final List<String> tags =
                            mc.tagsFor(n.pubKeyHex);
                        final telem = mc.telemetryFor(n.pubKeyHex);
                        // R102 — what the row is for: who, what kind, how
                        // far, how strong. The old line joined six facts with
                        // `·` (including a bare 12-hex pubkey prefix and a
                        // 4-decimal coordinate pair) and wrapped to three
                        // lines on a 387 dp phone at 1.3x text. Coordinates
                        // and the full id live in the detail sheet; the list
                        // keeps the two facts that change a decision.
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(<String>[
                              n.typeLabel,
                              if (distance != null) distance,
                            ].join(' · '),
                                style: TextStyle(
                                    color: cs.onSurfaceVariant)),
                            if (n.signalLabel.isNotEmpty)
                              Text(n.signalLabel,
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontFamily: context.skin.type.monoFamily,
                                      fontSize: 11,
                                      height: 1.4)),
                            if (telem?.temperatureC != null) ...<Widget>[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: cs.tertiaryContainer,
                                  borderRadius: mmRadius(context, 8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(Icons.thermostat,
                                        size: 11,
                                        color: cs.onTertiaryContainer),
                                    const SizedBox(width: 3),
                                    Text(
                                      <String>[
                                        '${telem!.temperatureC!.toStringAsFixed(1)}°C',
                                        if (telem.humidityPct != null)
                                          '${telem.humidityPct!.toStringAsFixed(0)}%',
                                      ].join(' · '),
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: cs.onTertiaryContainer),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (tags.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 4,
                                runSpacing: 2,
                                children: <Widget>[
                                  for (final String t in tags)
                                    Container(
                                      padding: const EdgeInsets
                                          .symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: cs.secondaryContainer,
                                        borderRadius:
                                            mmRadius(context, 8),
                                      ),
                                      child: Text(t,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: cs
                                                  .onSecondaryContainer)),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        );
                      }),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(_ago(n.lastHeardUnix),
                              style:
                                  TextStyle(color: cs.onSurfaceVariant)),
                          IconButton(
                            tooltip: mc.isFavorite(n.pubKeyHex)
                                ? l.nodesUnfavTooltip
                                : l.nodesFavTooltip,
                            iconSize: 20,
                            icon: Icon(
                              mc.isFavorite(n.pubKeyHex)
                                  ? Icons.star
                                  : Icons.star_border,
                              color: mc.isFavorite(n.pubKeyHex)
                                  ? cs.tertiary
                                  : cs.onSurfaceVariant,
                            ),
                            onPressed: () =>
                                mc.toggleFavorite(n.pubKeyHex),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
      ),
    );
  }
}
