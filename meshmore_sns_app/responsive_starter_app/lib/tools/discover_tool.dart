// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:math' as math;

import 'package:meshcore/meshcore.dart';

import 'mesh_tool.dart';

class DiscoveredRepeater {
  DiscoveredRepeater(this.response, this.at);
  final DiscoverResponse response;
  final DateTime at;

  String get keyHex => hexOf(response.publicKey);

  /// The weaker direction — what the link is actually worth.
  double get weakerSnrDb =>
      math.min(response.theirSnrDb, response.ourSnrDb);

  /// Over 6 dB between directions: a deaf or loud node.
  bool get asymmetric =>
      (response.theirSnrDb - response.ourSnrDb).abs() > 6.0;
}

/// R60 T4 — which repeaters hear us right now, and how well, both ways.
/// One zero-hop `NODE_DISCOVER_REQ`; repeaters answer after a random
/// delay, so we listen for [listenFor].
class DiscoverTool extends MeshTool {
  DiscoverTool(super.mc, {super.now});

  static const Duration listenFor = Duration(seconds: 12);

  /// Strongest weaker-direction first.
  final List<DiscoveredRepeater> found = <DiscoveredRepeater>[];
  DateTime? startedAt;

  Duration get remaining {
    final DateTime? s = startedAt;
    if (s == null || !running) return Duration.zero;
    final Duration left = listenFor - now().difference(s);
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> start() async {
    if (!begin()) return;
    found.clear();
    startedAt = now();
    notifyListeners();
    final int tag = randomTag();
    final StreamSubscription<MeshcoreInbound> sub =
        mc.inboundFrames.listen((MeshcoreInbound f) {
      if (f is! ControlDataFrame) return;
      final DiscoverResponse? d = f.discover;
      if (d == null || d.tag != tag) return;
      final DiscoveredRepeater r = DiscoveredRepeater(d, now());
      found
        ..removeWhere((DiscoveredRepeater x) => x.keyHex == r.keyHex)
        ..add(r)
        ..sort((DiscoveredRepeater a, DiscoveredRepeater b) =>
            b.weakerSnrDb.compareTo(a.weakerSnrDb));
      notifyListeners();
    });
    // A once-a-second tick so the countdown moves.
    final Timer tick = Timer.periodic(
        const Duration(seconds: 1), (_) => notifyListeners());
    try {
      await sendAwaitingReply(MeshcoreFrameCodec.sendDiscoverReq(tag: tag));
      await pause(listenFor);
      finish();
    } on ToolException catch (e) {
      finish(e.failure);
    } finally {
      tick.cancel();
      unawaited(sub.cancel());
    }
  }
}
