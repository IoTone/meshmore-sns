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
import '../../ui/mm_shape.dart';
import 'dashboard_model.dart';
import 'my_pubkey_line.dart';

/// Daybreak — a warm morning report, rounded and friendly, the first thing read
/// with coffee.
///
/// The signature is the leading bar: every card in this skin wears a short
/// accent rule down its left edge, so a screenshot is identifiable by the
/// vermilion edges alone. That is the whole difference from Air, which is the
/// other white page: Air is a spec sheet with hairlines and a ledger, and this is
/// a report with cards. Two light skins sharing one layout would be the recolour
/// the owner objected to.
///
/// What it must not borrow: sharp corners, dark panels, gauges, and Air's ledger
/// alignment.
class DaybreakDashboard extends StatelessWidget {
  const DaybreakDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final DashboardModel m = DashboardModel.gather(mc, l);
    final Color muted = skin.color.fgMuted;

    return MmScaffold(
      child: ListView(
        padding: EdgeInsets.fromLTRB(skin.space.rowInset, skin.space.rowInset,
            skin.space.rowInset, skin.space.sectionGap),
        children: <Widget>[
          _StatusRow(m: m, skin: skin),
          SizedBox(height: skin.space.rowInset),
          // The hero card: the one number the page is about, with the status
          // beside it. The bar is the skin's signature, so it is on every card
          // and never on anything else.
          _ReportCard(
            skin: skin,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        m.peersLabel(l),
                        style: mmSectionLabelStyle(skin),
                      ),
                      SizedBox(height: skin.space.labelToControl),
                      Text(
                        '${m.peersInRange}',
                        style: TextStyle(
                          color: skin.color.fg,
                          fontFamily: skin.type.monoFamily,
                          fontSize: skin.type.size(36),
                          height: 1,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  m.statusLabel,
                  style: TextStyle(
                    color: m.alert ? skin.color.alert : muted,
                    fontSize: skin.type.sizeSm,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: skin.space.rowGap),
          // Three chips, in a Wrap: at 200 % text three pills are wider than a
          // 320 dp screen and a Row cannot give the width back.
          Wrap(
            spacing: skin.space.rowGap,
            runSpacing: skin.space.rowGap,
            children: <Widget>[
              MmStatusPill(l.dashboardKnownCount(m.knownCount)),
              if (m.contactsLabel != null)
                MmStatusPill('${l.dashForestContacts} ${m.contactsLabel!}'),
              if (m.batteryLine != null)
                MmStatusPill(m.batteryLine!),
            ],
          ),
          SizedBox(height: skin.space.rowInset),
          _ReportCard(
            skin: skin,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MmSectionHeader(l.dashboardRadio),
                SizedBox(height: skin.space.rowGap),
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
          _ReportCard(
            skin: skin,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MmSectionHeader(l.dashboardRecent),
                SizedBox(height: skin.space.rowGap),
                if (m.events.isEmpty)
                  Text(l.dashboardNoActivity,
                      style: TextStyle(color: muted))
                else
                  for (int i = 0; i < m.events.length; i++) ...<Widget>[
                    if (i > 0)
                      Divider(
                        height: skin.shape.hairlineWidth,
                        thickness: skin.shape.hairlineWidth,
                        color: skin.color.hairline,
                      ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                          vertical: skin.space.labelToControl),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // The stamp sizes to its own text and the gap is a
                          // gap. A guessed 64 dp column wrapped the last digit
                          // of "12:34:56" onto a second line at larger text and
                          // left the stamp touching the event it describes.
                          Text(
                            m.events[i].time,
                            style: TextStyle(
                                color: muted,
                                fontFamily: skin.type.monoFamily,
                                fontSize: skin.type.sizeSm,
                              ),
                          ),
                          SizedBox(width: skin.space.rowGap),
                          Expanded(
                            child: Text(
                              m.events[i].text,
                              style: TextStyle(
                                  color: skin.color.fg,
                                  fontSize: skin.type.sizeBody),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A card with the skin's leading bar.
///
/// The bar is a `Positioned` child of a `Stack`, not a `Row` cell: a row cell
/// that spans the card's height needs `IntrinsicHeight`, and intrinsic height
/// cannot be computed through a `Wrap` or a `ListView`, which is what the cards
/// hold. A stack sizes to its content and the bar stretches to it, with no
/// intrinsics anywhere.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.skin, required this.child});

  final MmSkin skin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('daybreak-card'),
      decoration: BoxDecoration(
        color: skin.color.surface,
        borderRadius: mmRadius(context, skin.shape.cornerSize),
        border:
            Border.all(color: skin.color.edge, width: skin.shape.borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.all(skin.space.rowInset),
            child: child,
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: skin.space.step(1),
            child: ColoredBox(color: skin.color.accent),
          ),
        ],
      ),
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
