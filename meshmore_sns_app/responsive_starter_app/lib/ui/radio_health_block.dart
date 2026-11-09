// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/meshcore_controller.dart';
import '../theme/mm_skin.dart';
import '../tools/radio_stats_tool.dart';
import '../tools/tools_controller.dart';

/// What the radio itself has measured, on the screen where a user goes when
/// something sounds wrong.
///
/// Every line names its source, because a noise floor and a last-packet
/// reading answer different questions and a battery voltage is not a
/// percentage: the radio reports all four through `CMD_GET_STATS`
/// (`MyMesh.cpp` core/radio sub-types) and the app must not present the
/// radio's numbers as its own.
class RadioHealthBlock extends StatefulWidget {
  const RadioHealthBlock({super.key});

  @override
  State<RadioHealthBlock> createState() => _RadioHealthBlockState();
}

class _RadioHealthBlockState extends State<RadioHealthBlock> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _read());
  }

  /// One local read. The stats tool takes no exclusive slot, so this cannot
  /// steal the radio from a measurement the user started.
  Future<void> _read() async {
    if (!mounted) return;
    final MeshcoreController mc = context.read<MeshcoreController>();
    if (!mc.isReady) return;
    setState(() => _busy = true);
    await context.read<ToolsController>().stats.fetch();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final RadioStatsTool tool = context.watch<ToolsController>().stats;
    final MeshcoreController mc = context.watch<MeshcoreController>();
    final CoreStats? core = tool.core;
    final RadioStats? radio = tool.radio;
    final bool any = core != null || radio != null;

    Widget line(String text) => Padding(
          padding: EdgeInsets.only(top: skin.space.step(1)),
          child: Text(text,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: skin.type.sizeSm,
                fontFamily: skin.type.bodyFamily,
              )),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(l.radioHealthTitle,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: skin.type.sizeBodyLg,
                    fontFamily: skin.type.headingFamily,
                    letterSpacing: skin.type.headingTracking,
                  )),
            ),
            TextButton(
              onPressed: _busy ? null : _read,
              child: Text(_busy ? l.radioHealthReading : l.radioHealthRead),
            ),
          ],
        ),
        if (!any) line(l.radioHealthUnread),
        if (radio != null) ...<Widget>[
          line(l.radioHealthNoise('${radio.noiseFloorDbm}')),
          line(l.radioHealthLast('${radio.lastRssi}', '${radio.lastSnrDb}')),
        ],
        if (core != null)
          line(l.radioHealthBattery(core.batteryMilliVolts == 0
              ? l.radioHealthNotReported
              : (core.batteryMilliVolts / 1000).toStringAsFixed(2))),
        if (core != null) line(l.radioHealthUptime(_uptime(core.uptimeSecs))),
        // The one number here the app could not compute: the radio times its
        // own send-to-ACK and reports it on the confirmation push. Absent until
        // a direct message has been acknowledged, because a firmware that omits
        // the field must not read as a zero-millisecond round trip.
        if (mc.lastAckTripMs != null)
          line(l.radioHealthAckTrip(mc.lastAckTripMs!)),
        if (tool.fetchedAt != null) line(l.radioHealthSource),
      ],
    );
  }

  static String _uptime(int s) {
    final int d = s ~/ 86400;
    final int h = (s % 86400) ~/ 3600;
    final int m = (s % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
