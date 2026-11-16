// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:meshcore/meshcore.dart';

import 'mesh_tool.dart';

/// R60 T1 — what the radio itself has seen: `CMD_GET_STATS` core,
/// radio and packets. A local read, so it doesn't take the radio from
/// other tools.
class RadioStatsTool extends MeshTool {
  RadioStatsTool(super.mc, {super.now});

  /// How often [auto] refreshes.
  static const Duration autoInterval = Duration(seconds: 5);

  CoreStats? core;
  RadioStats? radio;
  PacketStats? packets;

  /// The packet counters before the latest fetch, for `+N` deltas.
  PacketStats? previousPackets;

  DateTime? fetchedAt;

  Timer? _autoTimer;
  bool get auto => _autoTimer != null;

  /// TX + RX airtime as a share of uptime, in percent. Null until both
  /// core and radio stats are in, or before the radio has been up.
  double? get dutyCyclePercent {
    final int? up = core?.uptimeSecs;
    final RadioStats? r = radio;
    if (up == null || up <= 0 || r == null) return null;
    return (r.txAirSecs + r.rxAirSecs) * 100.0 / up;
  }

  double? get txDutyCyclePercent {
    final int? up = core?.uptimeSecs;
    final RadioStats? r = radio;
    if (up == null || up <= 0 || r == null) return null;
    return r.txAirSecs * 100.0 / up;
  }

  /// One fetch of all three sub-types. An unsupported command ends the
  /// fetch with [ToolFailure.unsupported].
  Future<void> fetch() async {
    if (!begin(exclusive: false)) return;
    try {
      for (final int sub in <int>[
        kStatsTypeCore,
        kStatsTypeRadio,
        kStatsTypePackets,
      ]) {
        final MeshcoreInbound f = await sendAwaitingReply(
          MeshcoreFrameCodec.getStats(sub),
          accept: (MeshcoreInbound g) => g is StatsFrame && _isSub(g, sub),
        );
        final StatsFrame s = f as StatsFrame;
        if (s.core != null) core = s.core;
        if (s.radio != null) radio = s.radio;
        if (s.packets != null) {
          previousPackets = packets;
          packets = s.packets;
        }
      }
      fetchedAt = now();
      finish();
    } on ToolException catch (e) {
      if (e.failure == ToolFailure.unsupported) setAuto(false);
      finish(e.failure);
    }
  }

  static bool _isSub(StatsFrame f, int sub) => switch (sub) {
        kStatsTypeCore => f.core != null,
        kStatsTypeRadio => f.radio != null,
        _ => f.packets != null,
      };

  /// Refresh every [autoInterval] while on (and once now).
  void setAuto(bool on) {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (on) {
      _autoTimer = Timer.periodic(autoInterval, (_) {
        if (!running) unawaited(fetch());
      });
      if (!running) unawaited(fetch());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }
}
