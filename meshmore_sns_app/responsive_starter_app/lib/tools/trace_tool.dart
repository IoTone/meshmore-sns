// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:meshcore/meshcore.dart';

import '../meshcore/discovered_node.dart';
import 'mesh_tool.dart';

/// The trace path for [n], or null when there is nothing to trace.
///
/// A trace only travels through repeaters (each appends the SNR it
/// heard at), so:
/// - a repeater/room is traced along its route **plus its own hash**;
/// - any other contact is traced along the repeater chain toward it;
/// - with [roundTrip], the chain is mirrored so the packet comes back
///   to us and our own radio reports the last hop: `a b` → `a b a`.
///
/// Null when the route is unknown (flood / advert-only).
///
/// [hashSize] is the radio's negotiated bytes-per-hop, from `DEVICE_INFO`
/// (`path_hash_mode + 1`, 1–3). A path is a sequence of truncated public keys
/// at *that* width, so appending one byte on a mesh configured for two is a
/// packet addressed to nobody. It is one byte only on a default mesh, which is
/// why a hardcoded byte survived.
///
/// A **direct neighbour** is a legitimate target, not a missing one: a contact
/// whose `out_path_len` is 0 has no route bytes because it is one hop away, and
/// a trace to it is addressed with its own hash as a single-hop path. Refusing
/// it (the guard this replaced) made "trace the node next to me" impossible,
/// which is the one case a person can actually verify by hand.
List<int>? tracePathFor(DiscoveredNode n,
    {bool roundTrip = true, int hashSize = 1}) {
  final List<int>? route = n.outPathHashes;
  if (route == null) return null;
  final bool relays = n.type == kAdvTypeRepeater || n.type == kAdvTypeRoom;
  final int hs = hashSize.clamp(1, 3);
  final List<int> ownHash = n.pubKeyHex.length >= hs * 2
      ? bytesOfHex(n.pubKeyHex.substring(0, hs * 2)).toList()
      : <int>[];
  final List<int> out = <int>[
    ...route,
    if (relays || route.isEmpty) ...ownHash,
  ];
  if (out.isEmpty) return null;
  if (!roundTrip || out.length == 1) return out;
  return <int>[...out, ...out.reversed.skip(1)];
}

/// Parse `a1,7f a1` / `a17fa1` into one-byte hashes; null if invalid.
List<int>? parseManualPath(String text) {
  final String t = text.replaceAll(RegExp(r'[\s,:\-]'), '').toLowerCase();
  if (t.isEmpty || t.length.isOdd || t.length > kMaxPathSize * 2) {
    return null;
  }
  if (!RegExp(r'^[0-9a-f]+$').hasMatch(t)) return null;
  return bytesOfHex(t).toList();
}

class TraceRun {
  TraceRun({required this.path, required this.label, required this.at});
  final List<int> path;
  final String label;
  final DateTime at;

  /// Null while in flight.
  TraceResult? result;
  bool lost = false;
  int? rttMs;
  ToolFailure? failure;

  bool get done => result != null || lost || failure != null;

  /// The hop with the lowest SNR, as (index, snr). Index == path length
  /// means the final hop into our own radio.
  (int, double)? get weakest {
    final TraceResult? r = result;
    if (r == null) return null;
    final List<double> all = <double>[...r.hopSnrsDb, r.finalSnrDb];
    int idx = 0;
    for (int i = 1; i < all.length; i++) {
      if (all[i] < all[idx]) idx = i;
    }
    return (idx, all[idx]);
  }
}

/// R60 T3 — per-hop SNR along a repeater chain, there and back.
class TraceTool extends MeshTool {
  TraceTool(super.mc, {super.now});

  /// Results kept for comparison during the session.
  static const int historySize = 10;

  /// Newest first.
  final List<TraceRun> runs = <TraceRun>[];

  Future<void> trace(List<int> path, {String label = ''}) async {
    if (path.isEmpty) {
      if (begin(exclusive: false)) finish(ToolFailure.noTarget);
      return;
    }
    if (!begin()) return;
    final TraceRun run = TraceRun(path: path, label: label, at: now());
    runs.insert(0, run);
    if (runs.length > historySize) runs.removeLast();
    notifyListeners();
    final int tag = randomTag();
    try {
      final MsgSent s = await sendAwaitingSent(
          MeshcoreFrameCodec.sendTracePath(tag: tag, path: path));
      final DateTime sentAt = now();
      final TraceDataFrame? f = await awaitFrame<TraceDataFrame>(
        (TraceDataFrame f) => f.trace.tag == tag,
        replyTimeoutFor(s.estTimeoutMs),
      );
      if (f == null) {
        run.lost = !stopRequested;
        if (stopRequested) runs.remove(run);
      } else {
        run
          ..result = f.trace
          ..rttMs = now().difference(sentAt).inMilliseconds;
      }
      finish();
    } on ToolException catch (e) {
      run.failure = e.failure;
      finish(e.failure);
    }
  }

  /// `CMD_RESET_PATH` — drop the contact to flood so the mesh finds a
  /// new route (the classic hop-test move). True on OK.
  Future<bool> resetPath(String pubKeyHex) async {
    if (!begin()) return false;
    try {
      await sendAwaitingReply(
          MeshcoreFrameCodec.resetPath(bytesOfHex(pubKeyHex)));
      finish();
      // The contact's stored route is now stale; resync.
      await mc.requestContacts();
      return true;
    } on ToolException catch (e) {
      finish(e.failure);
      return false;
    }
  }
}
