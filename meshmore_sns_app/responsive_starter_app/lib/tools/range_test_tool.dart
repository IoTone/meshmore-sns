// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import '../bot/bot_scope.dart';
import '../meshcore/chat_message.dart';
import '../meshcore/own_location.dart';
import '../util/geo.dart' as geo;
import 'mesh_tool.dart';
import 'soak_tool.dart' show scopeRefusal;

enum RangeMode { sender, receiver }

class RangeRow {
  RangeRow({
    required this.seq,
    required this.at,
    this.snrDb,
    required this.flood,
    this.senderLat,
    this.senderLon,
    this.rxLat,
    this.rxLon,
  });
  final int seq;
  final DateTime at;
  final double? snrDb;
  final bool flood;
  final double? senderLat;
  final double? senderLon;
  final double? rxLat;
  final double? rxLon;

  double? get distanceM =>
      senderLat == null || senderLon == null || rxLat == null || rxLon == null
          ? null
          : geo.haversineMeters(senderLat!, senderLon!, rxLat!, rxLon!);
}

/// R60 T6 — Meshtastic-style range test on a private channel. One radio
/// beacons `RT <seq> <lat>,<lon>`; another walks and logs what it hears
/// with SNR and distance, for CSV export.
class RangeTestTool extends MeshTool {
  RangeTestTool(super.mc, {super.now});

  static const Duration minInterval = Duration(seconds: 15);

  /// Meshtastic's own cap on an unattended range test.
  static const Duration maxDuration = Duration(hours: 8);
  static const int maxCount = 1000;

  RangeMode mode = RangeMode.sender;
  int? channelIdx;
  String channelLabel = '';
  int count = 100;
  Duration interval = const Duration(seconds: 30);

  DateTime? startedAt;

  /// Sender: beacons sent so far.
  int beaconsSent = 0;

  /// Receiver: newest first.
  final List<RangeRow> rows = <RangeRow>[];

  static final RegExp _beacon =
      RegExp(r'(?:^|\s|:)RT (\d+)(?: (-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?))?');

  void configure({
    RangeMode? mode,
    int? channelIdx,
    String? channelLabel,
    int? count,
    Duration? interval,
  }) {
    if (running) return;
    if (mode != null) this.mode = mode;
    if (channelIdx != null) this.channelIdx = channelIdx;
    if (channelLabel != null) this.channelLabel = channelLabel;
    if (count != null) this.count = count.clamp(1, maxCount);
    if (interval != null) {
      this.interval = interval < minInterval ? minInterval : interval;
    }
    notifyListeners();
  }

  /// The beacon text for [seq] at [loc].
  static String beaconText(int seq, OwnLocation? loc) => loc == null
      ? 'RT $seq'
      : 'RT $seq ${loc.latitude.toStringAsFixed(5)},'
          '${loc.longitude.toStringAsFixed(5)}';

  // --- receiver summaries ---

  int get received => rows.length;

  /// Seqs missing between the lowest and highest heard.
  int get lost {
    if (rows.isEmpty) return 0;
    final Set<int> seen = <int>{for (final RangeRow r in rows) r.seq};
    final int lo = seen.reduce((int a, int b) => a < b ? a : b);
    final int hi = seen.reduce((int a, int b) => a > b ? a : b);
    return (hi - lo + 1) - seen.length;
  }

  double? get bestSnrDb {
    double? best;
    for (final RangeRow r in rows) {
      if (r.snrDb != null && (best == null || r.snrDb! > best)) best = r.snrDb;
    }
    return best;
  }

  double? get farthestM {
    double? far;
    for (final RangeRow r in rows) {
      final double? d = r.distanceM;
      if (d != null && (far == null || d > far)) far = d;
    }
    return far;
  }

  Future<void> start() async {
    final int? idx = channelIdx;
    if (idx == null) {
      if (begin(exclusive: false)) finish(ToolFailure.noTarget);
      return;
    }
    final ToolFailure? refusal = scopeRefusal(ChannelScope(idx), mc.channelPsk);
    if (refusal != null) {
      if (begin(exclusive: false)) finish(refusal);
      return;
    }
    if (!begin()) return;
    startedAt = now();
    beaconsSent = 0;
    rows.clear();
    notifyListeners();
    if (mode == RangeMode.sender) {
      await _send(idx);
    } else {
      await _receive(idx);
    }
  }

  Future<void> _send(int idx) async {
    final DateTime end = now().add(maxDuration);
    for (int seq = 1;
        seq <= count && !stopRequested && now().isBefore(end);
        seq++) {
      final DateTime t0 = now();
      await mc.sendChannelTextTo(idx, beaconText(seq, mc.ownLocation));
      beaconsSent = seq;
      notifyListeners();
      if (!mc.isReady) break;
      if (seq < count && !stopRequested) {
        final Duration left = interval - now().difference(t0);
        if (left > Duration.zero) await pause(left);
      }
    }
    finish(mc.isReady ? null : ToolFailure.notConnected);
  }

  Future<void> _receive(int idx) async {
    final StreamSubscription<ChatMessage> sub = mc.incomingChannelMessages
        .where((ChatMessage m) => m.channelIdx == idx)
        .listen(_onMessage);
    // Listen until stopped (or the 8 h cap).
    await pause(maxDuration);
    unawaited(sub.cancel());
    finish();
  }

  void _onMessage(ChatMessage m) {
    final RegExpMatch? hit = _beacon.firstMatch(m.text);
    if (hit == null) return;
    final OwnLocation? here = mc.ownLocation;
    rows.insert(
      0,
      RangeRow(
        seq: int.parse(hit.group(1)!),
        at: now(),
        snrDb: m.snrDb,
        flood: m.isFlood,
        senderLat: double.tryParse(hit.group(2) ?? ''),
        senderLon: double.tryParse(hit.group(3) ?? ''),
        rxLat: here?.latitude,
        rxLon: here?.longitude,
      ),
    );
    notifyListeners();
  }

  /// CSV, oldest first (rule 6).
  String exportCsv() {
    final StringBuffer b = StringBuffer(
        'seq,time,snr_db,flood,sender_lat,sender_lon,rx_lat,rx_lon,'
        'distance_m\n');
    for (final RangeRow r in rows.reversed) {
      b.writeln(<Object?>[
        r.seq,
        r.at.toUtc().toIso8601String(),
        r.snrDb,
        r.flood ? 1 : 0,
        r.senderLat,
        r.senderLon,
        r.rxLat,
        r.rxLon,
        r.distanceM?.round(),
      ].map((Object? v) => v ?? '').join(','));
    }
    return b.toString();
  }
}
