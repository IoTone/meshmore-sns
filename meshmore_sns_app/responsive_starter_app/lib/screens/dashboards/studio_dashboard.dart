// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../meshcore/own_location.dart';
import '../../theme/mm_skin.dart';
import '../../ui/mm_audio_toggle.dart';
import '../../ui/mm_collapse_controller.dart';
import '../../ui/mm_collapsible.dart';
import '../../ui/mm_components.dart';
import '../device_manager_sheet.dart';
import 'dashboard_model.dart';
import 'my_pubkey_line.dart';

/// R68 — the **Studio** dashboard: the clean, professional, readable
/// dark layout. It exists because the SEELE monolith (what Studio used to
/// inherit) is the opposite register: a 88sp numeral, a full-bleed
/// colour-inverting status slab and tracked all-caps labels.
///
/// Type roles (the one rule this screen follows, pinned by
/// `test/screens/studio_dashboard_test.dart`):
///   * **sans** (the platform UI face) for everything a person reads:
///     labels, names, prose, status, region;
///   * **mono** (`MmType.monoFamily`) only for machine data: counts,
///     coordinates, radio parameters, the public key, battery volts,
///     timestamps.
/// A row may hold both (a number beside its caption) but never a word in
/// the data face.
///
/// Reads the same [DashboardModel] / controller as every skin, and the
/// position only through `MeshcoreController.ownLocation` (the
/// location-source-of-truth guard). The status is text plus a dot whose
/// *shape* (filled / ring / spinner) differs, never a colour fill.
class StudioDashboard extends StatelessWidget {

  const StudioDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final DashboardModel m = DashboardModel.gather(mc, l);
    final TextStyle label = mmSectionLabelStyle(skin);
    final TextStyle data = _data(skin, 13);
    final Color muted = skin.color.fgMuted;
    final SelfInfo? si = mc.selfInfo;
    final OwnLocation? loc = mc.ownLocation;

    String cap(String s) => skin.type.upperHeadings ? s.toUpperCase() : s;

    return ListView(
      padding: EdgeInsets.only(bottom: skin.space.sectionGap),
      children: <Widget>[
        _StatusRow(mc: mc, m: m),
        _hairline(skin),
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: skin.space.screenEdge,
              vertical: skin.space.rowInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(cap(l.dashboardPeersInRange), style: label),
              SizedBox(height: skin.space.labelToControl),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text('${m.peersInRange}', style: _data(skin, 22)),
                  SizedBox(width: skin.space.rowGap),
                  Expanded(
                    child: Text(
                      m.contactsLabel == null
                          ? l.dashboardKnownCount(m.knownCount)
                          : l.dashboardKnownAndContacts(
                              m.knownCount, m.contactsLabel!),
                      style: TextStyle(color: muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        MmCollapsibleSection(
          id: MmGroupIds.studioRadio,
          title: l.dashboardRadio,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(skin.space.screenEdge,
                  skin.space.rowGap, skin.space.screenEdge, skin.space.rowInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (si == null)
                    Text(l.dashboardAwaitingDevice,
                        style: TextStyle(color: muted))
                  else ...<Widget>[
                    // R100 — renaming moved to Device configuration; this
                    // is a readout that walks there, with the same chevron
                    // the battery and region rows carry.
                    InkWell(
                      onTap: () => context.push('/settings/device'),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            minHeight: kMinInteractiveDimension),
                        child: Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(m.nodeName ?? '',
                                  style: TextStyle(
                                      fontSize: skin.type.sizeLg,
                                      fontWeight: FontWeight.w600)),
                            ),
                            SizedBox(width: skin.space.rowGap),
                            Icon(Icons.chevron_right, size: 16, color: muted),
                          ],
                        ),
                      ),
                    ),
                    MyPubkeyLine(
                      pubKeyHex: m.pubKeyHex,
                      style: _data(skin, 12).copyWith(color: muted),
                      iconColor: muted,
                    ),
                    SizedBox(height: skin.space.labelToControl),
                    Text(m.radioLine ?? '', style: data),
                    InkWell(
                      onTap: () => context.push('/settings/device'),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            minHeight: kMinInteractiveDimension),
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.public, size: 16, color: muted),
                            SizedBox(width: skin.space.rowGap),
                            Flexible(
                              child: Text(m.region,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (mc.pairedName != null)
                    Text(l.dashboardPaired(mc.pairedName!),
                        style: TextStyle(color: muted, fontSize: skin.type.sizeBody)),
                  if (m.batteryLine != null)
                    InkWell(
                      onTap: () => context.push('/settings/battery'),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            minHeight: kMinInteractiveDimension),
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.battery_std, size: 16, color: muted),
                            SizedBox(width: skin.space.rowGap),
                            Text(m.batteryLine!, style: data),
                            const Spacer(),
                            Icon(Icons.chevron_right, size: 18, color: muted),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        MmCollapsibleSection(
          id: MmGroupIds.studioLocation,
          title: l.dashboardLocation,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(skin.space.screenEdge,
                  skin.space.labelToControl, skin.space.labelToControl,
                  skin.space.rowGap),
              child: Row(
                children: <Widget>[
                  Expanded(child: _locationBody(context, mc, loc, si, skin)),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: l.dashboardLocationRefresh,
                    color: muted,
                    onPressed: mc.isReady ? () => mc.refreshSelfInfo() : null,
                  ),
                ],
              ),
            ),
          ],
        ),
        MmCollapsibleSection(
          id: MmGroupIds.studioRecent,
          title: l.dashboardRecent,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: skin.space.screenEdge,
                  vertical: skin.space.rowGap),
              child: m.events.isEmpty
                  ? Text(l.dashboardNoActivity, style: TextStyle(color: muted))
                  : Column(
                      children: <Widget>[
                        for (final ({String text, String time}) e in m.events)
                          Padding(
                            padding: EdgeInsets.symmetric(
                                vertical: skin.space.labelToControl),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                // R75: was a fixed 70dp column. The mono
                                // stamp is ~67dp at 12pt, leaving ~3dp of
                                // gap and no headroom for text scaling, so
                                // it collided with the event text at larger
                                // font sizes. Mono makes the column
                                // self-aligning, so the width is not needed.
                                Text(e.time,
                                    style: _data(skin, 12)
                                        .copyWith(color: muted)),
                                SizedBox(width: skin.space.rowGap),
                                Expanded(child: Text(e.text)),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _locationBody(BuildContext context, MeshcoreController mc,
      OwnLocation? loc, SelfInfo? si, MmSkin skin) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Color muted = skin.color.fgMuted;
    if (loc != null) {
      // Coordinates and where they came from, on one line: the source is a
      // fact about the reading, the rest of its provenance is Diagnostics.
      return Text(
        '${loc.latitude.toStringAsFixed(5)}, '
        '${loc.longitude.toStringAsFixed(5)}'
        '${loc.altitudeMeters == null ? '' : '  · '
            '${l.dashboardLocationAltitude(loc.altitudeMeters!.round())}'}'
        '  · ${loc.localizedSourceLabel(l)}',
        style: _data(skin, 13),
      );
    }
    if (si == null) {
      return Text(l.dashboardAwaitingDeviceLocation,
          style: TextStyle(color: muted));
    }
    return Row(
      children: <Widget>[
        Icon(Icons.location_off_outlined, size: 18, color: muted),
        SizedBox(width: skin.space.rowGap),
        Expanded(child: Text(l.dashboardLocationNotSet)),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => context.push('/settings/device'),
          child: Text(l.dashboardLocationConfigure),
        ),
      ],
    );
  }
}

/// A data-face style: mono, machine values only.
TextStyle _data(MmSkin skin, double size) => TextStyle(
      fontFamily: skin.type.monoFamily,
      fontSize: size,
      height: 1.4,
    );

Widget _hairline(MmSkin skin) =>
    Container(height: skin.shape.hairlineWidth, color: skin.color.hairline);

/// Link state as a quiet row: a dot whose shape (filled / ring /
/// spinner) and the label say the state; there is no colour fill and no
/// colour-only meaning. Connect/Retry, the device sheet and the audio
/// toggle are 48dp targets.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.mc, required this.m});
  final MeshcoreController mc;
  final DashboardModel m;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final Color muted = skin.color.fgMuted;
    final bool linked = mc.state == MeshcoreConnectionState.ready;
    // R97 — linked is green (the same hue as the app-bar chip), not the
    // accent grey the dot used while the chip above it was sage.
    final Color dotColor =
        m.alert ? skin.color.alert : (linked ? skin.color.link : skin.color.accent);
    final Widget dot = m.busy
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: dotColor),
          )
        : Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: linked ? dotColor : null,
              border: linked ? null : Border.all(color: dotColor, width: 2),
            ),
          );
    final bool canConnect =
        mc.state == MeshcoreConnectionState.disconnected && !mc.isConnecting;
    final bool canRetry = mc.state == MeshcoreConnectionState.failed ||
        mc.gaveUp;
    final Widget status = Row(
      children: <Widget>[
        SizedBox(width: skin.space.rowInset, child: Center(child: dot)),
        SizedBox(width: skin.space.rowInset),
        Expanded(
          child: Text(
            m.statusLabel,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
    final List<Widget> controls = <Widget>[
      if (linked && mc.isDraining)
        Padding(
          padding: EdgeInsets.only(right: skin.space.rowGap),
          child: Text(l.statusSyncing,
              style: TextStyle(color: muted, fontSize: skin.type.sizeBody)),
        ),
      if (canConnect || canRetry)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: skin.space.labelToControl),
          child: MmAction(
            dense: true,
            label: canRetry ? l.actionRetry : l.actionConnect,
            onPressed: () => mc.connect(),
          ),
        ),
      IconButton(
        tooltip: l.dashboardDevice,
        icon: Icon(Icons.bluetooth, size: 20, color: muted),
        onPressed: () => DeviceManagerSheet.show(context),
      ),
      MmAudioToggle(color: muted),
    ];
    // R68 — the status line and its three controls fit one row on a normal
    // phone. On a narrow screen, or at the accessibility floor where the
    // status label and the Connect action both grow, one row cannot hold them
    // and the row overflowed (14 px at 256 dp, 41 px at 320 dp with 200 %
    // text). Below that point the controls take their own line rather than
    // being clipped: nothing here may become unreachable.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool stacked = c.maxWidth < 380 ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        // Vertical padding is explicit and equal on both sides.
        //
        // It used to be none at all, with a `minHeight: 56` doing the work and
        // a Row centring whatever fell inside it — so the band's height came
        // from its tallest child and the space above the content was not the
        // space below it. Measured on the phone against the hairline above and
        // below: 51 px above the Retry button and 11 px below, which is the
        // "more space above than below" the owner saw on the LINK LOST row and
        // on its button alike. Equal padding cannot be lopsided.
        return Padding(
          padding: EdgeInsets.only(
            left: skin.space.screenEdge,
            right: skin.space.labelToControl,
            top: skin.space.rowInset,
            bottom: skin.space.rowInset,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      status,
                      Padding(
                        padding: EdgeInsets.only(bottom: skin.space.labelToControl),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 4,
                          children: controls,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: <Widget>[
                      Expanded(child: status),
                      ...controls,
                    ],
                  ),
          ),
        );
      },
    );
  }
}
