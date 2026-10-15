// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';

import '../meshcore/meshcore_controller.dart';
import 'discover_tool.dart';
import 'mesh_tool.dart';
import 'ping_tool.dart';
import 'radio_stats_tool.dart';
import 'range_test_tool.dart';
import 'soak_tool.dart';
import 'trace_tool.dart';

/// R60 — owns every tool for the life of the app, so a run survives
/// leaving its screen, and enforces rule 3 of the spec: **one tool at
/// a time**. The firmware keeps a single pending remote request; two
/// tools — or a tool and the background telemetry poller — would
/// silently clear each other's. While a tool holds the radio, the
/// poller is held too.
class ToolsController extends ChangeNotifier {
  ToolsController(this.mc, {DateTime Function()? now}) {
    stats = RadioStatsTool(mc, now: now);
    ping = PingTool(mc, now: now);
    trace = TraceTool(mc, now: now);
    discover = DiscoverTool(mc, now: now);
    soak = SoakTool(mc, now: now);
    range = RangeTestTool(mc, now: now);
    for (final MeshTool t in _all) {
      t
        ..acquire = _acquire
        ..release = _release;
    }
  }

  final MeshcoreController mc;

  late final RadioStatsTool stats;
  late final PingTool ping;
  late final TraceTool trace;
  late final DiscoverTool discover;
  late final SoakTool soak;
  late final RangeTestTool range;

  List<MeshTool> get _all =>
      <MeshTool>[stats, ping, trace, discover, soak, range];

  MeshTool? _holder;

  /// The tool holding the radio, if any.
  ToolKind? get running => _holder == null ? null : kindOf(_holder!);

  ToolKind kindOf(MeshTool t) => switch (t) {
        RadioStatsTool() => ToolKind.stats,
        PingTool() => ToolKind.ping,
        TraceTool() => ToolKind.trace,
        DiscoverTool() => ToolKind.discover,
        SoakTool() => ToolKind.soak,
        RangeTestTool() => ToolKind.range,
        _ => throw ArgumentError(t),
      };

  MeshTool toolFor(ToolKind k) => switch (k) {
        ToolKind.stats => stats,
        ToolKind.ping => ping,
        ToolKind.trace => trace,
        ToolKind.discover => discover,
        ToolKind.soak => soak,
        ToolKind.range => range,
      };

  bool _acquire(MeshTool t) {
    if (_holder != null && !identical(_holder, t)) return false;
    _holder = t;
    mc.holdBackgroundRequests(true);
    notifyListeners();
    return true;
  }

  void _release(MeshTool t) {
    if (!identical(_holder, t)) return;
    _holder = null;
    mc.holdBackgroundRequests(false);
    notifyListeners();
  }

  /// Stop whichever tool holds the radio.
  void stopRunning() => _holder?.stop();

  @override
  void dispose() {
    for (final MeshTool t in _all) {
      t.stop();
      t.dispose();
    }
    super.dispose();
  }
}
