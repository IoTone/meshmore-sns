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
import '../util/safe_notifier.dart';
import 'tool_history.dart';
import 'trace_tool.dart';

/// R60 — owns every tool for the life of the app, so a run survives
/// leaving its screen, and enforces rule 3 of the spec: **one tool at
/// a time**. The firmware keeps a single pending remote request; two
/// tools — or a tool and the background telemetry poller — would
/// silently clear each other's. While a tool holds the radio, the
/// poller is held too.
class ToolsController extends ChangeNotifier with SafeNotifier {
  ToolsController(this.mc,
      {DateTime Function()? now, ToolHistoryStore? historyStore})
      : history = historyStore ?? ToolHistoryStore() {
    stats = RadioStatsTool(mc, now: now);
    ping = PingTool(mc, now: now);
    trace = TraceTool(mc, now: now);
    discover = DiscoverTool(mc, now: now);
    soak = SoakTool(mc, now: now);
    range = RangeTestTool(mc, now: now);
    for (final MeshTool t in _all) {
      t
        ..acquire = _acquire
        ..release = _release
        ..onFinished = _record;
    }
    // Fire and forget: a history that has not loaded yet is empty, and the
    // first recorded run loads it before writing rather than overwriting it.
    history.load();
  }

  /// Every finished run, sealed and bounded. Owned here because a run ends
  /// here, whichever screen started it.
  final ToolHistoryStore history;

  /// Keep the run that just ended.
  ///
  /// The rows come from the tool that produced them, so this knows nothing
  /// about what any of them mean: a tool with nothing to say records nothing,
  /// which is why a refused start leaves no entry in the history.
  void _record(MeshTool t, ToolFailure? failure) {
    final DateTime? began = t.beganAt;
    if (began == null) return;
    final String summary = t.runHistorySummary;
    if (summary.isEmpty) return;
    history.record(ToolRun(
      kind: kindOf(t),
      startedAt: began,
      endedAt: t.now(),
      summary: summary,
      csv: t.runHistoryCsv,
      failure: failure,
    ));
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
    history.dispose();
    super.dispose();
  }
}
