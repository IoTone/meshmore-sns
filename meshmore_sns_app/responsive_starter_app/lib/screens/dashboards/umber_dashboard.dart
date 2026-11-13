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
import 'dashboard_model.dart';
import 'my_pubkey_line.dart';

/// Umber — a warm dark workbench where every instrument is within reach and
/// nothing is decorated.
///
/// The signature is a gauge cluster: four numbers in a square, divided by
/// hairlines, with no panel around them. A workbench is read by glancing at the
/// instruments, not by reading a list, so the four facts a reader checks most
/// are the first thing on the page and they are all in one place.
///
/// What it must not borrow: DR Pop's saturated blocks (one warm orange spent on
/// a block fights the browns), AG-HUD's sweep (this palette is a static
/// workbench), and NERV's hazard stripes, which this palette has no role for.
class UmberDashboard extends StatelessWidget {
  const UmberDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final DashboardModel m = DashboardModel.gather(mc, l);
    final Color muted = skin.color.fgMuted;

    final List<Widget> cells = <Widget>[
      MmReadout(
        label: m.peersLabel(l),
        value: '${m.peersInRange}',
        emphasize: true,
      ),
      MmReadout(label: l.dashNervKnown, value: '${m.knownCount}'),
      if (m.contactsLabel != null)
        MmReadout(label: l.dashForestContacts, value: m.contactsLabel!),
      if (m.batteryLine != null)
        MmReadout(label: l.dashboardBattery, value: m.batteryLine!),
    ];

    return MmScaffold(
      child: ListView(
        padding: EdgeInsets.fromLTRB(skin.space.rowInset, skin.space.rowInset,
            skin.space.rowInset, skin.space.sectionGap),
        children: <Widget>[
          _StatusRow(m: m, skin: skin),
          SizedBox(height: skin.space.rowInset),
          // The cluster. Two by two while there is room for two columns and the
          // text is at its normal size; one by four otherwise, because a 2 by 2
          // of readouts at 200 % text is four labels fighting for 160 dp each.
          LayoutBuilder(builder: (BuildContext c, BoxConstraints box) {
            final bool twoUp = box.maxWidth >= 360 &&
                MediaQuery.textScalerOf(c).scale(1) <= 1.3;
            return _Cluster(cells: cells, twoUp: twoUp, skin: skin);
          }),
          SizedBox(height: skin.space.rowInset),
          // The radio's own settings, on the surface, full width, no rounding:
          // a strip of instrument labels rather than a card.
          Container(
            width: double.infinity,
            color: skin.color.surface,
            padding: EdgeInsets.symmetric(
                horizontal: skin.space.rowInset, vertical: skin.space.rowGap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (m.radioFields == null)
                  Text(l.dashboardAwaitingDevice,
                      style: TextStyle(color: muted))
                else
                  MmValueFields(
                    fields: m.radioFields!,
                    separator: '  ',
                    color: skin.color.fg,
                  ),
                SizedBox(height: skin.space.labelToControl),
                Text(
                  '${l.dashNervRegion}  ${m.region}',
                  style: TextStyle(
                    color: muted,
                    fontFamily: skin.type.monoFamily,
                    fontSize: skin.type.sizeBody,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: skin.space.rowInset),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: skin.space.rowInset),
            child: MyPubkeyLine(
              pubKeyHex: m.pubKeyHex,
              style: TextStyle(
                  color: muted,
                  fontFamily: skin.type.monoFamily,
                  fontSize: skin.type.sizeMicro),
              iconColor: muted,
            ),
          ),
          SizedBox(height: skin.space.rowInset),
          MmPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MmSectionHeader(l.dashboardRecent),
                SizedBox(height: skin.space.rowGap),
                if (m.events.isEmpty)
                  Text(l.dashboardNoActivity,
                      style: TextStyle(color: muted))
                else
                  for (final ({String time, String text}) e in m.events)
                    Padding(
                      padding:
                          EdgeInsets.only(bottom: skin.space.labelToControl),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: skin.space.step(9) * 2,
                            child: Text(
                              e.time,
                              style: TextStyle(
                                color: muted,
                                fontFamily: skin.type.monoFamily,
                                fontSize: skin.type.sizeSm,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e.text,
                              style: TextStyle(
                                  color: skin.color.fg,
                                  fontSize: skin.type.sizeBody),
                            ),
                          ),
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

/// Four readouts in a square, divided by hairlines rather than boxed in panels.
///
/// The dividers are the whole design: a panel around each number would be four
/// boxes, and a workbench has one instrument face, not four.
class _Cluster extends StatelessWidget {
  const _Cluster({
    required this.cells,
    required this.twoUp,
    required this.skin,
  });

  final List<Widget> cells;
  final bool twoUp;
  final MmSkin skin;

  @override
  Widget build(BuildContext context) {
    final double line = skin.shape.hairlineWidth;
    final Color rule = skin.color.hairline;
    if (!twoUp) {
      return Column(
        key: const ValueKey<String>('umber-cluster'),
        children: <Widget>[
          for (int i = 0; i < cells.length; i++) ...<Widget>[
            if (i > 0) Divider(height: line, thickness: line, color: rule),
            Padding(
              padding: EdgeInsets.symmetric(vertical: skin.space.rowGap),
              child: cells[i],
            ),
          ],
        ],
      );
    }
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 2) {
      final bool hasSecond = i + 1 < cells.length;
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: cells[i]),
          if (hasSecond) ...<Widget>[
            VerticalDivider(width: skin.space.rowInset, thickness: line, color: rule),
            Expanded(child: cells[i + 1]),
          ],
        ],
      ));
    }
    return Column(
      key: const ValueKey<String>('umber-cluster'),
      children: <Widget>[
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) Divider(height: line, thickness: line, color: rule),
          Padding(
            padding: EdgeInsets.symmetric(vertical: skin.space.rowGap),
            child: rows[i],
          ),
        ],
      ],
    );
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
