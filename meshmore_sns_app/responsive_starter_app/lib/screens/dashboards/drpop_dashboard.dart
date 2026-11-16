// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../gen/app_localizations.dart';
import '../../meshcore/meshcore_controller.dart';
import '../../theme/mm_skin.dart';
import '../../ui/mm_audio_toggle.dart';
import '../../ui/mm_scaffold.dart';
import 'dashboard_model.dart';
import 'my_pubkey_line.dart';

/// Concept E — **DR Pop** dashboard: Designers-Republic maximalism. Flat
/// saturated colour blocks, bold numerals, katakana run as graphics, and
/// a fake generated "sub-brand" per channel (the Wipeout team-livery idea
/// applied to mesh channels). Loud and graphic; the parity rules keep
/// colour from being a sole information carrier (every block carries a
/// label + value too). Same DashboardModel as every skin.
class DrPopDashboard extends StatelessWidget {

  const DrPopDashboard({super.key});

  // Wipeout-flavoured fake corp names + katakana, picked deterministically
  // per channel so a channel always wears the same livery.
  static const List<String> _brands = <String>[
    'AURICOM', 'FEISAR', 'QIREX', 'AG-SYS', 'PIRHANA', 'GOTEKI',
    'ASSEGAI', 'TIGRON',
  ];
  static const List<String> _kata = <String>[
    'ツウシン', 'ノード', 'メッシュ', 'デンパ', 'コウシン',
  ];

  @override
  Widget build(BuildContext context) {
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final DashboardModel m = DashboardModel.gather(mc, l);

    final Color magenta = skin.color.accent;
    final Color acid = skin.color.ok;
    const Color cyan = Color(0xFF00C2FF);
    final List<Color> livery = <Color>[magenta, acid, cyan];

    final int ch = mc.activeChannel;
    final int hash = ch.abs();
    final String brand = _brands[hash % _brands.length];
    final Color brandColor = livery[hash % livery.length];
    final String kata = _kata[hash % _kata.length];
    final int act = mc.messagesFor(ch).length;

    return MmScaffold(
      child: ListView(
        padding: EdgeInsets.fromLTRB(skin.space.rowInset, skin.space.rowInset, skin.space.rowInset, skin.space.sectionGap),
        children: <Widget>[
          // Brand bar — magenta slab + PHASE code.
          Row(
            children: <Widget>[
              Expanded(
                child: Text('DR POP',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: skin.type.headingFamily,
                        color: magenta,
                        fontSize: skin.type.sizeXl,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w800)),
              ),
              Text('PHASE_${ch.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      color: skin.color.fgMuted,
                      fontFamily: skin.type.monoFamily,
                      fontSize: skin.type.sizeBody,
                      letterSpacing: 1)),
              const MmAudioToggle(),
              IconButton(
                tooltip: 'BLE',
                icon: Icon(Icons.bluetooth,
                    size: 20,
                    color: m.alert ? skin.color.alert : magenta),
                onPressed: () => context.push('/settings/connection'),
              ),
            ],
          ),
          SizedBox(height: skin.space.rowGap),
          // Hero row — PEERS (acid) + STATUS (magenta / alert).
          Row(
            children: <Widget>[
              Expanded(
                child: _Block(
                  skin: skin,
                  color: acid,
                  label: l.dashPeers,
                  value: '${m.peersInRange}',
                  accent: 'ノード',
                ),
              ),
              SizedBox(width: skin.space.rowGap),
              Expanded(
                child: _Block(
                  skin: skin,
                  color: m.alert ? skin.color.alert : magenta,
                  label: l.dashDrPopLink,
                  value: m.statusLabel,
                  valueSize: 18,
                  accent: 'ツウシン',
                ),
              ),
            ],
          ),
          SizedBox(height: skin.space.rowGap),
          // Channel sub-brand block — the generated livery.
          _SubBrandBlock(
            skin: skin,
            color: brandColor,
            brand: brand,
            channel: m.channelLabel,
            kata: kata,
            activity: act,
          ),
          SizedBox(height: skin.space.rowGap),
          // KNOWN + BATTERY row.
          Row(
            children: <Widget>[
              Expanded(
                child: _Block(
                  skin: skin,
                  color: cyan,
                  label: l.dashNervKnown,
                  value: '${m.knownCount}',
                  accent: 'メッシュ',
                ),
              ),
              SizedBox(width: skin.space.rowGap),
              Expanded(
                child: _Block(
                  skin: skin,
                  color: skin.color.surfaceAlt,
                  label: l.dashboardBattery,
                  value: m.batteryLine ?? '—',
                  valueSize: 20,
                  outline: true,
                ),
              ),
            ],
          ),
          SizedBox(height: skin.space.rowGap),
          // Radio line as a thin coded strip.
          Container(
            width: double.infinity,
            color: skin.color.surface,
            padding: EdgeInsets.symmetric(horizontal: skin.space.rowInset, vertical: skin.space.rowGap),
            child: Text(
                '通信 ${m.radioLine ?? '—'}'
                '${m.contactsLabel != null ? '  ·  ${l.dashContacts} ${m.contactsLabel}' : ''}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: skin.color.fg,
                    fontFamily: skin.type.monoFamily,
                    fontSize: skin.type.sizeBody)),
          ),
          // Own pubkey — the identifier another operator needs to add
          // you before their DMs can route.
          Container(
            width: double.infinity,
            color: skin.color.surface,
            padding: EdgeInsets.fromLTRB(skin.space.rowInset, skin.space.insideText, skin.space.rowInset, skin.space.rowGap),
            child: MyPubkeyLine(
              pubKeyHex: m.pubKeyHex,
              style: TextStyle(
                  color: skin.color.fg,
                  fontFamily: skin.type.monoFamily,
                  fontSize: skin.type.sizeBody),
            ),
          ),
        ],
      ),
    );
  }
}

/// A flat saturated colour block. Text colour flips to dark or light for
/// contrast against the block — never relying on colour alone (parity).
class _Block extends StatelessWidget {
  const _Block({
    required this.skin,
    required this.color,
    required this.label,
    required this.value,
    this.accent,
    this.valueSize = 40,
    this.outline = false,
  });

  final MmSkin skin;
  final Color color;
  final String label;
  final String value;
  final String? accent;
  final double valueSize;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    final Color ink =
        color.computeLuminance() > 0.45 ? const Color(0xFF101014) : skin.color.fg;
    final Color sub = ink.withValues(alpha: 0.7);
    return Container(
      // A floor, not a fixed height: the block grid reads as equal blocks at
      // normal text, and at 200 % the label, the numeral and the accent need
      // more room than 116 dp, which overflowed by 52 px on a 320 dp phone.
      constraints: const BoxConstraints(minHeight: 116),
      padding: EdgeInsets.fromLTRB(skin.space.rowInset, skin.space.rowGap,
          skin.space.rowInset, skin.space.rowGap),
      decoration: BoxDecoration(
        color: outline ? skin.color.surface : color,
        border: outline ? Border.all(color: color, width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: TextStyle(
                  color: outline ? skin.color.fgMuted : sub,
                  fontSize: skin.type.sizeSm,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700)),
          // A gap, not a Spacer: with a height floor instead of a fixed
          // height the column has no bounded space to distribute, and a flex
          // child there is a layout error rather than a layout.
          SizedBox(height: skin.space.labelToControl),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: outline ? skin.color.fg : ink,
                  fontFamily: skin.type.monoFamily,
                  fontSize: valueSize,
                  height: 1.0,
                  fontWeight: FontWeight.w700)),
          if (accent != null) ...<Widget>[
            SizedBox(height: skin.space.labelToControl),
            Text(accent!,
                style: TextStyle(
                    color: outline ? skin.color.fgMuted : sub,
                    fontSize: skin.type.sizeBodyLg,
                    letterSpacing: 2)),
          ],
        ],
      ),
    );
  }
}

class _SubBrandBlock extends StatelessWidget {
  const _SubBrandBlock({
    required this.skin,
    required this.color,
    required this.brand,
    required this.channel,
    required this.kata,
    required this.activity,
  });

  final MmSkin skin;
  final Color color;
  final String brand;
  final String channel;
  final String kata;
  final int activity;

  @override
  Widget build(BuildContext context) {
    final Color ink =
        color.computeLuminance() > 0.45 ? const Color(0xFF101014) : skin.color.fg;
    final int filled = (activity.clamp(0, 5));
    final String bars =
        '${'▮' * filled}${'▯' * (5 - filled)}';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(skin.space.rowInset, skin.space.rowInset, skin.space.rowInset, skin.space.rowInset),
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // The brand tag is unbounded text in a Row: at 200 % on a 320 dp
              // phone it pushed 229 px past the edge. It takes what is left and
              // ellipsises; the katakana tag keeps its own room.
              Expanded(
                child: Text('[$brand·NET]',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: ink,
                        fontFamily: skin.type.monoFamily,
                        fontSize: skin.type.size(14),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1)),
              ),
              SizedBox(width: skin.space.rowGap),
              Text(kata,
                  style: TextStyle(
                      color: ink.withValues(alpha: 0.75),
                      fontSize: skin.type.size(14),
                      letterSpacing: 3)),
            ],
          ),
          SizedBox(height: skin.space.rowGap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              // The channel name is the loudest thing in this skin, and at
              // 200 % it is wider than the phone. It scales down inside the
              // room it has rather than pushing the activity bars off the card.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(channel,
                      style: TextStyle(
                          color: ink,
                          fontFamily: skin.type.monoFamily,
                          fontSize: skin.type.size(30),
                          height: 1.0,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              SizedBox(width: skin.space.rowGap),
              Text(bars,
                  style: TextStyle(
                      color: ink, fontSize: skin.type.size(18), letterSpacing: 1)),
            ],
          ),
        ],
      ),
    );
  }
}
