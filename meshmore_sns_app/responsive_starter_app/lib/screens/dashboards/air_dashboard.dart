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

/// Air — a white page with one blue, and a ledger.
///
/// The other six skins are instruments: a dial, a panel grid, a compass, a
/// colour block. Air has one accent and a paper ground, and on paper an
/// instrument reads as a chart with no axis. So this layout is the opposite of
/// a dashboard: one number with air around it, then a flat ledger of the four
/// facts a reader actually checks, separated by hairlines rather than boxed in
/// panels. Nothing is collapsible, because a fold on a page this short is a tap
/// that reveals one row.
///
/// What it must not borrow from the others, and why: a panel fill (a grey box on
/// white is a hole), an ornament (the skin already chose calm), a radial gauge (a
/// dark-UI device), and a saturated block (one blue spent on a block is one blue
/// not spent on the link state).
class AirDashboard extends StatelessWidget {
  const AirDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final DashboardModel m = DashboardModel.gather(mc, l);
    final TextStyle label = mmSectionLabelStyle(skin);
    final Color muted = skin.color.fgMuted;
    final Color hairline = skin.color.hairline;

    return MmScaffold(
      child: ListView(
        padding: EdgeInsets.only(bottom: skin.space.sectionGap),
        children: <Widget>[
          _StatusRow(m: m, skin: skin),
          Divider(height: hairlineWidth(skin), thickness: hairlineWidth(skin), color: hairline),
          // The signature: one number, large, with air on every side. It is the
          // only thing on this page that is allowed to be big, and that is what
          // makes a screenshot of Air recognisable.
          Padding(
            padding: EdgeInsets.fromLTRB(skin.space.screenEdge,
                skin.space.sectionGap, skin.space.screenEdge, skin.space.sectionGap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(m.peersLabel(l), style: label),
                SizedBox(height: skin.space.rowGap),
                Text(
                  '${m.peersInRange}',
                  style: TextStyle(
                    color: skin.color.fg,
                    // The mono face carries every number in this skin, and this
                    // is the number the page is about.
                    fontFamily: skin.type.monoFamily,
                    fontSize: skin.type.size(44),
                    height: 1,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                SizedBox(height: skin.space.labelToControl),
                Text(
                  m.contactsLabel == null
                      ? l.dashboardKnownCount(m.knownCount)
                      : l.dashboardKnownAndContacts(
                          m.knownCount, m.contactsLabel!),
                  style: TextStyle(color: muted, fontSize: skin.type.sizeBody),
                ),
              ],
            ),
          ),
          Divider(height: hairlineWidth(skin), thickness: hairlineWidth(skin), color: hairline),
          // The ledger. Four rows, label left and value right, hairlines between
          // instead of a panel around each. A reader scanning for the battery
          // runs their eye down one column, which a stack of panels makes
          // impossible.
          _LedgerRow(
            label: l.dashNervLink,
            value: m.statusLabel,
            skin: skin,
          ),
          if (m.radioFields != null && m.radioFields!.isNotEmpty)
            _LedgerRow(
              label: l.dashboardRadio,
              valueWidget: Align(
                alignment: Alignment.centerRight,
                child: MmValueFields(
                  fields: m.radioFields!,
                  separator: '  ',
                  color: skin.color.fg,
                ),
              ),
              skin: skin,
            ),
          _LedgerRow(
            label: l.dashNervRegion,
            value: m.region,
            skin: skin,
          ),
          if (m.batteryLine != null)
            _LedgerRow(
              label: l.batteryTitle,
              value: m.batteryLine!,
              skin: skin,
            ),
          SizedBox(height: skin.space.sectionGap),
          if (m.pubKeyHex != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: skin.space.screenEdge),
              child: MyPubkeyLine(
                pubKeyHex: m.pubKeyHex!,
                style: TextStyle(
                    color: muted,
                    fontFamily: skin.type.monoFamily,
                    fontSize: skin.type.sizeMicro),
                iconColor: muted,
              ),
            ),
          if (m.events.isNotEmpty) ...<Widget>[
            SizedBox(height: skin.space.sectionGap),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: skin.space.screenEdge),
              child: Text(l.dashNervEvents, style: label),
            ),
            SizedBox(height: skin.space.rowGap),
            // A plain list, not a panel: the page has no panels, and an event
            // list is the one place a reader wants density.
            for (final ({String time, String text}) e in m.events)
              Padding(
                padding: EdgeInsets.fromLTRB(skin.space.screenEdge,
                    skin.space.labelToControl, skin.space.screenEdge,
                    skin.space.labelToControl),
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
                      child: Text(e.text,
                          style: TextStyle(
                              color: skin.color.fg,
                              fontSize: skin.type.sizeBody)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

double hairlineWidth(MmSkin skin) => skin.shape.hairlineWidth;

/// The status row every skin starts with: what the link is, and the audio gate.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.m, required this.skin});

  final DashboardModel m;
  final MmSkin skin;

  @override
  Widget build(BuildContext context) {
    final Color c = m.alert ? skin.color.alert : skin.color.fgMuted;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          skin.space.screenEdge, skin.space.rowInset, skin.space.rowInset, skin.space.rowInset),
      child: Row(
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
      ),
    );
  }
}

/// One line of the ledger.
///
/// Two columns, label left and value right, separated by a hairline. Both
/// columns are `Expanded` and both wrap: at 320 dp with text at 200 % a fixed
/// label width plus a right-aligned value is the row that overflows, and this is
/// the layout where that would show first.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.label,
    required this.skin,
    this.value,
    this.valueWidget,
  }) : assert(value != null || valueWidget != null, 'a ledger row needs a value');

  final String label;
  final MmSkin skin;
  final String? value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: skin.space.screenEdge, vertical: skin.space.rowInset),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 2,
                child: Text(
                  label,
                  style: TextStyle(
                      color: skin.color.fgMuted, fontSize: skin.type.sizeBody),
                ),
              ),
              SizedBox(width: skin.space.rowGap),
              Expanded(
                flex: 3,
                child: valueWidget ??
                    Text(
                      value!,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: skin.color.fg,
                        fontFamily: skin.type.monoFamily,
                        fontSize: skin.type.sizeBody,
                      ),
                    ),
              ),
            ],
          ),
        ),
        Divider(
          height: skin.shape.hairlineWidth,
          thickness: skin.shape.hairlineWidth,
          color: skin.color.hairline,
        ),
      ],
    );
  }
}
