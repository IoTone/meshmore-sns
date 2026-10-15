// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math' as math;

import 'package:meshcore/meshcore.dart';

import '../meshcore/discovered_node.dart';
import 'mesh_tool.dart';

/// How a ping reaches its target. Chosen from the node's type, shown
/// to the user, never picked by them.
enum PingMethod {
  /// `CMD_SEND_STATUS_REQ` → `PUSH 0x87` (repeater / room / sensor).
  status,

  /// `CMD_SEND_TELEMETRY_REQ` → `PUSH 0x8B` (chat node; silent for the
  /// peer, answered only if it shares base telemetry with us).
  telemetry,
}

PingMethod pingMethodFor(int nodeType) => switch (nodeType) {
      kAdvTypeRepeater || kAdvTypeRoom || kAdvTypeSensor => PingMethod.status,
      _ => PingMethod.telemetry,
    };

class PingAttempt {
  PingAttempt(this.seq);
  final int seq;

  /// Null while in flight.
  bool? replied;
  int? rttMs;
  Duration? timeout;

  /// Set when the radio refused or never confirmed this attempt.
  ToolFailure? failure;
}

/// R60 T2 — round-trip to one node, N times, with loss and RTT.
class PingTool extends MeshTool {
  PingTool(super.mc, {super.now});

  static const int maxCount = 20;
  static const Duration minInterval = Duration(seconds: 5);
  static const Duration maxInterval = Duration(minutes: 2);

  String? targetPubKeyHex;
  String targetName = '';
  PingMethod method = PingMethod.telemetry;
  int count = 5;
  Duration interval = const Duration(seconds: 10);

  final List<PingAttempt> attempts = <PingAttempt>[];

  /// The last status reply (status method only).
  RepeaterStatus? lastStatus;
  DateTime? startedAt;

  int get sent => attempts.where((PingAttempt a) => a.replied != null).length;
  int get replied => attempts.where((PingAttempt a) => a.replied == true).length;
  int get lost => sent - replied;
  double? get lossPercent => sent == 0 ? null : lost * 100.0 / sent;

  List<int> get _rtts => <int>[
        for (final PingAttempt a in attempts)
          if (a.rttMs != null) a.rttMs!,
      ];
  int? get rttMin => _rtts.isEmpty ? null : _rtts.reduce(math.min);
  int? get rttMax => _rtts.isEmpty ? null : _rtts.reduce(math.max);
  int? get rttAvg => _rtts.isEmpty
      ? null
      : (_rtts.reduce((int a, int b) => a + b) / _rtts.length).round();

  void setTarget(DiscoveredNode n) {
    if (running) return;
    targetPubKeyHex = n.pubKeyHex;
    targetName = n.name;
    method = pingMethodFor(n.type);
    notifyListeners();
  }

  void configure({int? count, Duration? interval}) {
    if (running) return;
    if (count != null) this.count = count.clamp(1, maxCount);
    if (interval != null) {
      this.interval = Duration(
          milliseconds: interval.inMilliseconds.clamp(
              minInterval.inMilliseconds, maxInterval.inMilliseconds));
    }
    notifyListeners();
  }

  Future<void> start() async {
    final String? pk = targetPubKeyHex;
    if (pk == null || pk.length != kPubKeySize * 2) {
      if (!running) {
        // Surface the reason without taking the radio.
        _noTarget();
      }
      return;
    }
    if (!begin()) return;
    attempts.clear();
    lastStatus = null;
    startedAt = now();
    notifyListeners();
    final List<int> key = bytesOfHex(pk);
    final String pub6 = pk.substring(0, kPubKeyPrefixSize * 2);
    ToolFailure? fatal;
    for (int seq = 1; seq <= count && !stopRequested; seq++) {
      final DateTime t0 = now();
      final PingAttempt a = PingAttempt(seq);
      attempts.add(a);
      notifyListeners();
      try {
        final MsgSent s = await sendAwaitingSent(switch (method) {
          PingMethod.status => MeshcoreFrameCodec.sendStatusReq(key),
          PingMethod.telemetry =>
            MeshcoreFrameCodec.sendTelemetryReq(peerPubKey: key),
        });
        final DateTime sentAt = now();
        a.timeout = replyTimeoutFor(s.estTimeoutMs);
        notifyListeners();
        final MeshcoreInbound? reply = await awaitFrame<MeshcoreInbound>(
          (MeshcoreInbound f) => switch (f) {
            StatusResponseFrame(:final pubKeyPrefix) =>
              method == PingMethod.status && hexOf(pubKeyPrefix) == pub6,
            TelemetryResponseFrame(:final pubKeyPrefix) =>
              method == PingMethod.telemetry &&
                  hexOf(pubKeyPrefix) == pub6,
            _ => false,
          },
          a.timeout!,
        );
        if (stopRequested && reply == null) {
          attempts.remove(a); // cut short, not lost
          break;
        }
        a.replied = reply != null;
        if (reply != null) {
          a.rttMs = now().difference(sentAt).inMilliseconds;
          if (reply is StatusResponseFrame && reply.status != null) {
            lastStatus = reply.status;
          }
        }
      } on ToolException catch (e) {
        a
          ..replied = false
          ..failure = e.failure;
        if (e.failure == ToolFailure.unsupported ||
            e.failure == ToolFailure.notFound) {
          fatal = e.failure; // every further attempt would say the same
          notifyListeners();
          break;
        }
      }
      notifyListeners();
      if (seq < count && !stopRequested) {
        final Duration left = interval - now().difference(t0);
        if (left > Duration.zero) await pause(left);
      }
    }
    finish(fatal);
  }

  void _noTarget() {
    begin(exclusive: false);
    finish(ToolFailure.noTarget);
  }

  /// JSON export (rule 6).
  Map<String, Object?> report({String? firmware}) => <String, Object?>{
        'tool': 'ping',
        'target': targetPubKeyHex,
        'targetName': targetName,
        'method': method.name,
        'count': count,
        'intervalSec': interval.inSeconds,
        'firmware': firmware,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'sent': sent,
        'replied': replied,
        'lossPercent': lossPercent,
        'rttMinMs': rttMin,
        'rttAvgMs': rttAvg,
        'rttMaxMs': rttMax,
        'attempts': <Map<String, Object?>>[
          for (final PingAttempt a in attempts)
            <String, Object?>{
              'seq': a.seq,
              'replied': a.replied,
              'rttMs': a.rttMs,
              if (a.failure != null) 'failure': a.failure!.name,
            },
        ],
      };
}
