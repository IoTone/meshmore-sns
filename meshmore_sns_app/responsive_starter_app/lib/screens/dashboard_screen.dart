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
import 'device_manager_sheet.dart';
import '../ui/mm_shape.dart';

/// R8 home — "SEELE Monolith" dashboard: one dominant numeral
/// (peers in range), a full-width status slab that colour-inverts on
/// alert, a terse radio readout, and the recent-activity feed. Pure
/// token styling so every theme preset re-skins it.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  ({String label, bool alert, bool busy}) _status(
      MeshcoreController mc, AppLocalizations l) {
    return switch (mc.state) {
      MeshcoreConnectionState.ready =>
        (label: l.statusLinked, alert: false, busy: false),
      MeshcoreConnectionState.handshaking =>
        (label: l.statusHandshaking, alert: false, busy: true),
      MeshcoreConnectionState.reconnecting =>
        (label: l.statusReconnecting, alert: true, busy: true),
      MeshcoreConnectionState.failed =>
        (label: l.statusLinkLost, alert: true, busy: false),
      MeshcoreConnectionState.disconnected => (
          label: mc.isConnecting ? l.statusConnecting : l.statusOffline,
          alert: !mc.isConnecting,
          busy: mc.isConnecting,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme tt = Theme.of(context).textTheme;
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: <Widget>[
        // Dominant numeral.
        Text(l.dashboardPeersInRange,
            style: TextStyle(
                color: cs.onSurfaceVariant, fontSize: 12, letterSpacing: 4)),
        Text('$inRange',
            style: (tt.displayLarge ?? const TextStyle(fontSize: 72))
                .copyWith(
                    color: cs.onSurface,
                    fontSize: 88,
                    height: 1.0,
                    fontWeight: FontWeight.w300)),
        const SizedBox(height: 4),
        Text(
            mc.deviceContactCount == null
                ? l.dashboardKnownCount(mc.nodes.length)
                : '${l.dashboardKnownCount(mc.nodes.length)}'
                    '   ·   ${l.dashContacts} ${mc.deviceContactCount}'
                    '${mc.maxContacts == null ? '' : '/${mc.maxContacts}'}',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 24),

        // Status slab — colour-inverts to error on alert.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          color: st.alert ? cs.error : cs.surfaceContainerHigh,
          child: Row(
            children: <Widget>[
              if (st.busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: statusColor),
                )
              else
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('▌ ${st.label}',
                    style: TextStyle(
                        color: statusColor,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600)),
              ),
              // Inline "SYNCING…" when the post-handshake drain is in
              // flight. Surfaces the BLE round-trip work that runs for
              // 1–3 s after a fresh link so it doesn't read as a
              // freeze. Static glyph (no spinner) so widget tests'
              // pumpAndSettle can still settle.
              if (mc.state == MeshcoreConnectionState.ready &&
                  mc.isDraining) ...<Widget>[
                Icon(Icons.sync, size: 14, color: cs.primary),
                const SizedBox(width: 4),
                Text(l.statusSyncing,
                    style: TextStyle(
                        color: cs.primary,
                        fontSize: 10,
                        letterSpacing: 2)),
                const SizedBox(width: 4),
              ],
              // R41 — Device chip. Single tap target for disconnect /
              // reconnect / forget / pick-a-different-radio. The
              // existing inline Connect/Retry stays for one-tap
              // recovery; this sits next to it for everything else.
              IconButton(
                tooltip: l.dashboardDevice,
                icon: Icon(Icons.bluetooth, color: statusColor, size: 20),
                onPressed: () => DeviceManagerSheet.show(context),
              ),
              // Quick mute/unmute for alert sounds (default on).
              const MmAudioToggle(),
            ],
          ),
        ),
        // R91 — Connect / Retry used to sit in the status slab between the
        // label and two 48 dp icon buttons. At 256-320 dp with large text
        // that row overflowed (51 px at 256), and it starved the label it
        // was supposed to explain. It gets its own row, shown only in the
        // states that need it.
        if (mc.state == MeshcoreConnectionState.disconnected &&
            !mc.isConnecting)
          Align(
            alignment: Alignment.centerLeft,
            child: MmAction(
              icon: Icons.link,
              label: l.actionConnect,
              onPressed: () => mc.connect(),
            ),
          )
        else if (mc.state == MeshcoreConnectionState.failed)
          Align(
            alignment: Alignment.centerLeft,
            child: MmAction(
              icon: Icons.refresh,
              label: l.actionRetry,
              onPressed: () => mc.connect(),
            ),
          ),
        const SizedBox(height: 22),

        // Terse radio readout.
        Text(l.dashboardRadio,
            style: TextStyle(
                color: cs.onSurfaceVariant, fontSize: 12, letterSpacing: 4)),
        const SizedBox(height: 4),
        if (selfInfo == null)
          Text(l.dashboardAwaitingDevice,
              style: TextStyle(
                  color: cs.onSurface,
                  fontFamily: 'JetBrains Mono',
                  height: 1.5))
        else ...<Widget>[
          // R100 — the name is a fact here, not a form field. R52 let a
          // tap rename the radio from the dashboard, which made one row
          // both a readout and a hidden editor (only a 14 px pencil said
          // so). Renaming lives on Device configuration, where the field,
          // its 31-character limit and its Apply are; this row now opens
          // that page like every other setting row on the dashboard.
          InkWell(
            onTap: () => context.push('/settings/device'),
            borderRadius: mmRadius(context, 6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      selfInfo.name.isEmpty
                          ? l.dashboardUnnamed
                          : selfInfo.name,
                      style: TextStyle(
                          color: cs.onSurface,
                          fontFamily: 'JetBrains Mono',
                          fontWeight: FontWeight.w600,
                          fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right,
                      size: 16, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Your own public key. This is the one identifier another
          // operator needs to add you as a contact and DM you, and
          // until now the app knew it (`ownPubKeyHex`, used all over
          // for self-filtering) but never showed it to you -- leaving
          // "why can't they message me?" with nothing to check.
          MyPubkeyLine(pubKeyHex: mc.ownPubKeyHex),
          const SizedBox(height: 2),
          Text(
            '${selfInfo.frequencyMhz}MHz  '
            'SF${selfInfo.spreadingFactor}  '
            'CR${selfInfo.codingRate}  '
            '${selfInfo.txPowerDbm}dBm',
            style: TextStyle(
                color: cs.onSurface,
                fontFamily: 'JetBrains Mono',
                height: 1.5),
          ),
        ],
        // R39 — region preset readout. The answer to "what region am
        // I on?" should be visible from the dashboard, not buried in
        // Device Config. Matched against the device's live tuple;
        // shows "Custom" when no shipped preset matches.
        if (selfInfo != null) ...<Widget>[
          const SizedBox(height: 4),
          Builder(builder: (BuildContext _) {
            final RegionPreset? p = matchPresetByRadioParams(
              frequencyMhz: selfInfo.frequencyMhz,
              bandwidthKhz: selfInfo.bandwidthKhz,
              spreadingFactor: selfInfo.spreadingFactor,
              codingRate: selfInfo.codingRate,
            );
            final bool isCustom = p == null;
            return InkWell(
              onTap: () => context.push('/settings/device'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    Icon(isCustom ? Icons.tune : Icons.public,
                        size: 14,
                        color: isCustom ? cs.tertiary : cs.primary),
                    const SizedBox(width: 6),
                    Text(
                        p == null
                            ? l.deviceRegionCustom
                            : localizedPresetLabel(l, p.id),
                        style: TextStyle(
                            color: isCustom ? cs.tertiary : cs.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            );
          }),
        ],
        if (mc.pairedName != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(l.dashboardPaired(mc.pairedName!),
              style:
                  TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ],
        // Location surface (Phase A) — pulled from the device's
        // SelfInfo when present, otherwise flagged as unset with a
        // "Configure" CTA into Device config (manual lat/lon entry).
        const SizedBox(height: 18),
        _LocationTile(mc: mc),
        if (mc.batteryMillivolts != null) ...<Widget>[
          const SizedBox(height: 18),
          InkWell(
            onTap: () => context.push('/settings/battery'),
            borderRadius: mmRadius(context, 6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(l.dashboardBattery,
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                              letterSpacing: 4)),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right,
                          size: 16, color: cs.onSurfaceVariant),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _batteryLine(mc, l),
                    style: TextStyle(
                        color: mc.charging == true
                            ? cs.tertiary
                            : cs.onSurface,
                        fontFamily: 'JetBrains Mono'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),

        // Recent activity.
        Text(l.dashboardRecent,
            style: TextStyle(
                color: cs.onSurfaceVariant, fontSize: 12, letterSpacing: 4)),
        const SizedBox(height: 6),
        if (mc.recentEvents.isEmpty)
          Text(l.dashboardNoActivity,
              style: TextStyle(color: cs.onSurfaceVariant))
        else
          ...mc.recentEvents.take(12).map((MeshEvent e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // R75: was a fixed 64dp column, narrower than the
                    // 8-character mono stamp at 12pt, so the stamp ran
                    // into the event text. Mono keeps the column aligned
                    // without a hardcoded width.
                    Text(
                      '${e.at.hour.toString().padLeft(2, '0')}:'
                      '${e.at.minute.toString().padLeft(2, '0')}:'
                      '${e.at.second.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontFamily: 'JetBrains Mono',
                          fontSize: 12),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_eventLine(l, e),
                          style: TextStyle(color: cs.onSurface)),
                    ),
                  ],
                ),
              )),
      ],
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
    MeshEventKind.channelMsg => l.eventChannelMsg(
        a['channel'] ?? '?', a['text'] ?? ''),
    MeshEventKind.dm => l.eventDm(a['text'] ?? ''),
    MeshEventKind.contact => l.eventContact(a['name'] ?? '?'),
    MeshEventKind.battery => l.eventBattery(a['volts'] ?? '?'),
    MeshEventKind.deviceError =>
      l.eventDeviceError(a['reason'] ?? a['code'] ?? '?'),
    MeshEventKind.deviceClockSynced => l.eventDeviceClockSynced,
    MeshEventKind.deviceClockSkew =>
      l.eventDeviceClockSkew(a['seconds'] ?? '?'),
    MeshEventKind.msgSent => l.eventMsgSent(a['ack'] ?? '?'),
    MeshEventKind.deviceInfo => l.eventDeviceInfo(a['version'] ?? '?'),
    MeshEventKind.selfInfo => l.eventSelfInfo(a['name'] ?? '?'),
    MeshEventKind.queuedWaiting => a.containsKey('count')
        ? l.eventQueuedWaitingN(a['count']!)
        : l.eventQueuedWaiting,
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
        Row(
          children: <Widget>[
            Expanded(
              child: Text(l.dashboardLocation,
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                      letterSpacing: 4)),
            ),
            // Manual refresh — the periodic 30 s SelfInfo poll
            // handles most cases, but if the user just moved
            // significantly and doesn't want to wait, this button
            // forces an immediate re-query.
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: l.dashboardLocationRefresh,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: mc.isReady ? () => mc.refreshSelfInfo() : null,
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (loc != null) ...<Widget>[
          Text(
            '${loc.latitude.toStringAsFixed(5)}, '
            '${loc.longitude.toStringAsFixed(5)}'
            '${loc.altitudeMeters == null ? '' : '  '
                '· ${l.dashboardLocationAltitude(loc.altitudeMeters!.round())}'}'
            '\n'
            '${l.dashboardLocationSourceLabel(loc.localizedSourceLabel(l))}',
            style: TextStyle(
                color: cs.onSurface,
                fontFamily: 'JetBrains Mono',
                height: 1.5),
          ),
          // Diagnostic readout — shows the raw selfInfo lat/lon,
          // the device's advertLocPolicy, and the phoneFix value
          // (if any). Lets us tell at a glance whether the device
          // is reporting fresh GPS or whether ownLocation is
          // falling through to a cached phone fix.
          const SizedBox(height: 4),
          _LocationDebugLine(mc: mc, cs: cs),
        ]
        else if (awaitingSelf)
          Text(l.dashboardAwaitingDeviceLocation,
              style: TextStyle(color: cs.onSurfaceVariant))
        else
          Row(
            children: <Widget>[
              Icon(Icons.location_off,
                  size: 18, color: cs.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.dashboardLocationNotSet,
                  style: TextStyle(color: cs.onSurface),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/settings/device'),
                child: Text(l.dashboardLocationConfigure),
              ),
            ],
          ),
      ],
    );
  }
}

/// Small dev-style readout under the formatted Location value.
/// Shows the **raw** values our controller currently sees:
/// - `dev: lat, lon` — `mc.selfInfo.latitude/longitude` straight
///   off the wire. Frozen at (0, 0) → the firmware reports "no
///   GPS." Frozen at a non-zero pair across multiple refreshes →
///   the firmware is caching and not re-reading GPS.
/// - `pol: N` — `mc.selfInfo.advertLocPolicy`, using MeshCore's
///   integers from `src/helpers/CommonCLI.h`: 0=None, 1=Device GPS
///   (`ADVERT_LOC_SHARE`), 2=Pinned (`ADVERT_LOC_PREFS`). If the user
///   picked "Device GPS" but this is not 1, the policy didn't stick on
///   the device. (Companion firmware only distinguishes 0 from
///   non-zero — `examples/companion_radio/NodePrefs.h:9-10` — so 2
///   behaves like 1 there. This comment previously read
///   "1=Pinned, 2=Device GPS", the label reversal fixed on this branch (cc5acb2).)
/// - `phone: lat, lon` — the one-shot phone fix `mc.phoneLocationFix`.
///   Only present if the user has tapped "Use phone location" or
///   the dashboard requested a fix. `ownLocation` falls back to
///   this when the device reports (0, 0).
class _LocationDebugLine extends StatelessWidget {
  const _LocationDebugLine({required this.mc, required this.cs});
  final MeshcoreController mc;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final SelfInfo? si = mc.selfInfo;
    final OwnLocation? phone = mc.phoneLocationFix;
    final List<String> parts = <String>[
      if (si != null)
        'dev: ${si.latitude.toStringAsFixed(5)}, '
            '${si.longitude.toStringAsFixed(5)} '
            'pol:${si.advertLocPolicy}'
      else
        'dev: —',
      if (phone != null)
        'phone: ${phone.latitude.toStringAsFixed(5)}, '
            '${phone.longitude.toStringAsFixed(5)}'
            '${phone.altitudeMeters == null ? '' : ' '
                'alt:${phone.altitudeMeters!.round()}m'}'
      else
        'phone: —',
    ];
    return Text(
      parts.join('\n'),
      style: TextStyle(
        color: cs.onSurfaceVariant.withValues(alpha: .7),
        fontFamily: 'JetBrains Mono',
        fontSize: 10,
        height: 1.35,
      ),
    );
  }
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
    b.write(' · ${l.dashboardBatteryLeft(_fmtBatteryDur(est.timeToEmpty!, l))}');
  }
  return b.toString();
}

String _fmtBatteryDur(Duration d, AppLocalizations l) {
  if (d.inDays > 0) return l.batteryDurDH(d.inDays, d.inHours % 24);
  if (d.inHours > 0) return l.batteryDurHM(d.inHours, d.inMinutes % 60);
  return l.batteryDurM(d.inMinutes);
}
