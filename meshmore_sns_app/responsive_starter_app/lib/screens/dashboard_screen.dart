// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/mesh_event.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/own_location.dart';
import '../theme/mm_skin.dart';
import 'dashboards/my_pubkey_line.dart';
import '../ui/mm_components.dart';
import '../meshcore/region_presets.dart';
import '../ui/mm_audio_toggle.dart';
import '../ui/mm_collapse_controller.dart';
import '../ui/mm_collapsible.dart';
import 'device_manager_sheet.dart';
import '../ui/mm_shape.dart';
import '../util/mm_format.dart';

/// R8 home — "SEELE Monolith" dashboard: one dominant numeral
/// (peers in range), a full-width status slab that colour-inverts on
/// alert, a terse radio readout, and the recent-activity feed. Pure
/// token styling so every theme preset re-skins it.
/// Identifies the dashboard body to tests, now that the view name is not
/// drawn here.
const Key dashboardKey = ValueKey<String>('dashboard');

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  ({String label, bool alert, bool busy}) _status(
      MeshcoreController mc, AppLocalizations l) {
    return switch (mc.state) {
      // The app bar's chip already says "linked" on every view, so the slab
      // says which radio instead of repeating the word. Two places stating the
      // same fact in the same words is the redundancy the header rewrite
      // removed one block above this line.
      MeshcoreConnectionState.ready => (
          label: mc.pairedName ?? l.statusLinked,
          alert: false,
          busy: false
        ),
      MeshcoreConnectionState.handshaking => (
          label: l.statusHandshaking,
          alert: false,
          busy: true
        ),
      MeshcoreConnectionState.reconnecting => (
          label: l.statusReconnecting,
          alert: true,
          busy: true
        ),
      MeshcoreConnectionState.failed => (
          label: l.statusLinkLost,
          alert: true,
          busy: false
        ),
      MeshcoreConnectionState.disconnected => (
          label: mc.isConnecting ? l.statusConnecting : l.statusOffline,
          alert: !mc.isConnecting,
          busy: mc.isConnecting,
        ),
    };
  }

  /// The gap before a block that starts a subject.
  ///
  /// The monolith left this to whichever block happened to follow: the peers
  /// block asked for a gap and the collapsible sections asked for none, so the
  /// space under the status slab, between the peers count and RADIO, and
  /// between the sections were three different distances. Every block below
  /// the slab now starts with this one gap.
  Widget _blockGap(BuildContext context) =>
      SizedBox(height: context.skin.space.sectionGap);

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);
    final int inRange = mc.nodes.where((DiscoveredNode n) {
      final NodeProximity p = mc.proximityFor(n);
      return p == NodeProximity.near || p == NodeProximity.recent;
    }).length;
    final ({String label, bool alert, bool busy}) st = _status(mc, l);
    final SelfInfo? selfInfo = mc.selfInfo;
    // R97 — a live link is green in every skin. `ok` is per-preset and not
    // green in most of them; the accent here was not a link signal at all.
    final Color statusColor = st.alert
        ? cs.onError
        : (mc.state == MeshcoreConnectionState.ready
            ? context.skin.color.link
            : cs.primary);

    // One screen, one telling. The link state is the slab and nothing else:
    // the banner carries only the states the slab cannot (storage, clock,
    // battery), and the blocks below appear as they gain a value, so a fresh
    // install is a link state and one action rather than eight placeholders.
    final bool hasPeers = inRange > 0 || mc.nodes.isNotEmpty;
    final bool hasRadio = selfInfo != null || mc.pairedName != null;
    final OwnLocation? loc = mc.ownLocation;

    return ListView(
      // A stable marker for tests: the dashboard no longer carries a title
      // row of its own (the strip says which view is showing), so the body
      // has to identify itself.
      padding: context.skin.space.padScreen,
      children: <Widget>[
        // APP-N4's banner is above this layout, in `DashboardHost`: the facts
        // are the same on every preset, and building it here made a
        // storage-full warning visible on this one layout only.

        if (hasPeers) ...<Widget>[
          Text(
              mc.state == MeshcoreConnectionState.ready
                  ? l.dashboardPeersInRange
                  : l.dashboardPeersInRangeStale,
              style: mmSectionLabelStyle(context.skin)),
          // The one dominant numeral on the screen. It scales with the skin
          // and with the user's text size up to a point, past which it would
          // take the width it is supposed to dominate from.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Text('$inRange',
                style: TextStyle(
                    fontFamily: context.skin.type.monoFamily,
                    color: cs.onSurface,
                    fontSize: context.skin.type.sizeHero * 1.5,
                    height: 1.0,
                    fontWeight: FontWeight.w300)),
          ),
          SizedBox(height: context.skin.space.labelToControl),
          Text(
              mc.deviceContactCount == null
                  ? l.dashboardKnownCount(mc.nodes.length)
                  : l.dashboardKnownAndContacts(
                      mc.nodes.length, _contactsLabel(mc)),
              style: TextStyle(color: cs.onSurfaceVariant)),
        ],

        // Status slab — colour-inverts to error on alert. The audio toggle
        // sits beside it rather than inside it: a mute is not a link state, and
        // an accidental mute inside a status display reads as a change to the
        // link. It sits *after* the numeral because that is this skin's own
        // arrangement: the monolith leads with the number, and the slab answers
        // "linked to what" underneath it.
        _blockGap(context),
        Row(
          // Centred, not top-aligned: an `IconButton` beside a taller panel
          // reads as floating above it, which is what the owner saw as "the
          // speaker is not properly spaced in the middle".
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(child: _statusSlab(context, mc, l, cs, st, statusColor)),
            Padding(
              padding: EdgeInsets.only(left: context.skin.space.labelToControl),
              child: const MmAudioToggle(),
            ),
          ],
        ),

        if (hasRadio) _blockGap(context),
        if (hasRadio)
          MmCollapsibleSection(
            id: MmGroupIds.dashRadio,
            title: l.dashboardRadio,
            children: <Widget>[
              if (selfInfo == null)
                Text(l.dashboardAwaitingDevice,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontFamily: context.skin.type.monoFamily,
                        height: 1.5))
              else ...<Widget>[
                // R100 — the name is a fact here, not a form field. R52 let a
                // tap rename the radio from the dashboard, which made one row
                // both a readout and a hidden editor (only a 14 px pencil said
                // so). Renaming lives on Device configuration, where the
                // field, its 31-character limit and its Apply are; this row
                // opens that page like every other setting row here.
                InkWell(
                  onTap: () => context.push('/settings/device'),
                  borderRadius: mmRadius(context, 6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        minHeight: kMinInteractiveDimension),
                    child: Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            selfInfo.name.isEmpty
                                ? l.dashboardUnnamed
                                : selfInfo.name,
                            style: TextStyle(
                                color: cs.onSurface,
                                fontFamily: context.skin.type.monoFamily,
                                fontWeight: FontWeight.w600,
                                fontSize: context.skin.type.sizeLg),
                          ),
                        ),
                        SizedBox(width: context.skin.space.rowGap),
                        Icon(Icons.chevron_right,
                            size: 16, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
                // Your own public key: the one identifier another operator
                // needs to add you as a contact and DM you.
                MyPubkeyLine(pubKeyHex: mc.ownPubKeyHex),
                SizedBox(height: context.skin.space.insideText),
                // The radio's tuple, broken only between its own fields. As a
                // single `Text` it wrapped wherever the width ran out, so
                // "910.525MHz  SF7" ended one line and "CR5  22dBm" began the
                // next and a reader had to reassemble a configuration.
                MmValueFields(
                  fields: <String>[
                    '${selfInfo.frequencyMhz}MHz',
                    'SF${selfInfo.spreadingFactor}',
                    'CR${selfInfo.codingRate}',
                    '${selfInfo.txPowerDbm}dBm',
                  ],
                  separator: '  ',
                  color: cs.onSurface,
                ),
                // R39 — the region answer stays on the dashboard. Matched
                // against the radio's live tuple; "Custom" when none fits.
                SizedBox(height: context.skin.space.labelToControl),
                _RegionRow(selfInfo: selfInfo, l: l, cs: cs),
              ],
              if (mc.pairedName != null) ...<Widget>[
                SizedBox(height: context.skin.space.labelToControl),
                Text(l.dashboardPaired(mc.pairedName!),
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ],
          ),

        if (loc != null || selfInfo != null) _blockGap(context),
        if (loc != null || selfInfo != null)
          MmCollapsibleSection(
            id: MmGroupIds.dashLocation,
            title: l.dashboardLocation,
            children: <Widget>[
              // One refresh, on the block's own row. The block used to carry a
              // second one under it, on its own baseline, under a second copy
              // of the word LOCATION.
              Row(
                children: <Widget>[
                  Expanded(child: _LocationTile(mc: mc)),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: l.dashboardLocationRefresh,
                    constraints: const BoxConstraints(
                        minWidth: kMinInteractiveDimension,
                        minHeight: kMinInteractiveDimension),
                    onPressed: mc.isReady ? () => mc.refreshSelfInfo() : null,
                  ),
                ],
              ),
            ],
          ),

        if (mc.batteryMillivolts != null) _blockGap(context),
        if (mc.batteryMillivolts != null)
          MmCollapsibleSection(
            id: MmGroupIds.dashBattery,
            title: l.dashboardBattery,
            initiallyExpanded: false,
            children: <Widget>[
              InkWell(
                onTap: () => context.push('/settings/battery'),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: kMinInteractiveDimension),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _batteryLine(mc, l),
                          style: TextStyle(
                              color: mc.charging == true
                                  ? cs.tertiary
                                  : cs.onSurface,
                              fontFamily: context.skin.type.monoFamily),
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 16, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ],
          ),

        if (mc.recentEvents.isNotEmpty) _blockGap(context),
        if (mc.recentEvents.isNotEmpty)
          MmCollapsibleSection(
            id: MmGroupIds.dashRecent,
            title: l.dashboardRecent,
            children: <Widget>[
              for (final MeshEvent e in mc.recentEvents.take(12))
                Padding(
                  padding: EdgeInsets.symmetric(
                      vertical: context.skin.space.labelToControl),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // R75: was a fixed 64dp column, narrower than the
                      // 8-character mono stamp at 12pt, so the stamp ran into
                      // the event text. Mono keeps the column aligned without
                      // a hardcoded width.
                      // One line, whatever the type size. A mono stamp is eight
                      // fixed characters, and without this the Row could squeeze
                      // it by one character and wrap the last digit onto its own
                      // line — the "bad newline in the timestamp" the owner saw
                      // on the light themes, where the body size is largest.
                      Text(
                        '${e.at.hour.toString().padLeft(2, '0')}:'
                        '${e.at.minute.toString().padLeft(2, '0')}:'
                        '${e.at.second.toString().padLeft(2, '0')}',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontFamily: context.skin.type.monoFamily,
                            fontSize: context.skin.type.sizeBody),
                      ),
                      SizedBox(width: context.skin.space.rowGap),
                      Expanded(
                        child: Text(_eventLine(l, e),
                            style: TextStyle(color: cs.onSurface)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// The link state, once. Colour inverts on alert, the glyph is a dot or a
/// spinner, and the two controls that belong to the link live here; the audio
/// toggle deliberately does not (see the build method).
Widget _statusSlab(
  BuildContext context,
  MeshcoreController mc,
  AppLocalizations l,
  ColorScheme cs,
  ({String label, bool alert, bool busy}) st,
  Color statusColor,
) {
  final MmSkin skin = context.skin;
  return Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(
        horizontal: context.skin.space.step(4), vertical: context.skin.space.step(4)),
    color: st.alert ? cs.error : cs.surfaceContainerHigh,
    child: Row(
      children: <Widget>[
        if (st.busy)
          SizedBox(
            width: context.skin.space.step(5) + context.skin.space.step(1),
            height: context.skin.space.step(5) + context.skin.space.step(1),
            child:
                CircularProgressIndicator(strokeWidth: 2, color: statusColor),
          )
        else
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: statusColor),
          ),
        SizedBox(width: context.skin.space.rowGap),
        // The label and the syncing note share one flexible slot. They used to
        // be siblings with only the label flexible, so at 200 % text a long
        // paired name plus "SYNCING…" plus two 48 dp buttons overflowed the
        // row by 55 px on a 320 dp screen — measured, not guessed. Everything
        // that can grow now lives inside the Expanded and ellipsises.
        Expanded(
          child: Row(
            children: <Widget>[
              Flexible(
                child: Text('▌ ${st.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: statusColor,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600)),
              ),
              // Inline "SYNCING…" when the post-handshake drain is in flight,
              // so the 1–3 s of BLE round-trip work does not read as a freeze.
              // A static glyph, not a spinner, so widget tests can settle.
              if (mc.state == MeshcoreConnectionState.ready &&
                  mc.isDraining) ...<Widget>[
                SizedBox(width: context.skin.space.labelToControl),
                Icon(Icons.sync, size: 14, color: cs.primary),
                SizedBox(width: context.skin.space.labelToControl),
                Flexible(
                  child: Text(l.statusSyncing,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: cs.primary,
                          fontSize: skin.type.sizeMicro,
                          letterSpacing: 2)),
                ),
              ],
            ],
          ),
        ),
        // Connect / Retry sit in the slab because they are the state's own
        // action: with nothing paired they open the in-app pairing flow,
        // where which radio you get is your choice.
        if (mc.state == MeshcoreConnectionState.disconnected &&
            !mc.isConnecting)
          IconButton(
            tooltip: l.actionConnect,
            icon: Icon(Icons.link, color: statusColor, size: 20),
            onPressed: () =>
                context.push('/connect'),
          )
        else if (mc.state == MeshcoreConnectionState.failed ||
            mc.state == MeshcoreConnectionState.reconnecting ||
            mc.gaveUp)
          // The ladder retries on its own for about two and a half minutes with
          // a jittered backoff, so this is offered *while* it retries rather
          // than only after it gives up: the owner's own report was that a
          // wait with no action in it reads as a stuck screen, and a tap here
          // restarts the ladder from zero instead of waiting out the delay.
          // A link that gave up sits in `reconnecting` with no timer left, so
          // the state alone cannot offer the way out either.
          IconButton(
            tooltip: l.actionRetry,
            icon: Icon(Icons.refresh, color: statusColor, size: 20),
            onPressed: () =>
                context.push('/connect'),
          ),
        // R41 — Device chip: disconnect, reconnect, forget, or pick another
        // radio, in one place.
        IconButton(
          tooltip: l.dashboardDevice,
          icon: Icon(Icons.bluetooth, color: statusColor, size: 20),
          onPressed: () => DeviceManagerSheet.show(context),
        ),
      ],
    ),
  );
}

/// The radio's region preset, matched against its live tuple. A readout that
/// walks to Device configuration, where the choice actually lives.
class _RegionRow extends StatelessWidget {
  const _RegionRow({required this.selfInfo, required this.l, required this.cs});

  final SelfInfo selfInfo;
  final AppLocalizations l;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final RegionPreset? p = matchPresetByRadioParams(
      frequencyMhz: selfInfo.frequencyMhz,
      bandwidthKhz: selfInfo.bandwidthKhz,
      spreadingFactor: selfInfo.spreadingFactor,
      codingRate: selfInfo.codingRate,
    );
    final bool isCustom = p == null;
    return InkWell(
      onTap: () => context.push('/settings/device'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Row(
          children: <Widget>[
            Icon(isCustom ? Icons.tune : Icons.public,
                size: 14, color: isCustom ? cs.tertiary : cs.primary),
            SizedBox(width: context.skin.space.labelToControl),
            Text(
                p == null
                    ? l.deviceRegionCustom
                    : localizedPresetLabel(l, p.id),
                style: TextStyle(
                    color: isCustom ? cs.tertiary : cs.primary,
                    fontSize: context.skin.type.sizeBody,
                    fontWeight: FontWeight.w600)),
            // Every other row in this panel opens a page and says so with a
            // chevron; this one opened Device configuration without one, which
            // taught the opposite rule two rows above it.
            SizedBox(width: context.skin.space.labelToControl),
            Icon(Icons.chevron_right, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Localise a single RECENT-feed event line. The controller emits
/// a discriminated `kind` + an args map; this function picks the
/// matching arb format and substitutes the args, so every event
/// row reads in the user's chosen locale.
String _eventLine(AppLocalizations l, MeshEvent e) {
  final Map<String, String> a = e.args;
  return switch (e.kind) {
    MeshEventKind.advert => l.eventAdvert(a['name'] ?? '?'),
    MeshEventKind.channelMsg =>
      l.eventChannelMsg(a['channel'] ?? '?', a['text'] ?? ''),
    MeshEventKind.dm => l.eventDm(a['text'] ?? ''),
    MeshEventKind.contact => l.eventContact(a['name'] ?? '?'),
    MeshEventKind.contactBatch =>
      l.eventContactBatch(int.tryParse(a['count'] ?? '') ?? 0),
    MeshEventKind.battery => l.eventBattery(a['volts'] ?? '?'),
    MeshEventKind.deviceError =>
      l.eventDeviceError(a['reason'] ?? a['code'] ?? '?'),
    MeshEventKind.deviceClockSynced => l.eventDeviceClockSynced,
    MeshEventKind.deviceClockSkew =>
      l.eventDeviceClockSkew(a['seconds'] ?? '?'),
    MeshEventKind.msgSent => l.eventMsgSent,
    MeshEventKind.deviceInfo => l.eventDeviceInfo(a['version'] ?? '?'),
    MeshEventKind.selfInfo => l.eventSelfInfo(a['name'] ?? '?'),
    MeshEventKind.queuedWaiting => a.containsKey('count')
        ? l.eventQueuedWaitingN(a['count']!)
        : l.eventQueuedWaiting,
    MeshEventKind.oneKeyRejected => l.eventOneKeyRejected(a['key'] ?? '?'),
    MeshEventKind.radioRefused => l.eventRadioRefused,
  };
}

/// Dashboard "LOCATION" tile (Phase A). Three states:
///   - device reported a non-zero fix → green dot + coordinates +
///     source label ("device").
///   - device responded but lat/lon are (0,0) → "not set" with a
///     **Configure** CTA into Device config (manual entry).
///   - device hasn't reported SelfInfo yet → muted "awaiting".
class _LocationTile extends StatelessWidget {
  const _LocationTile({required this.mc});
  final MeshcoreController mc;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppLocalizations l = AppLocalizations.of(context);
    final OwnLocation? loc = mc.ownLocation;
    final SelfInfo? si = mc.selfInfo;
    final bool awaitingSelf = si == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (loc != null)
          // Coordinates, and where they came from, on one line. The raw
          // wire values and the radio's advert-location policy are a
          // diagnostic question, answered in Diagnostics where every line
          // names its frame; the home screen is not the place to read them.
          // Two or three facts, laid out where the separators are. As one
          // string it wrapped wherever the width ran out, and on the handset
          // that was inside nothing in particular — a coordinate split after
          // its decimal point is a number the reader has to reassemble.
          MmValueFields(
            fields: <String>[
              MmFormat.coordinate(loc.latitude, loc.longitude),
              // Zero altitude is the firmware's "not set": a radio that has
              // never been given one reports 0, and printing "alt 0 m" in
              // Denver states a fact nobody measured. The phone's own fix
              // always carries a real altitude, so it is only the device
              // source that can be absent this way.
              if ((loc.altitudeMeters ?? 0) != 0)
                l.dashboardLocationAltitude(loc.altitudeMeters!.round()),
              loc.localizedSourceLabel(l),
            ],
            color: cs.onSurface,
          )
        else if (awaitingSelf)
          Text(l.dashboardAwaitingDeviceLocation,
              style: TextStyle(color: cs.onSurfaceVariant))
        else
          // The message and its action stack, they do not share a Row. At
          // 200 % text the icon, the sentence and a text button do not fit
          // across a 320 dp tile: the button keeps its intrinsic width, so the
          // Expanded text had nothing left and the row overflowed by 55 px —
          // the yellow-and-black stripe the owner reported on this exact
          // screen. A column cannot overflow that way at any text size.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.only(top: context.skin.space.step(1)),
                    child: Icon(Icons.location_off, size: 18, color: cs.error),
                  ),
                  SizedBox(width: context.skin.space.rowGap),
                  Expanded(
                    child: Text(
                      l.dashboardLocationNotSet,
                      style: TextStyle(color: cs.onSurface),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: MmAction(
                  label: l.dashboardLocationConfigure,
                  dense: true,
                  onPressed: () => context.push('/settings/device'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// The radio's routable contact table as one value: `12/350`, or `12` when the
/// firmware does not say how many it can hold.
String _contactsLabel(MeshcoreController mc) {
  final int? n = mc.deviceContactCount;
  if (n == null) return '';
  final int? max = mc.maxContacts;
  return max == null ? '$n' : '$n/$max';
}

/// Dashboard battery line: voltage + the **model's** state-of-charge
/// estimate (OCV-curve, more accurate than the raw linear percent),
/// with a compact time-to-empty when the estimator has one. Charging
/// supersedes the runtime (it's paused while charging).
String _batteryLine(MeshcoreController mc, AppLocalizations l) {
  final est = mc.batteryEstimate;
  final int percent =
      est.socPercent.isNaN ? (mc.batteryPercent ?? 0) : est.socPercent.round();
  final StringBuffer b = StringBuffer(l.dashboardBatteryReadout(
    mc.batteryVolts!.toStringAsFixed(2),
    percent,
  ));
  if (mc.charging == true) {
    b.write('  ⚡ ${l.dashboardCharging}');
  } else if (est.timeToEmpty != null) {
    b.write(
        ' · ${l.dashboardBatteryLeft(_fmtBatteryDur(est.timeToEmpty!, l))}');
  }
  return b.toString();
}

String _fmtBatteryDur(Duration d, AppLocalizations l) =>
    MmFormat.batteryDuration(d, l);
