// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import 'grid_notice.dart';
import '../theme/mm_skin.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/mesh_graph.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/mesh_radial_layout.dart';
import '../ui/mm_components.dart';
import '../util/force_layout.dart';
import 'node_detail_sheet.dart';
import '../ui/mm_shape.dart';

/// R50 — directed mesh topology tree, force-directed layout. The
/// data comes straight from `Contact.outPath` (the route the device
/// uses to reach each peer); the layout uses spring physics so
/// shared repeaters naturally become hubs.
///
/// Compared to the globe view this is *topology, not geography* —
/// peers without GPS still get a place (their connectivity does the
/// work). Compared to the radial view this is *connectivity, not
/// recency* — every edge in the picture is a confirmed route.
class MeshTreeView extends StatefulWidget {
  /// Every depth the slider can hold, plus the "no limit" stop.
  ///
  /// It used to be 0..6 with 6 meaning All, so the last step before All was
  /// five hops — and on a mesh whose routes are mostly unlearned there is
  /// nothing between five and everything, which made the control feel like a
  /// switch. Ten hops is the real next step down from All: it is under the
  /// firmware's own path ceiling, so "≤10" and "All" differ only by the peers
  /// whose route the radio has not learned.
  static const List<int> hopStops = <int>[0, 1, 2, 3, 4, 5, 10, allHops];

  /// The stop that applies no depth limit at all.
  ///
  /// The number lives on [MeshGraph] because the filter needs to know which
  /// value means "everything"; this is the same constant under the name the
  /// screen uses.
  static const int allHops = MeshGraph.noLimit;

  /// The label for a stop, including what the limit actually reached.
  ///
  /// A stop below All filters on the depth the *radio* learned, so on a mesh
  /// with no learned routes it can only be honest about that: "no routes"
  /// rather than a count of zero that reads as a bug.
  @visibleForTesting
  static String hopLabelFor(int hops, AppLocalizations l,
      {required int routed}) {
    if (hops >= allHops) return l.meshTreeHopsFlood;
    final String base = hops <= 0 ? l.meshTreeHopsDirect : l.meshTreeHopsN(hops);
    return routed == 0
        ? '$base · ${l.meshTreeHopsNoRoutes}'
        : '$base · ${l.meshTreeHopsRouted(routed)}';
  }

  /// The stop the tree opens on.
  ///
  /// The smallest stop that just covers every learned route, so the tree opens
  /// on a *number* that is populated and complete rather than on All. All is
  /// still one drag away, and stays the only honest answer when the radio has
  /// learned no routes at all — a limit cannot be applied to a depth nobody
  /// measured, so at that point the control has nothing to do and says so.
  @visibleForTesting
  static int defaultHops(int deepestRouted, {int routed = 1}) {
    if (routed <= 0 || deepestRouted <= 0) return allHops;
    for (final int stop in hopStops) {
      if (stop >= deepestRouted) return stop;
    }
    return allHops;
  }

  /// The slider position for a depth.
  @visibleForTesting
  static int hopIndex(int hops) {
    if (hops >= allHops) return hopStops.length - 1;
    final int i = hopStops.indexOf(hops);
    if (i >= 0) return i;
    // A value that is not a stop lands on the nearest stop at or below it, so
    // an old depth can never select All by accident.
    int best = 0;
    for (int k = 0; k < hopStops.length; k++) {
      if (hopStops[k] <= hops) best = k;
    }
    return best;
  }

  const MeshTreeView({
    super.key,
    this.filteredNodes,
    this.frozen = false,
  });

  /// Optional pre-filtered list (e.g. the parent screen applied
  /// favourites-only). When null the controller's full node list
  /// drives the graph.
  final List<DiscoveredNode>? filteredNodes;

  /// Pause the force simulation. The current frame keeps rendering.
  final bool frozen;

  @override
  State<MeshTreeView> createState() => _MeshTreeViewState();
}

class _MeshTreeViewState extends State<MeshTreeView> {
  /// No ticker: the layout is a function of the graph, so there is nothing to
  /// animate. The force simulation this replaced ran every frame and drew a
  /// different picture of the same mesh each time it was opened.

  final Map<String, NodePosition> _positions = <String, NodePosition>{};
  final TransformationController _transform = TransformationController();
  RadialLayout? _radial;

  /// Who gets a name drawn; see `_labelsFor`.
  Set<String> _labels = const <String>{'self'};
  int _lastGraphSignature = 0;
  Size _lastSize = Size.zero;

  /// Max hop depth shown. 0 = direct neighbours only, [allHops] = everything
  /// (including the peers whose depth is unknown). It opens on the smallest
  /// stop that covers every learned route — see [defaultHops] — because a stop
  /// below All only asserts what it can check: peers whose route the radio has
  /// learned, at most N deep. "Default 6" was true when the top of the ladder
  /// was six; the ladder is 0..5, ten, then All, and All is the only value that
  /// can mean "everything".
  int _maxHops = MeshTreeView.allHops;

  /// Whether the opening stop has been chosen from the graph that arrived. One
  /// shot each: after that the slider is the user's and a rebuild must not move
  /// it under their finger.
  bool _stopChosen = false;

  /// When true the view continuously scales/pans to frame the whole
  /// graph (so a few-hundred-node cloud is always visible). Disabled
  /// the moment the user pinch-zooms or pans; re-enabled by the
  /// recenter button.
  bool _autoFit = true;

  /// Scale + pan the InteractiveViewer so every node fits the
  /// viewport with padding. Lerped toward the target each frame so
  /// the framing eases as the layout settles instead of snapping.
  void _fitToContent({bool immediate = false}) {
    if (_positions.isEmpty || _lastSize == Size.zero) return;
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final NodePosition p in _positions.values) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    final double contentW = math.max(maxX - minX, 1);
    final double contentH = math.max(maxY - minY, 1);
    const double pad = 64.0;
    final double sx = (_lastSize.width - pad) / contentW;
    final double sy = (_lastSize.height - pad) / contentH;
    final double target = math.min(sx, sy).clamp(0.1, 1.8);
    final double cx = (minX + maxX) / 2;
    final double cy = (minY + maxY) / 2;
    final double tTx = _lastSize.width / 2 - cx * target;
    final double tTy = _lastSize.height / 2 - cy * target;

    final Matrix4 cur = _transform.value;
    final double curScale = cur.getMaxScaleOnAxis();
    // Matrix4 storage is column-major; translation x/y live at 12/13.
    final double curTx = cur.storage[12];
    final double curTy = cur.storage[13];
    final double k = immediate ? 1.0 : 0.18;
    final double ns = curScale + (target - curScale) * k;
    final double ntx = curTx + (tTx - curTx) * k;
    final double nty = curTy + (tTy - curTy) * k;
    // Build scale+translate directly via setEntry to avoid the
    // deprecated Matrix4.translate/scale helpers.
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, ns) // scale x
      ..setEntry(1, 1, ns) // scale y
      ..setEntry(0, 3, ntx) // translate x
      ..setEntry(1, 3, nty); // translate y
    if (immediate && mounted) setState(() {});
  }

  /// Who gets a name drawn, and who is just a mark.
  ///
  /// A hand-sized mesh labels everyone. A public mesh with two hundred peers on
  /// one ring cannot: at 197 labels the text covers the whole dial and the
  /// picture stops being a tree. So the cap sorts by *depth* first — the rings
  /// nearest the radio keep their names — and the rest are marks you tap. Every
  /// favourite and known contact is always named, because those are the ones a
  /// reader is looking for.
  static Set<String> _labelsFor(RadialLayout radial, MeshGraph g) {
    final List<RadialPlace> ordered = radial.places.toList()
      ..sort((RadialPlace a, RadialPlace b) {
        final int d = (a.depth < 0 ? 999 : a.depth)
            .compareTo(b.depth < 0 ? 999 : b.depth);
        return d != 0 ? d : a.id.compareTo(b.id);
      });
    const int cap = 60;
    return <String>{
      'self',
      for (final RadialPlace p in ordered.take(cap)) p.id,
    };
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Asking the radio for the routes the tree is drawn from.
  ///
  /// A route is learned by the *radio*, not by this app: each contact in its
  /// table carries the outbound path it took, and a contact that has never been
  /// routed to has none. So the tree's "no learned routes" state is not a bug to
  /// work around but a fact, and the one action that changes it is asking the
  /// radio to stream its contact table again.
  Future<void> _learnRoutes(MeshcoreController mc) async {
    setState(() => _learning = true);
    try {
      final int before = mc.nodes.length;
      final int routesBefore = MeshGraph.fromController(mc).routed;
      await mc.requestContacts();
      // Wait for the table to actually change rather than for a fixed 600 ms:
      // the frames arrive as they arrive, so a slow radio showed "done" before
      // any route had landed and a fast one kept the spinner up for nothing.
      // Either a node appears or a peer gains a route; after three seconds the
      // answer is "nothing came back", which is itself worth showing.
      final Stopwatch waited = Stopwatch()..start();
      while (mounted && waited.elapsed < const Duration(seconds: 3)) {
        if (mc.nodes.length != before ||
            MeshGraph.fromController(mc).routed != routesBefore) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      if (mounted) setState(() => _learning = false);
    }
  }

  bool _learning = false;

  void _recenter() {
    // Re-enable auto-fit *and* do the fitting, in one frame. The ticker that
    // used to lerp the transform every frame is gone with the force simulation,
    // so a non-immediate call scheduled nothing to finish the ease: one tap moved
    // the camera 18 % of the way and the rebuild then hid the button, leaving a
    // user who had panned away with no way back.
    setState(() => _autoFit = true);
    _fitToContent(immediate: true);
  }

  /// Rebuild the radial tree when the graph's node-set or the viewport
  /// changes.
  ///
  /// Cheap enough to be a pure function of the graph: no simulation, no
  /// settling, no frame-to-frame drift. The signature keeps a rebuild that only
  /// changed a name or a timestamp from re-laying the tree out.
  void _ensureLayout(MeshGraph g, Size size) {
    int sig = 17;
    for (final MeshGraphNode n in g.nodes) {
      sig = (sig * 31 + n.id.hashCode) & 0x7fffffff;
    }
    for (final MeshGraphEdge e in g.edges) {
      sig = (sig * 31 + e.key.hashCode) & 0x7fffffff;
    }
    final bool sizeChanged = (_lastSize.width - size.width).abs() > 8 ||
        (_lastSize.height - size.height).abs() > 8;
    if (sig == _lastGraphSignature && _radial != null && !sizeChanged) {
      return;
    }
    _lastGraphSignature = sig;
    _lastSize = size;

    final RadialLayout radial = radialHopLayout(g);
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    // The outermost ring has to fit, and its labels sit just inside the edge.
    final double maxR = math.max(24, math.min(size.width, size.height) / 2 - 34);
    final Map<String, NodePosition> next = <String, NodePosition>{};
    for (final RadialPlace p in radial.places) {
      final double r = p.radius * maxR;
      next[p.id] = NodePosition(
        x: cx + r * math.sin(p.angle),
        y: cy - r * math.cos(p.angle),
        pinned: p.id == 'self',
      );
    }
    _positions
      ..clear()
      ..addAll(next);
    _radial = radial;
    _labels = _labelsFor(radial, g);
    if (_autoFit) {
      // Straight to the framing, not lerped: the layout arrives complete, so
      // there is no settling to ease through. The ticker that used to do this
      // every frame is gone with the force simulation.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _fitToContent(immediate: true));
    }
  }

  void _maybeShowDetail(MeshcoreController mc, Offset tap) {
    // Hit-test by finding the closest node within 24 *screen* pixels. The
    // positions are in child coordinates and the child is inside an
    // `InteractiveViewer` down to 0.1×, so a fixed 24 in child space is a 2.4 px
    // target at fit zoom — smaller than a fingertip — and 96 px at 4×. Dividing
    // by the live scale keeps the target the size of the finger at every zoom.
    final double scale = _transform.value.getMaxScaleOnAxis();
    final double reach = 24 / (scale <= 0 ? 1 : scale);
    String? hitId;
    double bestD2 = reach * reach;
    _positions.forEach((String id, NodePosition p) {
      final double dx = p.x - tap.dx;
      final double dy = p.y - tap.dy;
      final double d2 = dx * dx + dy * dy;
      if (d2 < bestD2) {
        bestD2 = d2;
        hitId = id;
      }
    });
    if (hitId == null || hitId == 'self') return;
    DiscoveredNode? node;
    for (final DiscoveredNode n in mc.nodes) {
      if (n.pubKeyHex == hitId) {
        node = n;
        break;
      }
    }
    if (node == null) return;
    final DiscoveredNode peer = node;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => NodeDetailSheet(
        node: peer,
        distanceMeters: peer.hasLocation
            ? mc.distanceMetersTo(peer.latitude!, peer.longitude!)
            : null,
        isFavourite: mc.favorites.contains(peer.pubKeyHex),
        isKnown: mc.known.contains(peer.pubKeyHex),
        onToggleFavourite: () => mc.toggleFavorite(peer.pubKeyHex),
        proximity: mc.proximityFor(peer),
        recentDms: mc.dmHistoryFor(peer.pubKeyHex),
        tags: mc.tagsFor(peer.pubKeyHex),
        tagSuggestions: mc.allTags,
        onAddTag: (String t) => mc.addTagTo(peer.pubKeyHex, t),
        onRemoveTag: (String t) => mc.removeTagFrom(peer.pubKeyHex, t),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);

    final MeshGraph graph = MeshGraph.fromController(
      mc,
      filteredNodes: widget.filteredNodes,
      maxHops: _maxHops,
    );
    if (!_stopChosen && graph.peers > 0) {
      _stopChosen = true;
      final int opening =
          MeshTreeView.defaultHops(graph.deepestRouted, routed: graph.routed);
      if (opening != _maxHops) {
        // A frame later: choosing it here would change the graph this build is
        // already holding.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _maxHops = opening);
        });
      }
    }

    return LayoutBuilder(
      builder: (BuildContext _, BoxConstraints c) {
        final Size size = Size(c.maxWidth, c.maxHeight);
        _ensureLayout(graph, size);
        return Stack(
          children: <Widget>[
            // InteractiveViewer handles pinch-zoom + two-finger pan +
            // mouse-wheel zoom. The canvas inside is laid out at the
            // viewport size; the viewer transforms it. Gestures
            // delivered to children land in the *unscaled* coordinate
            // space, so hit-testing against _positions still works
            // without manual matrix math.
            //
            // boundaryMargin huge so you can pan a long way before
            // hitting an edge — the layout drifts outward when the
            // mesh grows large.
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 0.1,
                maxScale: 4.0,
                boundaryMargin: const EdgeInsets.all(2000),
                // Manual pinch/pan turns off auto-fit so we stop
                // fighting the user; the recenter button turns it
                // back on.
                onInteractionStart: (_) {
                  if (_autoFit) setState(() => _autoFit = false);
                },
                // The canvas hit-tests its own marks, so the label is on the
                // canvas: a screen reader is told what a tap does here.
                child: Semantics(
                  button: true,
                  label: l.mapCanvasSemantics,
                  child: GestureDetector(
                    onTapUp: (TapUpDetails d) =>
                        _maybeShowDetail(mc, d.localPosition),
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: CustomPaint(
                        painter: _MeshTreePainter(
                          type: context.skin.type,
                          radial: _radial,
                          labels: _labels,
                          textScale: MediaQuery.textScalerOf(context).scale(1),
                          graph: graph,
                          positions: _positions,
                          knownPubKeys: mc.known,
                          favPubKeys: mc.favorites,
                          accent: cs.primary,
                          accentDim: cs.primary.withValues(alpha: .35),
                          hub: cs.tertiary,
                          edge: cs.primary.withValues(alpha: .55),
                          edgeFloat: cs.outline.withValues(alpha: .35),
                          label: cs.onSurface,
                          bg: cs.surface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Nothing but us, and two different reasons for it.
            //
            // A hop limit *can* empty the tree now: below Flood / All a stop
            // means "a learned route at most this deep", and a peer heard only
            // by advert has no learned route. Saying "waiting for contact sync"
            // there would be a lie — the peers are all present, the filter is
            // what removed them — so the notice names the filter and the number
            // it is holding back.
            if (graph.nodes.length <= 1)
              Positioned.fill(
                child: GridNotice(
                  message: graph.hidden > 0
                      // Named by the stop's own label, and with the two counts
                      // in the order the message declares them: `n` is the stop
                      // and `count` is how many peers it hid. They were swapped,
                      // which is how a stop of three hops came to read "within
                      // 201 hops" — 201 being the peers it had hidden.
                      ? l.meshTreeFilteredEmptyFor(
                          MeshTreeView.hopLabelFor(_maxHops, l,
                              routed: graph.routed),
                          graph.hidden)
                      : l.meshTreeEmpty,
                  icon: Icons.account_tree,
                ),
              ),
            // Recenter overlay — listens to the transformation
            // controller so it appears only when the user has zoomed
            // or panned away from the default view. Identity matrix
            // Shown only when the user has taken manual control
            // (auto-fit off). Tapping re-enables auto-fit so the view
            // eases back to framing the whole graph.
            // Recenter sits top-right, in the same corner as every other
            // grid view's reset (the heat map has had it there all along).
            // It used to be bottom-right, above the hop slider, after both
            // were found sharing `bottom: 12` and the button was painted under
            // the slider. Top-right is both the consistent answer and the one
            // that cannot collide with the bottom strip.
            if (!_autoFit)
              Positioned(
                right: 12,
                top: 12,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.center_focus_strong, size: 16),
                  label: Text(l.meshTreeRecenter),
                  onPressed: _recenter,
                ),
              ),
            // Hop-depth slider — trims the tree to peers whose *known* route
            // is within N hops. Peers whose route the radio has not learned
            // stay, drawn as floaters: a limit cannot exclude a depth nobody
            // measured. Default 6 keeps everything visible on a mesh with no
            // learned routes, which is the public mesh most of the time.
            // The corner strip that named the four shapes is gone: the legend
            // panel one tap away already names every mark, and the strip's copy
            // disagreed with it ("client" here, "chat" there) because it was a
            // hardcoded line inside a translated string.
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              // No learned routes means no depth to limit: every peer is an
              // unknown, and a stop cannot be applied to a depth nobody
              // measured. Offering the slider anyway is what made the ladder
              // read as broken — every stop below All drew the same empty tree,
              // and the notice blamed a hop count the reader could not act on.
              //
              // And only when there is a tree to explain: with no peers at all
              // the empty notice is already saying it, and two panels describing
              // an empty mesh in different words is one too many.
              child: graph.nodes.length <= 1
                  ? const SizedBox.shrink()
                  : graph.routed == 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: mmRadius(context, 8),
                        border: Border.all(color: cs.outline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            l.meshTreeNoRoutes,
                            style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: context.skin.type.sizeSm),
                          ),
                          // The routes come from the radio's contact table, so
                          // "learn routes" is "ask the radio for its contacts".
                          // It is offered only where the tree has nothing to
                          // draw, which is the moment a reader wants it.
                          if (mc.isReady)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: MmAction(
                                label: _learning
                                    ? l.meshTreeLearning
                                    : l.meshTreeLearnRoutes,
                                icon: _learning
                                    ? Icons.hourglass_empty
                                    : Icons.download_for_offline_outlined,
                                dense: true,
                                onPressed: _learning
                                    ? null
                                    : () => _learnRoutes(mc),
                              ),
                            ),
                        ],
                      ),
                    )
                  : _HopSlider(
                      index: MeshTreeView.hopIndex(_maxHops),
                      stops: MeshTreeView.hopStops.length,
                      label: MeshTreeView.hopLabelFor(_maxHops, l,
                          routed: graph.routed),
                      cs: cs,
                      onChanged: (int i) {
                        final int hops = MeshTreeView.hopStops[
                            i.clamp(0, MeshTreeView.hopStops.length - 1)];
                        if (hops != _maxHops) setState(() => _maxHops = hops);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

}

/// Compact hop-depth slider for the tree view: direct, 1..5, ten, then All,
/// with a label chip saying which stop is current and what it reached.
class _HopSlider extends StatelessWidget {

  const _HopSlider({
    required this.index,
    required this.stops,
    required this.label,
    required this.cs,
    required this.onChanged,
  });

  /// The current stop's position, not its hop count: the ladder is uneven
  /// (0..5, 10, All) and a slider over hop counts would put five and ten a
  /// pixel apart.
  final int index;
  final int stops;
  final String label;
  final ColorScheme cs;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        // Solid: the slider is a control over the tree's own strokes, and the
        // label above it has to be read before the canvas is.
        color: cs.surface,
        borderRadius: mmRadius(context, 8),
        border: Border.all(color: cs.outline),
      ),
      // The label sits above the slider, not beside it.
      //
      // It used to be a fixed 96 dp box beside the slider, which held "Direct"
      // but not "≤3 hops · 12 routed": the sentence was clipped to nothing
      // useful. Widening it beside the slider then traded the label's room for
      // the control's, and at 320 dp with 2.0 text neither had enough — the
      // label needed three lines and the slider was down to its floor. A
      // readout and a control do not have to share a line to belong together:
      // stacked, the label gets the full width and the slider gets the full
      // width, at every scale, with nothing to tune.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.account_tree,
                  size: context.skin.type.sizeMicro + 4, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: context.skin.type.sizeSm,
                    fontFamily: context.skin.type.monoFamily,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            width: double.infinity,
            child: Slider(
              value: index.toDouble(),
              min: 0,
              max: (stops - 1).toDouble(),
              divisions: stops - 1,
              onChanged: (double v) => onChanged(v.round()),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeshTreePainter extends CustomPainter {
  _MeshTreePainter({
    required this.type,
    required this.textScale,
    required this.radial,
    required this.labels,
    required this.graph,
    required this.positions,
    required this.knownPubKeys,
    required this.favPubKeys,
    required this.accent,
    required this.accentDim,
    required this.hub,
    required this.edge,
    required this.edgeFloat,
    required this.label,
    required this.bg,
  });

  /// The skin's type roles, passed in because a painter has no [BuildContext].
  final MmType type;

  /// The user's text scale, multiplied into every label this painter draws.
  ///
  /// `MmType` carries the *skin's* scale only, so a painted label was the one
  /// text in the app that ignored the font setting: at 200 % the list, the
  /// sheets and the notice grew and the tree's own node names did not.
  final double textScale;

  /// The hop rings, so the canvas can draw and label them.
  final RadialLayout? radial;

  /// The nodes whose names are drawn. See `_labelsFor` for why this is a cap
  /// rather than everything.
  final Set<String> labels;

  final MeshGraph graph;
  final Map<String, NodePosition> positions;
  final Set<String> knownPubKeys;
  final Set<String> favPubKeys;
  final Color accent;
  final Color accentDim;
  final Color hub;
  final Color edge;
  final Color edgeFloat;
  final Color label;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);

    // Hop rings, then the edges over them. The radius *is* the hop count, so
    // the rings are the scale of the picture rather than decoration: ring 3 is
    // "everything learned three hops out", and the outermost ring, labelled
    // with a question mark, is the peers nobody has a route for.
    final RadialLayout? r = radial;
    // A ring label is the scale of a picture. With nothing circled there is no
    // scale to state, and the single outer ring drew only its number — a bare
    // "1" floating at the rim of an empty dial.
    if (r != null && r.rings > 0 && r.places.length > 1) {
      final Offset c0 = size.center(Offset.zero);
      final double maxR =
          math.max(24, math.min(size.width, size.height) / 2 - 34);
      final Paint ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edgeFloat;
      for (int d = 1; d <= r.rings; d++) {
        final double radius = maxR * d / r.rings;
        if (d < r.rings) {
          canvas.drawCircle(c0, radius, ringPaint);
        }
        final String text = (r.hasUnknown && d == r.rings) ? '?' : '$d';
        final TextPainter tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: edge,
              fontSize: type.sizeMicro * textScale,
              fontFamily: type.monoFamily,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(c0.dx + 4, c0.dy - radius + 2));
      }
    }

    // Edges first so node circles sit on top.
    final Paint edgePaint = Paint()
      ..color = edge
      ..strokeWidth = 1.2;
    // Flood edges: dimmer + dashed — reachable, but no fixed path.
    final Paint floodPaint = Paint()
      ..color = edgeFloat
      ..strokeWidth = 1.0;
    for (final MeshGraphEdge e in graph.edges) {
      final NodePosition? a = positions[e.fromId];
      final NodePosition? b = positions[e.toId];
      if (a == null || b == null) continue;
      final Offset p0 = Offset(a.x, a.y);
      final Offset p1 = Offset(b.x, b.y);
      if (e.flood) {
        _drawDashedLine(canvas, p0, p1, floodPaint);
        _drawArrow(canvas, p0, p1, floodPaint);
      } else {
        canvas.drawLine(p0, p1, edgePaint);
        _drawArrow(canvas, p0, p1, edgePaint);
      }
    }

    // Nodes.
    for (final MeshGraphNode n in graph.nodes) {
      final NodePosition? p = positions[n.id];
      if (p == null) continue;
      final Offset c = Offset(p.x, p.y);
      final _NodeStyle style = _styleFor(n);
      // Halo for known / favourites — same circle for any glyph
      // shape so the affinity cue stays consistent.
      if (favPubKeys.contains(n.id)) {
        canvas.drawCircle(
            c,
            style.radius + 5,
            Paint()
              ..color = style.colour.withValues(alpha: .25)
              ..style = PaintingStyle.fill);
      } else if (knownPubKeys.contains(n.id)) {
        canvas.drawCircle(
            c,
            style.radius + 3,
            Paint()
              ..color = style.colour.withValues(alpha: .18)
              ..style = PaintingStyle.fill);
      }
      // Body + outline, shape-aware.
      final Paint fillBg = Paint()..color = bg;
      final Paint strokeBody = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = n.isSelf ? 2.4 : 1.5
        ..color = style.colour;
      _drawShape(canvas, c, style.radius, style.shape, fillBg);
      _drawShape(canvas, c, style.radius, style.shape, strokeBody);
      // Centre dot for self.
      if (n.isSelf) {
        canvas.drawCircle(c, 3.0, Paint()..color = style.colour);
      }
      // Label, if this node is inside the cap.
      if (!labels.contains(n.id)) continue;
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: n.label,
          style: TextStyle(
            color: label,
            fontSize: type.sizeMicro * textScale,
            fontFamily: type.monoFamily,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 120);
      tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy + style.radius + 2));
    }
  }

  /// Draw the node glyph at [centre] with half-extent [r] using
  /// [paint]. The shape encodes the node's role so the topology is
  /// readable at a glance without leaning on colour alone:
  ///
  /// - **circle** — chat / sensor / self (endpoints + ego)
  /// - **square** — repeater (mast-mounted, infra)
  /// - **diamond** — room server (server-class infra)
  void _drawShape(
      Canvas canvas, Offset centre, double r, _NodeShape shape, Paint paint) {
    switch (shape) {
      case _NodeShape.circle:
        canvas.drawCircle(centre, r, paint);
      case _NodeShape.square:
        final Rect rect =
            Rect.fromCenter(center: centre, width: r * 2, height: r * 2);
        canvas.drawRect(rect, paint);
      case _NodeShape.diamond:
        final Path p = Path()
          ..moveTo(centre.dx, centre.dy - r)
          ..lineTo(centre.dx + r, centre.dy)
          ..lineTo(centre.dx, centre.dy + r)
          ..lineTo(centre.dx - r, centre.dy)
          ..close();
        canvas.drawPath(p, paint);
    }
  }

  _NodeStyle _styleFor(MeshGraphNode n) {
    if (n.isSelf) {
      return _NodeStyle(colour: accent, radius: 10, shape: _NodeShape.circle);
    }
    return switch (n.type) {
      kAdvTypeRepeater =>
        _NodeStyle(colour: hub, radius: 10, shape: _NodeShape.square),
      kAdvTypeRoom =>
        _NodeStyle(colour: hub, radius: 9, shape: _NodeShape.diamond),
      kAdvTypeSensor =>
        _NodeStyle(colour: accentDim, radius: 5, shape: _NodeShape.circle),
      _ => _NodeStyle(colour: accent, radius: 6, shape: _NodeShape.circle),
    };
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Paint paint) {
    // Place arrowhead just before the `to` node so it doesn't get
    // hidden under the node circle.
    final double dx = to.dx - from.dx;
    final double dy = to.dy - from.dy;
    final double d = math.sqrt(dx * dx + dy * dy);
    if (d < 24) return; // too short to bother
    final double ux = dx / d;
    final double uy = dy / d;
    final double backoff = 12;
    final Offset tip = Offset(to.dx - ux * backoff, to.dy - uy * backoff);
    const double arrowSize = 6;
    final Offset left = Offset(
      tip.dx - ux * arrowSize - uy * arrowSize * 0.6,
      tip.dy - uy * arrowSize + ux * arrowSize * 0.6,
    );
    final Offset right = Offset(
      tip.dx - ux * arrowSize + uy * arrowSize * 0.6,
      tip.dy - uy * arrowSize - ux * arrowSize * 0.6,
    );
    canvas.drawLine(tip, left, paint);
    canvas.drawLine(tip, right, paint);
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const double dash = 5;
    const double gap = 4;
    final double dx = to.dx - from.dx;
    final double dy = to.dy - from.dy;
    final double len = math.sqrt(dx * dx + dy * dy);
    if (len < 1) return;
    final double ux = dx / len;
    final double uy = dy / len;
    double t = 0;
    while (t < len) {
      final double end = math.min(t + dash, len);
      canvas.drawLine(
        Offset(from.dx + ux * t, from.dy + uy * t),
        Offset(from.dx + ux * end, from.dy + uy * end),
        paint,
      );
      t += dash + gap;
    }
  }

  @override
  /// Repaint only when something the picture is made of changed.
  ///
  /// This returned `true` unconditionally, so a full-screen canvas of edges,
  /// rings and labels was repainted on every frame the widget was rebuilt for
  /// any reason at all — a skin change, a toast, a poll. On a mesh with a few
  /// hundred nodes that is the most expensive paint in the app, and it was
  /// running for free.
  bool shouldRepaint(covariant _MeshTreePainter old) =>
      old.type != type ||
      old.textScale != textScale ||
      old.radial != radial ||
      old.labels != labels ||
      old.graph != graph ||
      old.positions != positions ||
      old.knownPubKeys != knownPubKeys ||
      old.favPubKeys != favPubKeys ||
      old.accent != accent ||
      old.accentDim != accentDim ||
      old.hub != hub ||
      old.edge != edge ||
      old.edgeFloat != edgeFloat ||
      old.label != label ||
      old.bg != bg;
}

/// Glyph shape per node role. Circle = endpoint, square = repeater
/// infra, diamond = room server.
enum _NodeShape { circle, square, diamond }

class _NodeStyle {
  const _NodeStyle({
    required this.colour,
    required this.radius,
    required this.shape,
  });
  final Color colour;
  final double radius;
  final _NodeShape shape;
}
