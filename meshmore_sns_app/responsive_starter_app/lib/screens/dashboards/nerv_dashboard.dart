// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../theme/mm_skin.dart';
import '../../ui/mm_audio_toggle.dart';
import '../../ui/mm_components.dart';
import '../../ui/mm_scaffold.dart';
import '../device_manager_sheet.dart';
import 'dashboard_model.dart';
import 'my_pubkey_line.dart';

/// Concept A — **NERV Terminal** dashboard: an information-maximal
/// operations console. Chamfered HUD panels, hazard-stripe section
/// headers, dense mono readouts, a CRT scanline + corner brackets
/// (all from the active [MmSkin]). The same [DashboardModel] data the
/// SEELE monolith shows, re-imagined as a telemetry grid — proving a
/// skin can drive layout, not just colour.
class NervDashboard extends StatelessWidget {

  const NervDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final DashboardModel m = DashboardModel.gather(mc, l);
    final TextStyle mono = TextStyle(
        fontFamily: skin.type.monoFamily, color: skin.color.fg, fontSize: skin.type.sizeBody);

    return MmScaffold(
      child: ListView(
        padding: EdgeInsets.fromLTRB(skin.space.rowInset, skin.space.rowInset, skin.space.rowInset, skin.space.sectionGap),
        children: <Widget>[
          SizedBox(height: skin.space.rowGap),
          // Status pills, right-aligned. A Wrap rather than a Row: at the
          // accessibility floor the two labels together are wider than a
          // 320 dp screen, and a Row cannot give the width back.
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                MmStatusPill(m.channelLabel),
                MmStatusPill(
                  m.statusLabel,
                  alert: m.alert,
                ),
              ],
            ),
          ),
          SizedBox(height: skin.space.rowInset),

          // LINK panel.
          MmPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MmSectionHeader(
                  l.dashNervLink,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Quick mute/unmute for alert sounds (default on).
                      MmAudioToggle(
                          dense: true, size: 18, color: skin.color.accent),
                      IconButton(
                        tooltip: l.dashboardDevice,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 48, minHeight: 48),
                        icon: Icon(Icons.bluetooth,
                            size: 18, color: skin.color.accent),
                        onPressed: () => DeviceManagerSheet.show(context),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: skin.space.rowGap),
                MmReadout(
                  label: 'BLE',
                  value: m.statusLabel,
                  valueColor: m.alert
                      ? skin.color.alert
                      : (m.linked ? skin.color.link : skin.color.ok),
                ),
                SizedBox(height: skin.space.labelToControl),
                MmReadout(label: l.dashNervNode, value: m.nodeName ?? '—'),
              ],
            ),
          ),
          SizedBox(height: skin.space.rowInset),

          // RADIO panel.
          MmPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MmSectionHeader(l.dashboardRadio),
                SizedBox(height: skin.space.rowGap),
                m.radioFields == null
                    ? Text(l.dashboardAwaitingDevice, style: mono)
                    : MmValueFields(
                        fields: m.radioFields!,
                        separator: '  ',
                        // Two spaces, not the default middle dot: the radio's
                        // settings are a tuple, not four separate facts.
                        color: mono.color,
                      ),
                SizedBox(height: skin.space.insideText),
                MyPubkeyLine(pubKeyHex: m.pubKeyHex, style: mono),
                SizedBox(height: skin.space.labelToControl),
                MmReadout(label: l.dashNervRegion, value: m.region),
              ],
            ),
          ),
          SizedBox(height: skin.space.rowInset),

          // MESH panel — hazard-striped header (the "live fabric" band).
          MmPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MmSectionHeader(l.dashNervMesh),
                SizedBox(height: skin.space.rowGap),
                MmReadout(
                    label: l.dashboardPeersInRange,
                    value: '${m.peersInRange}',
                    emphasize: true),
                SizedBox(height: skin.space.labelToControl),
                MmReadout(
                    label: l.dashNervKnown, value: '${m.knownCount}'),
                if (m.contactsLabel != null) ...<Widget>[
                  SizedBox(height: skin.space.labelToControl),
                  MmReadout(label: l.dashContacts, value: m.contactsLabel!),
                ],
                if (m.batteryLine != null) ...<Widget>[
                  SizedBox(height: skin.space.labelToControl),
                  MmReadout(label: l.dashboardBattery, value: m.batteryLine!),
                ],
              ],
            ),
          ),
          SizedBox(height: skin.space.rowInset),

          // EVENTS log.
          MmPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MmSectionHeader(l.dashNervEvents),
                SizedBox(height: skin.space.rowGap),
                if (m.events.isEmpty)
                  Text(l.dashboardNoActivity,
                      style: mono.copyWith(color: skin.color.fgMuted))
                else
                  for (final ({String time, String text}) e in m.events)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: skin.space.insideText),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(e.time,
                              style: mono.copyWith(
                                  color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
                          SizedBox(width: skin.space.rowGap),
                          Expanded(child: Text(e.text, style: mono)),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
