// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:meshcore/meshcore.dart'
    show AdvertPath, Contact, LoginResult, PathDiscoveryResult, PathLen,
        kAdvTypeRoom, kAdvTypeRepeater, kLoginPasswordMax;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../gen/app_localizations.dart';
import '../util/mm_format.dart';
import '../field/relationship.dart';
import '../meshcore/chat_message.dart';
import '../meshcore/discovered_node.dart';
import '../chat/block_actions.dart';
import '../meshcore/block_store.dart';
import '../meshcore/meshcore_controller.dart';
import '../bot/bot_scope.dart';
import '../bot/bot_section.dart';
import '../cue/cue_service.dart';
import '../meshcore/node_telemetry.dart';
import '../peer/peer_profiles.dart';
import '../theme/mm_skin.dart';
import '../theme/theme_controller.dart';
import '../util/geo.dart' as geo;
import '../ui/mm_components.dart';


import '../ui/mm_shape.dart';
import '../ui/mm_confirm.dart';
import '../util/relative_time.dart';
import '../peer/hop_names.dart';

/// The history row's time column, in pixels: a five-character stamp.
const double _timeGutter = 56;

/// R18 polish — modal bottom sheet shown when the user taps a node
/// on the /grid view. Shows summary stats (signal, last heard,
/// distance, lat/lon) and gives the three primary node actions:
/// **Message**, **Favourite/Unfavourite**, and a placeholder for
/// **Show on geocoded map** (R25, deferred).
class NodeDetailSheet extends StatefulWidget {
  const NodeDetailSheet({
    super.key,
    required this.node,
    required this.distanceMeters,
    this.relationship,
    required this.isFavourite,
    required this.isKnown,
    required this.onToggleFavourite,
    this.proximity = NodeProximity.unknown,
    this.tags = const <String>[],
    this.tagSuggestions = const <String>[],
    this.onAddTag,
    this.onRemoveTag,
    this.isSelf = false,
    this.cameFromDm = false,
    this.recentDms = const <ChatMessage>[],
  });

  final DiscoveredNode node;
  final double? distanceMeters;

  /// Which way the distance is going, when a caller has two readings. Null
  /// when there is nothing to compare, so the sheet never invents a trend.
  final RelationshipReading? relationship;

  /// Spatial-aware proximity classification for the IN RANGE / FAR
  /// header badge. Default `unknown` shows no badge — caller should
  /// pass `mc.proximityFor(node)` so the sheet matches the list view.
  final NodeProximity proximity;
  final bool isFavourite;
  final bool isKnown;
  final VoidCallback onToggleFavourite;

  /// R28 — current free-text tags for this node.
  final List<String> tags;

  /// R28 — autocomplete pool: every tag previously used anywhere in
  /// the app. Empty list disables autocomplete.
  final List<String> tagSuggestions;

  /// R28 — add a tag (controller-side persistence). When null, the
  /// add affordance is hidden (e.g. a sheet used in a read-only
  /// context).
  final ValueChanged<String>? onAddTag;

  /// R28 — remove a tag. When null, tag chips render without the
  /// delete X.
  final ValueChanged<String>? onRemoveTag;

  /// Most-recent DMs exchanged with this peer, oldest → newest. The
  /// sheet renders the last few of these as a "RECENT DMS" excerpt
  /// (Option D inbox surfacing).
  final List<ChatMessage> recentDms;

  /// True when [node] is *our own* pubkey — suppress Message + the
  /// favourite affordance because "DM yourself" / "favourite yourself"
  /// are meaningless. Belt-and-suspenders: /grid already filters our
  /// own pubkey out of the visible fleet, but this guards against
  /// future code paths that might land here directly.
  final bool isSelf;

  /// R96 — the sheet was opened from that peer's DM thread. Its "Message"
  /// action would push a second copy of the same conversation onto the stack
  /// (DM -> info -> Message -> DM -> ...), so it is hidden when true. The
  /// action stays for every other entry point (Nodes, grid, globe, map).
  final bool cameFromDm;

  @override
  State<NodeDetailSheet> createState() => _NodeDetailSheetState();
}

class _NodeDetailSheetState extends State<NodeDetailSheet> {
  late bool _fav = widget.isFavourite;

  /// Local mirror so the chips refresh between rebuilds — the
  /// controller path is async (persist → notifyListeners) and the
  /// sheet is shown via showModalBottomSheet, so we may not get a
  /// re-build from the provider before the user removes another.
  late List<String> _localTags = List<String>.from(widget.tags);

  void _toggle() {
    widget.onToggleFavourite();
    setState(() => _fav = !_fav);
  }

  Future<void> _promptAddTag(AppLocalizations l) async {
    final String? picked = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => _AddTagDialog(
        existing: _localTags,
        suggestions: widget.tagSuggestions,
        l: l,
      ),
    );
    if (picked == null || picked.isEmpty) return;
    if (_localTags.any(
        (String e) => e.toLowerCase() == picked.toLowerCase())) {
      return;
    }
    setState(() => _localTags = <String>[..._localTags, picked]);
    widget.onAddTag?.call(picked);
  }

  void _removeTag(String tag) {
    setState(() => _localTags = <String>[
          for (final String t in _localTags)
            if (t.toLowerCase() != tag.toLowerCase()) t,
        ]);
    widget.onRemoveTag?.call(tag);
  }

  /// Confirm + move the user's data from the stale key to the live key.
  /// If we're currently viewing the stale (now-deleted) node, close the
  /// sheet afterwards since it no longer exists in the fabric.
  Future<void> _reconcile(
      MeshcoreController mc, IdentityMatch match, AppLocalizations l) async {
    final bool viewingStale =
        widget.node.pubKeyHex == match.stale.pubKeyHex;
    await mc.reconcileIdentity(
      fromPubKeyHex: match.stale.pubKeyHex,
      toPubKeyHex: match.fresh.pubKeyHex,
    );
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(l.nodeIdentityMoved(match.fresh.name)),
        duration: const Duration(seconds: 3),
      ),
    );
    if (viewingStale) Navigator.of(context).maybePop();
  }

  /// Push this node to the radio's contact list so DMs route to it.
  Future<void> _addDeviceContact(
      MeshcoreController mc, DiscoveredNode n, AppLocalizations l) async {
    final bool ok = await mc.addNodeAsDeviceContact(n.pubKeyHex,
        name: n.name.isEmpty ? null : n.name);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
            ok ? l.nodeDetailAddDeviceContactDone : l.nodeDetailAddDeviceContactFailed),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Remove this node from the radio's contact table (frees a slot).
  Future<void> _removeDeviceContact(
      MeshcoreController mc, DiscoveredNode n, AppLocalizations l) async {
    final bool ok = await mmConfirm(
      context,
      title: l.nodeDetailRemoveDeviceContact,
      body: l.nodeDetailRemoveDeviceContactConfirm(
          n.name.isEmpty ? n.shortId : n.name),
      cancelLabel: l.actionCancel,
      confirmLabel: l.nodeDetailRemoveDeviceContact,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await mc.removeDeviceContact(n.pubKeyHex);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(l.nodeDetailRemoveDeviceContactDone),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Manual key-change linking — the reliable path when auto-detect can't
  /// (e.g. the saved contact name differs from the new advert's name).
  /// Pick the node that is the same contact under a new key; data moves
  /// from whichever side holds it to the other, and the old key retires.
  Future<void> _promptLinkKey(
      MeshcoreController mc, DiscoveredNode n, AppLocalizations l) async {
    final String? selfPk = mc.ownPubKeyHex;
    final List<DiscoveredNode> candidates = <DiscoveredNode>[
      for (final DiscoveredNode c in mc.nodes)
        if (c.pubKeyHex != n.pubKeyHex &&
            c.pubKeyHex != selfPk &&
            !mc.isSuperseded(c.pubKeyHex))
          c
    ];
    final String name = n.name.trim().toLowerCase();
    candidates.sort((DiscoveredNode a, DiscoveredNode b) {
      final bool an = a.name.trim().toLowerCase() == name;
      final bool bn = b.name.trim().toLowerCase() == name;
      if (an != bn) return an ? -1 : 1; // same-name first
      return b.lastHeardUnix.compareTo(a.lastHeardUnix); // then recent
    });

    final _LinkTarget? picked = await showModalBottomSheet<_LinkTarget>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => _LinkPicker(
        candidates: candidates,
        contactName: n.name,
        ago: _ago,
        l: l,
      ),
    );
    if (picked == null || !mounted) return;
    final String targetPk = picked.pubKeyHex.toLowerCase();
    if (targetPk == n.pubKeyHex.toLowerCase()) return;

    // Data flows from the side that holds it to the other (the live key).
    // A typed/unknown key holds nothing, so data moves from the contact.
    final bool targetHasData = mc.hasReconcileData(targetPk);
    final bool selfHasData = mc.hasReconcileData(n.pubKeyHex);
    final bool fromSelf = !(targetHasData && !selfHasData);
    final String fromPk = fromSelf ? n.pubKeyHex : targetPk;
    final String toPk = fromSelf ? targetPk : n.pubKeyHex;
    final String fromName = fromSelf ? n.name : (picked.displayName ?? '');
    final String toName = fromSelf ? (picked.displayName ?? n.name) : n.name;
    String tail(String pk) =>
        pk.length >= 6 ? pk.substring(0, 6) : pk;

    final bool ok = await mmConfirm(
      context,
      title: l.nodeIdentityLinkTitle,
      body: l.nodeIdentityLinkConfirm(
          '$fromName …${tail(fromPk)}', '$toName …${tail(toPk)}'),
      cancelLabel: l.actionCancel,
      confirmLabel: l.nodeIdentityAction,
    );
    if (!ok || !mounted) return;

    await mc.linkIdentityToKey(
        fromPubKeyHex: fromPk,
        toPubKeyHex: toPk,
        name: toName.isEmpty ? n.name : toName);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(l.nodeIdentityMoved(toName.isEmpty ? n.name : toName)),
        duration: const Duration(seconds: 3),
      ),
    );
    // If the node we're viewing became the retired key, close the sheet.
    if (mc.isSuperseded(n.pubKeyHex)) Navigator.of(context).maybePop();
  }

  String _ago(int unixSec, AppLocalizations l) =>
      nodeHeardAgo(l, unixSec);

  @override
  Widget build(BuildContext context) {
    final DiscoveredNode n = widget.node;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final String name = n.name.isEmpty ? n.shortId : n.name;
    // R56 — "returning contact": a same-name node whose key changed (peer
    // deleted + re-added). Offer to move the user's data to the live key.
    final IdentityMatch? idMatch =
        widget.isSelf ? null : mc.identityMatchFor(n.pubKeyHex);
    final String? distance =
        geo.formatDistance(widget.distanceMeters, prefs: context.formatPrefs);

    // A pill is delimited by its TINT: a tint plus a stroke in the same colour
    // says the same edge twice, and on a paper ground it reads as a small box
    // rather than a tag. This matches the temperature and tag pills on the
    // nodes list, which have always been fill-only.
    Widget chip(IconData icon, String label, Color colour) => Container(
          // Named so a test can tell a tag from a callout: they differ in
          // paint (tint only against tint plus hairline), and the difference
          // is a rule, not a preference.
          key: ValueKey<String>('node-chip-$label'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: .12),
            borderRadius: mmRadius(context, 12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 12, color: colour),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: colour, fontSize: context.skin.type.sizeSm, letterSpacing: 1)),
            ],
          ),
        );

    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: kvLabelWidth(context),
                child: Text(k,
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeBody)),
              ),
              const SizedBox(width: _kKvGap),
              Expanded(
                child: Text(v,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontFamily: context.skin.type.monoFamily,
                        fontSize: context.skin.type.sizeBody,
                        height: 1.35)),
              ),
            ],
          ),
        );

    return SafeArea(
      top: false,
      // The sheet content can exceed the sheet's height (e.g. a contact
      // with telemetry + share toggles + tags) — scroll it so it never
      // overflows the DraggableScrollableSheet.
      child: SingleChildScrollView(
        child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // R28+ spatial-aware: only show IN RANGE when we
                // actually believe they're close. Caller passes the
                // resolved enum via `proximity`. We fall back to
                // recently-heard (recent) for unknown-distance nodes
                // so the badge still appears for OTA-recent peers.
                if (widget.proximity == NodeProximity.near ||
                    widget.proximity == NodeProximity.recent)
                  chip(Icons.sensors, l.nodeDetailInRange, cs.primary),
                if (widget.proximity == NodeProximity.far)
                  chip(Icons.travel_explore, l.nodesFarBadge,
                      cs.onSurfaceVariant),
                // R96 — an explicit exit. Until now the sheet could only be
                // dismissed by the scrim, the drag handle, or the OS back
                // gesture, which is why a long sheet (a repeater with
                // telemetry, tags and actions) read as a page you were stuck
                // on once it was scrolled.
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: l.closeSheet,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                chip(Icons.cell_tower, n.typeLabel, cs.onSurfaceVariant),
                if (widget.isKnown)
                  chip(Icons.chat_bubble, l.nodeDetailKnown, cs.primary),
                if (_fav)
                  chip(Icons.star, l.nodeDetailContactBadge, cs.tertiary),
              ],
            ),
            if (idMatch != null) ...<Widget>[
              const SizedBox(height: 12),
              _ReconcileCard(
                match: idMatch,
                onMove: () => _reconcile(mc, idMatch, l),
              ),
            ],
            const SizedBox(height: 16),
            kv(l.nodeDetailShortIdKv, n.shortId),
            kv(
                l.nodeDetailPubkeyKv,
                n.pubKeyHex.length > 24
                    ? '${n.pubKeyHex.substring(0, 24)}…'
                    : n.pubKeyHex),
            if (n.signalLabel.isNotEmpty)
              kv(l.nodeDetailSignalKv, n.signalLabel),
            kv(l.nodeDetailLastHeardKv, _ago(n.lastHeardUnix, l)),
            if (distance != null)
              kv(
                l.nodeDetailDistanceKv,
                switch (widget.relationship?.trend) {
                  RelationshipTrend.closing =>
                    l.nodeClosing(name, distance),
                  RelationshipTrend.opening =>
                    l.nodeOpening(name, distance),
                  _ => distance,
                },
              ),
            if (n.hasLocation)
              kv(l.nodeDetailLatLonKv,
                  '${n.latitude!.toStringAsFixed(5)}, '
                      '${n.longitude!.toStringAsFixed(5)}'),
            // R49+1 — hop value, matching the official app's
            // categories: Direct (0 hops) / N via repeaters / Flood
            // (reachable, no fixed path) / unknown (advert-only, not
            // a contact at all).
            if (!widget.isSelf)
              kv(
                l.nodeDetailHopsKv,
                n.outPathHashes != null
                    ? (n.outPathHashes!.isEmpty
                        ? l.nodeDetailHopsDirect
                        : l.nodeDetailHopsViaRepeaters(
                            n.outPathHashes!.length))
                    : n.viaFlood
                        ? l.nodeDetailHopsFlood
                        : l.nodeDetailHopsUnknown,
              ),
            // The route the last advert took, from the radio's own record
            // (`CMD_GET_ADVERT_PATH` 0x2A). A trace reports the route a packet
            // took now and costs airtime; this answers "which repeaters hear
            // this node at all" with no mesh traffic, so it is offered as a
            // read rather than fetched for every node opened.
            if (!widget.isSelf) _AdvertPathLine(node: n),
            if (!widget.isSelf) _FindRouteLine(node: n),
            if (!widget.isSelf) _ShareContactLine(node: n),
            // Blocking, on the node itself. It is the same decision the message
            // sheet offers, and this is the screen where a reader knows who they
            // are looking at.
            if (!widget.isSelf)
              _BlockLine(node: n, mc: mc),
            if (!widget.isSelf &&
                (n.type == kAdvTypeRepeater || n.type == kAdvTypeRoom))
              _RepeaterSessionBlock(node: n),
            // R47 — peer telemetry on tap. CMD_SEND_TELEMETRY_REQ goes
            // to the device, which unicasts to the peer over the air;
            // the peer's response arrives async and lands in the
            // controller's _telemetry cache (keyed by pubkey6).
            // Self-telemetry already polled on every ready, so no
            // button needed there.
            _TelemetrySection(node: n, isSelf: widget.isSelf, kv: kv),
            if (!widget.isSelf)
              _ContactTelemetryShareSection(node: n),
            if (widget.isSelf) ...<Widget>[
              const SizedBox(height: 8),
              Text(l.nodeDetailSelf,
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                      fontSize: context.skin.type.sizeBody)),
            ],
            // Option D — RECENT DMS excerpt. Suppressed for own node.
            if (!widget.isSelf && widget.recentDms.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text(l.nodeDetailRecentDms,
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: context.skin.type.sizeSm,
                      letterSpacing: 3)),
              const SizedBox(height: 6),
              for (final ChatMessage m
                  in widget.recentDms.length > 3
                      ? widget.recentDms.sublist(
                          widget.recentDms.length - 3)
                      : widget.recentDms)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: _timeGutter,
                        child: Text(
                          '${m.at.hour.toString().padLeft(2, '0')}:'
                          '${m.at.minute.toString().padLeft(2, '0')} '
                          '${m.outgoing ? '»' : '«'}',
                          style: TextStyle(
                              color: m.outgoing
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                              fontFamily: context.skin.type.monoFamily,
                              fontSize: context.skin.type.sizeSm),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          m.text.length > 64
                              ? '${m.text.substring(0, 64)}…'
                              : m.text,
                          style: TextStyle(
                              color: cs.onSurface, fontSize: context.skin.type.sizeBody),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            // R28 — Tags row. Renders an existing-chip strip + a
            // "+ tag" input chip. Hidden entirely when no tags AND
            // no onAddTag — keeps the sheet quiet in read-only
            // contexts (e.g. peer-summary embeds we might add later).
            if (_localTags.isNotEmpty || widget.onAddTag != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(l.nodeDetailTags,
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: context.skin.type.sizeSm,
                      letterSpacing: 2)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final String t in _localTags)
                    InputChip(
                      label: Text(t),
                      onDeleted: widget.onRemoveTag == null
                          ? null
                          : () => _removeTag(t),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (widget.onAddTag != null)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(l.nodeDetailAddTag),
                      onPressed: () => _promptAddTag(l),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (!widget.isSelf)
              Row(
              children: <Widget>[
                if (!widget.cameFromDm) ...<Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.send),
                      label: Text(l.nodeDetailMessage),
                      onPressed: () {
                        Navigator.pop(context);
                        context.push('/dm/${n.pubKeyHex}');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(_fav ? Icons.star : Icons.star_border),
                    label: Text(_fav
                        ? l.nodeDetailContact
                        : l.nodeDetailFavourite),
                    onPressed: _toggle,
                  ),
                ),
              ],
            ),
            // R58 — give this peer its own arrival sound + vibration.
            if (!widget.isSelf) ...<Widget>[
              const SizedBox(height: 16),
              _SignaturePicker(pubKeyHex: n.pubKeyHex),
            ],
            // R59 — the bot can answer this peer's DMs.
            if (!widget.isSelf) ...<Widget>[
              const SizedBox(height: 8),
              BotSection(scope: DmScope(n.pubKeyHex)),
            ],
            // R57 — a node we've heard but the *radio* doesn't have as a
            // contact can't be DM'd (channel works; DMs route via the
            // device contact list). Offer to push it so DMs reach it.
            if (!widget.isSelf &&
                n.pubKeyHex.length == 64 &&
                !mc.isSyncedContact(n.pubKeyHex)) ...<Widget>[
              const SizedBox(height: 8),
              // A callout, not a pill: this block is a paragraph with an
              // action, so it keeps both the tint and the hairline. Tint-only
              // is the rule for tags (see `chip` above); a callout needs its
              // edge because it is the same weight as the page around it.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.tertiary.withValues(alpha: .10),
                  borderRadius: mmRadius(context, 10),
                  border: Border.all(color: cs.tertiary.withValues(alpha: .4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l.nodeDetailNotDeviceContact,
                        style: TextStyle(
                            color: cs.onSurface, fontSize: context.skin.type.sizeBodyLg, height: 1.35)),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.person_add_alt, size: 18),
                        label: Text(l.nodeDetailAddDeviceContact),
                        onPressed: () => _addDeviceContact(mc, n, l),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // "Show on map" — opens the platform's mapping app
            // (Apple Maps on iOS, Google Maps web URL elsewhere)
            // pinned at the node's lat/lon. Disabled if the node
            // doesn't have a known location yet.
            const SizedBox(height: 6),
            OutlinedButton.icon(
              icon: const Icon(Icons.map_outlined),
              label: Text(l.nodeDetailShowOnMap),
              onPressed: n.hasLocation
                  ? () => _openInMaps(context, n, l)
                  : null,
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: Text(l.nodeDetailCopyPubkey),
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: n.pubKeyHex));
                if (!context.mounted) return;
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(
                    content: Text(l.nodeDetailPubkeyCopied),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            // R56 — manual escape hatch: if a contact came back under a
            // new key (auto-detect can miss it when the saved name differs
            // from the advert), let the user link the two explicitly.
            if (!widget.isSelf)
              TextButton.icon(
                icon: const Icon(Icons.link, size: 16),
                label: Text(l.nodeIdentityLinkAction),
                onPressed: () => _promptLinkKey(mc, n, l),
              ),
            // Remove from the radio's contact table — frees a slot (the
            // table is finite; a full one blocks adding a re-homed key).
            if (!widget.isSelf &&
                n.pubKeyHex.length == 64 &&
                mc.isSyncedContact(n.pubKeyHex))
              TextButton.icon(
                icon: Icon(Icons.person_remove_alt_1,
                    size: 16, color: cs.error),
                label: Text(l.nodeDetailRemoveDeviceContact,
                    style: TextStyle(color: cs.error)),
                onPressed: () => _removeDeviceContact(mc, n, l),
              ),
          ],
        ),
      ),
      ),
    );
  }

  /// Open the platform's mapping app at the node's pin. iOS goes
  /// to Apple Maps natively (`maps.apple.com/?ll=LAT,LON&q=NAME`),
  /// everything else gets Google Maps via web URL (works whether
  /// or not the Google Maps app is installed — the OS resolves
  /// it).
  Future<void> _openInMaps(
      BuildContext context, DiscoveredNode n, AppLocalizations l) async {
    final String lat = n.latitude!.toStringAsFixed(6);
    final String lon = n.longitude!.toStringAsFixed(6);
    final String label = Uri.encodeQueryComponent(
        n.name.isEmpty ? n.shortId : n.name);
    // iOS prefers Apple Maps; with no macOS runner the only Apple target left
    // is iOS, so the check names just that.
    final bool isApple = !kIsWeb && Platform.isIOS;
    final Uri uri = isApple
        ? Uri.parse('https://maps.apple.com/?ll=$lat,$lon&q=$label')
        : Uri.parse('https://www.google.com/maps?q=$lat,$lon');
    final bool ok =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(l.nodeDetailShowOnMapFailed),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}

/// R54 follow-on — grant this *contact* permission to read our
/// telemetry. Only relevant when the device's telemetry mode is
/// "Contacts" (ALLOW_FLAGS); writes the per-contact flag bits via
/// ADD_UPDATE_CONTACT. Hidden for advert-only (non-contact) nodes,
/// since telemetry is contact-only.
class _ContactTelemetryShareSection extends StatelessWidget {
  const _ContactTelemetryShareSection({required this.node});

  final DiscoveredNode node;

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Contact? c = mc.contactRecordFor(node.pubKeyHex);
    if (c == null) return const SizedBox.shrink();

    Widget row(String label, bool value, void Function(bool) onChanged) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text(label, style: TextStyle(fontSize: context.skin.type.sizeBodyLg)),
          value: value,
          onChanged: onChanged,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Text(l.nodeDetailShareTelemetryTitle,
            style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: context.skin.type.sizeBody,
                letterSpacing: 1)),
        Text(l.nodeDetailShareTelemetryHelp,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeSm)),
        row(l.otherTelemetryBase, c.allowsTelemBase,
            (bool v) => mc.setContactTelemetryPermissions(node.pubKeyHex,
                base: v)),
        row(l.otherTelemetryLoc, c.allowsTelemLocation,
            (bool v) => mc.setContactTelemetryPermissions(node.pubKeyHex,
                location: v)),
        row(l.otherTelemetryEnv, c.allowsTelemEnvironment,
            (bool v) => mc.setContactTelemetryPermissions(node.pubKeyHex,
                environment: v)),
      ],
    );
  }
}

/// The active counterpart to the advert-path row: ask the mesh for a route.
///
/// It floods a discovery request and whichever repeaters answer return the
/// outbound and inbound paths they found, so a route that did not exist a
/// minute ago can come back. It costs airtime, which is why it is a tap and not
/// something the sheet does on open.
class _FindRouteLine extends StatefulWidget {
  const _FindRouteLine({required this.node});
  final DiscoveredNode node;

  @override
  State<_FindRouteLine> createState() => _FindRouteLineState();
}

class _FindRouteLineState extends State<_FindRouteLine> {
  bool _busy = false;
  bool _asked = false;
  PathDiscoveryResult? _result;

  Future<void> _read() async {
    if (_busy) return;
    setState(() => _busy = true);
    final MeshcoreController mc = context.read<MeshcoreController>();
    final PathDiscoveryResult? r =
        await mc.discoverPathFor(widget.node.pubKeyHex);
    if (!mounted) return;
    setState(() {
      _result = r;
      _busy = false;
      _asked = true;
    });
  }

  /// The hops of one direction, named where a hash names exactly one node.
  ///
  /// [nodes] is read once by the caller rather than once per hop: the list is
  /// the radio's whole contact table, and a five-hop path used to walk it five
  /// times inside a build.
  String _hops(PathLen len, Uint8List path, List<DiscoveredNode> nodes) {
    if (path.isEmpty) return '';
    final List<String> out = <String>[];
    final int size = len.hashSize;
    for (int i = 0; i + size <= path.length; i += size) {
      final String hex = path
          .sublist(i, i + size)
          .map((int b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      out.add(hopLabel(hex, hopNodeName(nodes, hex)));
    }
    return out.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final PathDiscoveryResult? r = _result;
    final String value;
    if (!_asked) {
      value = l.nodeFindRouteHint;
    } else if (r == null) {
      value = l.nodeFindRouteNone;
    } else {
      final List<DiscoveredNode> nodes =
          context.read<MeshcoreController>().nodes;
      final String out = _hops(r.outPathLen, r.outPath, nodes);
      final String back = _hops(r.inPathLen, r.inPath, nodes);
      // Both directions come back in one reply, and the interesting case is
      // when they differ: that is an asymmetric link, and hiding it would
      // throw away half the answer.
      value = out.isEmpty
          ? l.nodeFindRouteDirect
          : back.isEmpty || back == out
              ? out
              : '$out\n${l.nodeFindRouteTwoWay(back)}';
    }
    return InkWell(
      onTap: _busy ? null : _read,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: kvLabelWidth(context),
              child: Text(l.nodeFindRoute,
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: context.skin.type.sizeSm)),
            ),
            const SizedBox(width: _kKvGap),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: cs.onSurface,
                      fontFamily: context.skin.type.monoFamily,
                      fontSize: context.skin.type.sizeBody)),
            ),
            Icon(Icons.route_outlined, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Share this contact as a link the other side can import.
///
/// The radio exports the contact's own advert packet (`CMD_EXPORT_CONTACT`,
/// 0x11), and that packet is what `meshcore://<hex>` carries, so the link works
/// in any MeshCore client rather than only this one. Copied rather than sent:
/// the app has a file share channel and no text one, and a copied link can be
/// pasted into whichever chat the user is already in.
class _ShareContactLine extends StatefulWidget {
  const _ShareContactLine({required this.node});
  final DiscoveredNode node;

  @override
  State<_ShareContactLine> createState() => _ShareContactLineState();
}

class _ShareContactLineState extends State<_ShareContactLine> {
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final MeshcoreController mc = context.read<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final ScaffoldMessengerState sm = ScaffoldMessenger.of(context);
    final String? link = await mc.exportContactLink(widget.node.pubKeyHex);
    if (!mounted) return;
    setState(() => _busy = false);
    if (link == null) {
      sm
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.nodeShareContactFailed)));
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    sm
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
          content: Text('${l.shareLinkSheetTitle} · ${l.shareLinkCopied}')));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _busy ? null : _share,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: kvLabelWidth(context),
              child: Text(l.nodeShareContact,
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: context.skin.type.sizeSm)),
            ),
            const SizedBox(width: _kKvGap),
            Expanded(
              child: Text(l.nodeShareContactHint,
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: context.skin.type.sizeBody)),
            ),
            Icon(Icons.ios_share, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}


/// Block or unblock this node, on the row that names it.
///
/// The app could only ever *unblock*: `BlockStore.block` had no caller, so the
/// blocked-keys screen explained a feature nothing in the app could reach. This
/// is the second place the offer belongs — the other is the message action sheet,
/// where a reader decides not to hear from someone again — and the label follows
/// the state, because a row that says "Block" for an already-blocked key is a row
/// that does nothing.
class _BlockLine extends StatefulWidget {
  const _BlockLine({required this.node, required this.mc});
  final DiscoveredNode node;
  final MeshcoreController mc;

  @override
  State<_BlockLine> createState() => _BlockLineState();
}

class _BlockLineState extends State<_BlockLine> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final BlockStore? store = context.watch<BlockStore?>();
    final bool blocked = store?.isBlocked(widget.node.pubKeyHex) ?? false;
    return InkWell(
      key: const ValueKey<String>('node-block-line'),
      onTap: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                if (blocked) {
                  await store?.unblock(widget.node.pubKeyHex);
                } else {
                  await confirmAndBlock(context,
                      pubKeyHex: widget.node.pubKeyHex,
                      name: widget.node.name.isEmpty
                          ? null
                          : widget.node.name);
                }
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: kvLabelWidth(context),
              child: Text(l.actionBlock,
                  style: TextStyle(
                      color: blocked ? cs.primary : cs.onSurfaceVariant,
                      fontSize: context.skin.type.sizeSm)),
            ),
            const SizedBox(width: _kKvGap),
            Expanded(
              // The value column carries the state, not the reasoning. It used
              // to hold a whole sentence about what a block does and does not
              // stop, which is the dialog's job: a reader scanning for a fact
              // read documentation instead, in a column that exists for values.
              child: Text(
                  blocked ? l.blockedKeysUnblock : l.blockedKeysCannotStopShort,
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: context.skin.type.sizeBody)),
            ),
            Icon(blocked ? Icons.lock_open : Icons.block,
                size: 16,
                color: blocked ? cs.primary : cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// A repeater session: sign in with the repeater's own password, see what it
/// granted, and sign out.
///
/// The password is not stored anywhere: it is sent once, and the block only
/// remembers whether this sheet signed in. What a session permits is the
/// repeater's business (`permissions`), so it is reported, not interpreted.
/// A command console is the natural next step and is not built: the codec has no
/// `CMD_RUN_CLI_COMMAND` builder yet.
class _RepeaterSessionBlock extends StatefulWidget {
  const _RepeaterSessionBlock({required this.node});
  final DiscoveredNode node;

  @override
  State<_RepeaterSessionBlock> createState() => _RepeaterSessionBlockState();
}

class _RepeaterSessionBlockState extends State<_RepeaterSessionBlock> {
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  LoginResult? _session;
  String? _message;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    final MeshcoreController mc = context.read<MeshcoreController>();
    final LoginResult? r =
        await mc.loginRepeater(widget.node.pubKeyHex, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _session = r != null && r.success ? r : null;
      _message = r == null
          ? l.repeaterNoAnswer
          : r.success
              ? null
              : l.repeaterRefused;
      _password.clear();
    });
  }

  Future<void> _signOut() async {
    if (_busy) return;
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() => _busy = true);
    await context.read<MeshcoreController>().logoutRepeater(widget.node.pubKeyHex);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _session = null;
      _message = l.repeaterSignOutDone;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool ready = context.watch<MeshcoreController>().isReady && !_busy;
    final LoginResult? s = _session;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l.repeaterSession,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: context.skin.type.sizeSm,
                  letterSpacing: 2)),
          const SizedBox(height: 4),
          if (s == null) ...<Widget>[
            Text(l.repeaterSessionIntro,
                style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: context.skin.type.sizeBody)),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('repeater-password'),
                    controller: _password,
                    enabled: ready,
                    obscureText: true,
                    maxLength: kLoginPasswordMax,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l.repeaterPasswordHint,
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                MmAction(
                  label: l.repeaterSignIn,
                  onPressed: !ready || _password.text.isEmpty ? null : _signIn,
                ),
              ],
            ),
          ] else ...<Widget>[
            Text(l.repeaterSignedIn(s.permissions.toRadixString(16)),
                style: TextStyle(
                    color: cs.onSurface,
                    fontFamily: context.skin.type.monoFamily)),
            Align(
              alignment: Alignment.centerLeft,
              child: MmAction(
                label: l.repeaterSignOut,
                onPressed: ready ? _signOut : null,
              ),
            ),
          ],
          if (_message != null)
            Text(_message!,
                style: TextStyle(color: cs.error, fontSize: context.skin.type.sizeSm)),
        ],
      ),
    );
  }
}

/// Width of the key column in the sheet's key/value rows, so every row's value
/// starts at the same offset. One place, because the advert-path row has to
/// line up with the rows the sheet builds itself.
///
/// It grows with the text scale, because the column is aligned by *measuring*
/// the keys: at 1.3 text a fixed 84 dp put "Find the route" hard against the
/// sentence after it, and the row read "Find the routeAsks the mesh; costs
/// airtime."
double kvLabelWidth(BuildContext context) =>
    84 * MediaQuery.textScalerOf(context).scale(1);

/// The gap between the key column and the value. The key column is aligned by
/// design, so a key that fills it has nothing left to separate it from its own
/// value.
const double _kKvGap = 8;

/// The route the contact's last advert arrived by, read on demand.
///
/// The reply carries no key, so the controller allows one request at a time;
/// this asks once per tap and says what came back, including "the radio has no
/// advert route", which is the honest answer for a node heard directly or not
/// heard since the radio started.
class _AdvertPathLine extends StatefulWidget {
  const _AdvertPathLine({required this.node});
  final DiscoveredNode node;

  @override
  State<_AdvertPathLine> createState() => _AdvertPathLineState();
}

class _AdvertPathLineState extends State<_AdvertPathLine> {
  bool _reading = false;
  bool _asked = false;
  AdvertPath? _path;

  Future<void> _read() async {
    if (_reading) return;
    setState(() => _reading = true);
    final MeshcoreController mc = context.read<MeshcoreController>();
    final AdvertPath? p = await mc.advertPathFor(widget.node.pubKeyHex);
    if (!mounted) return;
    setState(() {
      _path = p;
      _reading = false;
      _asked = true;
    });
  }

  /// A hop of the route the contact's last advert took.
  String _name(int hash, int width, List<DiscoveredNode> nodes) {
    final String h = hash.toRadixString(16).padLeft(width * 2, '0');
    return hopLabel(h, hopNodeName(nodes, h));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AdvertPath? p = _path;
    final List<DiscoveredNode> nodes =
        context.read<MeshcoreController>().nodes;
    final String value = !_asked
        ? '—'
        : _reading
            ? l.nodeAdvertPathReading
            : p == null
                ? l.nodeAdvertPathNone
                // A zero-length path is not "no route": it is the neighbour in
                // radio range, and saying which is the honest answer.
                : p.path.isEmpty
                    ? l.deviceContactsDirect
                    : <String>[
                        for (int i = 0;
                            i + p.pathLen.hashSize <= p.path.length;
                            i += p.pathLen.hashSize)
                          _name(
                              p.path
                                  .sublist(i, i + p.pathLen.hashSize)
                                  .fold<int>(
                                      0, (int a, int b) => (a << 8) | b),
                              p.pathLen.hashSize,
                              nodes),
                      ].join(' · ');
    return InkWell(
      onTap: _reading ? null : _read,
      // A tap target, so it is 48dp tall like every other control: the row is
      // a read action, not a line of prose.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: kvLabelWidth(context),
              child: Text(l.nodeAdvertPath,
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: context.skin.type.sizeSm)),
            ),
            const SizedBox(width: _kKvGap),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: cs.onSurface,
                      fontFamily: context.skin.type.monoFamily,
                      fontSize: context.skin.type.sizeBody)),
            ),
            Icon(Icons.download_outlined,
                size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// R47 — telemetry section inside the node detail sheet. Reads the
/// controller's `_telemetry` cache via Provider so it rebuilds when a
/// 0x8B push lands. For non-self nodes also offers a button that
/// fires `CMD_SEND_TELEMETRY_REQ` over the air; that path is OTA
/// (seconds, not instant) so the section shows a spinner while
/// waiting.
class _TelemetrySection extends StatelessWidget {
  const _TelemetrySection({
    required this.node,
    required this.isSelf,
    required this.kv,
  });

  final DiscoveredNode node;
  final bool isSelf;
  final Widget Function(String, String) kv;

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final NodeTelemetry? t =
        mc.telemetryFor(node.pubKeyHex);
    final bool querying = mc.isQueryingTelemetry(node.pubKeyHex);

    // Compact age string ("2 min ago", "3 h ago", …) for the receipt
    // line. We reuse the same _ago bands as last-heard so the sheet
    // reads consistently.
    String ageOf(DateTime at) {
      final int delta =
          DateTime.now().millisecondsSinceEpoch ~/ 1000 -
              at.millisecondsSinceEpoch ~/ 1000;
      if (delta < 60) return l.nodeDetailAgoSeconds(delta);
      if (delta < 3600) return l.nodeDetailAgoMinutes((delta / 60).floor());
      if (delta < 86400) {
        return l.nodeDetailAgoHours((delta / 3600).floor());
      }
      return l.nodeDetailAgoDays((delta / 86400).floor());
    }

    final List<Widget> children = <Widget>[];

    // A node that answered telemetry without an altitude has no GPS fix, which
    // is a different fact from "not asked yet": the row stays and says it was
    // not reported, so the absence is information rather than a gap.
    if (t != null && t.altitudeMeters == null) {
      children.add(kv(
          l.nodeDetailAltitudeKv, l.nodeDetailAltitudeNotReported));
    } else if (t?.altitudeMeters != null) {
      children.add(kv(
          l.nodeDetailAltitudeKv,
          l.nodeDetailAltitudeMeters(
              t!.altitudeMeters!.toStringAsFixed(1))));
    }

    // Environment sensors (BME280 etc.) — present only when the node
    // reports them in its telemetry.
    if (t?.temperatureC != null) {
      children.add(kv(l.nodeDetailTempKv,
          l.nodeDetailTempValue(t!.temperatureC!.toStringAsFixed(1))));
    }
    if (t?.humidityPct != null) {
      children.add(kv(l.nodeDetailHumidityKv,
          l.nodeDetailHumidityValue(t!.humidityPct!.toStringAsFixed(0))));
    }
    if (t?.pressureHpa != null) {
      children.add(kv(l.nodeDetailPressureKv,
          l.nodeDetailPressureValue(t!.pressureHpa!.toStringAsFixed(0))));
    }
    if (t?.luminosity != null) {
      children.add(
          kv(l.nodeDetailLuminosityKv, t!.luminosity!.toStringAsFixed(0)));
    }

    if (t != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: Text(
          l.nodeDetailTelemetryAge(ageOf(t.receivedAt)),
          style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: context.skin.type.sizeSm,
              fontStyle: FontStyle.italic),
        ),
      ));
    }

    if (!isSelf) {
      children.add(const SizedBox(height: 4));
      // Peer-telemetry requires the target to be a *synced contact*
      // on our device — the firmware does lookupContactByPubKey and
      // silently drops the request if the peer is only advert-heard.
      // outPathHashes != null is our reliable "is a contact" signal
      // (path info only arrives via ContactFrame). When it's null,
      // explain why the query can't fire instead of offering a
      // button that does nothing.
      final bool isContact = node.outPathHashes != null;
      if (!isContact) {
        children.add(Text(
          l.nodeDetailTelemetryNotContact,
          style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: context.skin.type.sizeBody,
              fontStyle: FontStyle.italic),
        ));
      } else if (querying) {
        children.add(Row(
          children: <Widget>[
            SizedBox(
                width: context.skin.space.step(5) +
                    context.skin.space.insideText,
                height: context.skin.space.step(5) +
                    context.skin.space.insideText,
                child: const CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(l.nodeDetailTelemetryQuerying,
                style: TextStyle(
                    color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeBody)),
          ],
        ));
      } else {
        children.add(OutlinedButton.icon(
          icon: const Icon(Icons.terrain, size: 18),
          label: Text(t == null
              ? l.nodeDetailQueryTelemetry
              : l.nodeDetailRefreshTelemetry),
          onPressed: mc.isReady
              ? () => unawaited(
                  mc.requestPeerTelemetry(node.pubKeyHex))
              : null,
        ));
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// R28 — modal text-entry dialog with previously-used tags as chip
/// suggestions. Returning [Navigator.pop]'s argument is the new tag
/// (or null on cancel).
class _AddTagDialog extends StatefulWidget {
  const _AddTagDialog({
    required this.existing,
    required this.suggestions,
    required this.l,
  });
  final List<String> existing;
  final List<String> suggestions;
  final AppLocalizations l;

  @override
  State<_AddTagDialog> createState() => _AddTagDialogState();
}

class _AddTagDialogState extends State<_AddTagDialog> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool _isExisting(String s) => widget.existing
      .any((String e) => e.toLowerCase() == s.trim().toLowerCase());

  void _submit() {
    final String t = _input.text.trim();
    if (t.isEmpty) return;
    if (_isExisting(t)) {
      Navigator.pop(context); // already attached — nothing to do
      return;
    }
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = widget.l;
    // Filter suggestions: don't suggest tags already on the node.
    final List<String> unusedSuggestions = <String>[
      for (final String s in widget.suggestions)
        if (!_isExisting(s)) s,
    ];
    return AlertDialog(
      title: Text(l.nodeDetailAddTagTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _input,
            autofocus: true,
            decoration: InputDecoration(
                hintText: l.nodeDetailAddTagHint,
                isDense: true),
            onSubmitted: (_) => _submit(),
            maxLength: 32,
          ),
          if (unusedSuggestions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(l.nodeDetailAddTagSuggestions,
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final String s in unusedSuggestions)
                  ActionChip(
                    label: Text(s),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context, s),
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l.nodeDetailAddTagApply),
        ),
      ],
    );
  }
}

/// R56 — the "returning contact" reconcile prompt. Shown in the node
/// sheet when a same-name node's key changed; moving is user-confirmed.
class _ReconcileCard extends StatelessWidget {
  const _ReconcileCard({required this.match, required this.onMove});

  final IdentityMatch match;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.tertiary.withValues(alpha: .10),
        borderRadius: mmRadius(context, 10),
        border: Border.all(color: cs.tertiary.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.sync_problem, size: 16, color: cs.tertiary),
              const SizedBox(width: 6),
              Text(l.nodeIdentityTitle,
                  style: TextStyle(
                      color: cs.tertiary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l.nodeIdentityBody(match.fresh.name, match.messageCount),
            style: TextStyle(color: cs.onSurface, height: 1.35, fontSize: context.skin.type.sizeBodyLg),
          ),
          const SizedBox(height: 4),
          Text(
            l.nodeIdentityOldKey(match.stale.shortId),
            style: TextStyle(
                color: cs.onSurfaceVariant,
                fontFamily: context.skin.type.monoFamily,
                fontSize: context.skin.type.sizeSm),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: onMove,
              icon: const Icon(Icons.move_up, size: 18),
              label: Text(l.nodeIdentityAction),
            ),
          ),
        ],
      ),
    );
  }
}

/// Picker for the manual key-link flow: choose the node that is the same
/// contact under a new key. Pre-filtered by the contact's name (the list
/// of all fabric nodes is otherwise too long); the search is editable, so
/// clearing it broadens to everything.
class _LinkPicker extends StatefulWidget {
  const _LinkPicker({
    required this.candidates,
    required this.contactName,
    required this.ago,
    required this.l,
  });

  final List<DiscoveredNode> candidates;
  final String contactName;
  final String Function(int, AppLocalizations) ago;
  final AppLocalizations l;

  @override
  State<_LinkPicker> createState() => _LinkPickerState();
}

class _LinkPickerState extends State<_LinkPicker> {
  late final TextEditingController _q =
      TextEditingController(text: widget.contactName.trim());

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = widget.l;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String name = widget.contactName.trim().toLowerCase();
    final String query = _q.text.trim().toLowerCase();
    // A pasted public key (separators stripped, letters NEVER) — used both
    // to match a fabric node by key and to offer a direct link.
    final String? manualKey = parsePastedPubKey(_q.text);
    final List<DiscoveredNode> filtered = <DiscoveredNode>[
      for (final DiscoveredNode c in widget.candidates)
        if (query.isEmpty ||
            c.name.toLowerCase().contains(query) ||
            (manualKey != null &&
                c.pubKeyHex.toLowerCase().contains(manualKey)))
          c
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l.nodeIdentityLinkTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l.nodeIdentityLinkHelp,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: context.skin.type.sizeBodyLg)),
            const SizedBox(height: 12),
            TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: l.nodeIdentityLinkSearchHint,
                border: const OutlineInputBorder(),
                suffixIcon: _q.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l.nodesClearSearch,
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _q.clear()),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            // Direct link to a typed/pasted public key — the reliable path
            // when the new node isn't in the fabric (chat-only / unheard).
            if (manualKey != null)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.vpn_key, color: cs.primary),
                title: Text(l.nodeIdentityLinkUseKey),
                subtitle: Text(
                    '…${manualKey.substring(0, manualKey.length < 16 ? manualKey.length : 16)}',
                    style: TextStyle(
                        fontFamily: context.skin.type.monoFamily, fontSize: context.skin.type.sizeSm)),
                onTap: () => Navigator.pop(
                    context, _LinkTarget(pubKeyHex: manualKey)),
              ),
            if (manualKey != null && filtered.isNotEmpty)
              const Divider(height: 1),
            if (filtered.isEmpty && manualKey == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                    widget.candidates.isEmpty
                        ? l.nodeIdentityLinkEmpty
                        : l.nodeIdentityLinkNoMatch,
                    style: TextStyle(color: cs.onSurfaceVariant)),
              )
            else if (filtered.isNotEmpty)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext _, int i) {
                    final DiscoveredNode c = filtered[i];
                    final bool same =
                        c.name.trim().toLowerCase() == name && name.isNotEmpty;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          same ? Icons.person_search : Icons.cell_tower,
                          color: same ? cs.primary : cs.onSurfaceVariant),
                      title: Text(c.name.isEmpty ? c.shortId : c.name,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '…${c.shortId.substring(0, 6)} · ${widget.ago(c.lastHeardUnix, l)}',
                          style: TextStyle(
                              fontFamily: context.skin.type.monoFamily, fontSize: context.skin.type.sizeSm)),
                      onTap: () => Navigator.pop(context,
                          _LinkTarget(pubKeyHex: c.pubKeyHex, displayName: c.name)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Result of the link picker: a chosen node or a typed/pasted key.
class _LinkTarget {
  _LinkTarget({required this.pubKeyHex, this.displayName});
  final String pubKeyHex;
  final String? displayName;
}

/// Extract a pasteable public key from the picker's search text. Strips
/// only separators (space / colon / dash / underscore) — NEVER letters —
/// so the seeded contact name can't pollute a pasted key (a name like
/// "Davi1" must not contribute its hex letters). Accepts 12–64 hex chars;
/// returns null otherwise (so a plain name search never reads as a key).
String? parsePastedPubKey(String query) {
  final String hex =
      query.trim().toLowerCase().replaceAll(RegExp(r'[\s:_\-]'), '');
  return RegExp(r'^[0-9a-f]{12,64}$').hasMatch(hex) ? hex : null;
}

/// R58 — pick this peer's arrival signature.
///
/// Selecting a slot immediately **plays** it. That is the whole point:
/// a signature has to be recognised, not read, so the only useful way
/// to choose one is to feel the alternatives back to back. The chip
/// label is a number rather than a name because the pack decides what
/// the slot sounds and feels like — naming it "chirp" here would be a
/// lie under five of the six themes.
class _SignaturePicker extends StatelessWidget {
  const _SignaturePicker({required this.pubKeyHex});

  final String pubKeyHex;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final PeerProfiles peers = context.watch<PeerProfiles>();
    final ThemeController theme = context.watch<ThemeController>();
    final CueKind? current = peers.signatureFor(pubKeyHex);
    final bool audioMuted = !theme.audioMaster || theme.visualHapticOnly;

    void choose(CueKind? slot) {
      unawaited(peers.setSignature(pubKeyHex, slot));
      // Play what was just chosen, so picking and auditioning are the
      // same gesture. `playSignature(null)` is the ordinary DM cue,
      // which is exactly what "Default" should preview.
      unawaited(context.read<CueService>().playSignature(slot));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l.nodeDetailSignature,
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 2),
        Text(
          l.nodeDetailSignatureHint,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        if (audioMuted) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            l.nodeDetailSignatureMutedHint,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.error),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            MmChoiceChip(
              label: Text(l.nodeDetailSignatureNone),
              selected: current == null,
              onSelected: (_) => choose(null),
            ),
            for (int i = 0; i < kSignatureSlots.length; i++)
              MmChoiceChip(
                label: Text(l.nodeDetailSignatureSlot(i + 1)),
                selected: current == kSignatureSlots[i],
                onSelected: (_) => choose(kSignatureSlots[i]),
              ),
          ],
        ),
      ],
    );
  }
}
