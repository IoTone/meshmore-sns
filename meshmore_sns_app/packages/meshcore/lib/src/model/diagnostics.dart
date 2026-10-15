// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

/// R60 — the measurement payloads behind the Tools screens.
///
/// Layouts are from `examples/companion_radio/MyMesh.cpp` and
/// `examples/simple_repeater/MyMesh.h` (meshcore-dev/MeshCore main,
/// checked 2026-10-14). These commands are newer than the codec's
/// pinned tag; firmware that lacks one answers `ERR_CODE_UNSUPPORTED_CMD`.

/// `RESP_CODE_STATS` (0x18) sub-type 0 — the radio's own housekeeping.
class CoreStats {
  const CoreStats({
    required this.batteryMilliVolts,
    required this.uptimeSecs,
    required this.errFlags,
    required this.queueLen,
  });
  final int batteryMilliVolts;
  final int uptimeSecs;
  final int errFlags;
  final int queueLen;

  @override
  String toString() => 'CoreStats(batt: ${batteryMilliVolts}mV, '
      'up: ${uptimeSecs}s, err: 0x${errFlags.toRadixString(16)}, '
      'queue: $queueLen)';
}

/// `RESP_CODE_STATS` (0x18) sub-type 1 — what the radio hears.
class RadioStats {
  const RadioStats({
    required this.noiseFloorDbm,
    required this.lastRssi,
    required this.lastSnrDb,
    required this.txAirSecs,
    required this.rxAirSecs,
  });
  final int noiseFloorDbm;
  final int lastRssi;
  final double lastSnrDb;
  final int txAirSecs;
  final int rxAirSecs;

  @override
  String toString() => 'RadioStats(noise: $noiseFloorDbm dBm, '
      'rssi: $lastRssi, snr: $lastSnrDb, tx: ${txAirSecs}s, '
      'rx: ${rxAirSecs}s)';
}

/// `RESP_CODE_STATS` (0x18) sub-type 2 — packet counters since boot.
class PacketStats {
  const PacketStats({
    required this.received,
    required this.sent,
    required this.sentFlood,
    required this.sentDirect,
    required this.receivedFlood,
    required this.receivedDirect,
    this.receiveErrors,
  });
  final int received;
  final int sent;
  final int sentFlood;
  final int sentDirect;
  final int receivedFlood;
  final int receivedDirect;

  /// Absent on firmware that predates the field.
  final int? receiveErrors;

  @override
  String toString() => 'PacketStats(rx: $received, tx: $sent, '
      'txFlood: $sentFlood, txDirect: $sentDirect, rxFlood: $receivedFlood, '
      'rxDirect: $receivedDirect, rxErr: $receiveErrors)';
}

/// A repeater's (or sensor's) answer to `CMD_SEND_STATUS_REQ`: the
/// `RepeaterStats` struct. The trailing fields grew over firmware
/// releases, so the late ones are nullable.
class RepeaterStatus {
  const RepeaterStatus({
    required this.batteryMilliVolts,
    required this.txQueueLen,
    required this.noiseFloorDbm,
    required this.lastRssi,
    required this.packetsReceived,
    required this.packetsSent,
    required this.airTimeSecs,
    required this.uptimeSecs,
    this.sentFlood,
    this.sentDirect,
    this.receivedFlood,
    this.receivedDirect,
    this.errEvents,
    this.lastSnrDb,
    this.directDups,
    this.floodDups,
    this.rxAirTimeSecs,
    this.receiveErrors,
  });
  final int batteryMilliVolts;
  final int txQueueLen;
  final int noiseFloorDbm;
  final int lastRssi;
  final int packetsReceived;
  final int packetsSent;
  final int airTimeSecs;
  final int uptimeSecs;
  final int? sentFlood;
  final int? sentDirect;
  final int? receivedFlood;
  final int? receivedDirect;
  final int? errEvents;
  final double? lastSnrDb;
  final int? directDups;
  final int? floodDups;
  final int? rxAirTimeSecs;
  final int? receiveErrors;

  @override
  String toString() => 'RepeaterStatus(batt: ${batteryMilliVolts}mV, '
      'up: ${uptimeSecs}s, noise: $noiseFloorDbm, rssi: $lastRssi, '
      'snr: $lastSnrDb, rx: $packetsReceived, tx: $packetsSent)';
}

/// `PUSH_CODE_TRACE_DATA` (0x89): a TRACE packet that reached the end
/// of its path. [hopSnrsDb] has one entry per hop — the SNR at which
/// that repeater heard the packet; [finalSnrDb] is what our own radio
/// heard the last hop at.
class TraceResult {
  const TraceResult({
    required this.tag,
    required this.authCode,
    required this.flags,
    required this.pathHashes,
    required this.hopSnrsDb,
    required this.finalSnrDb,
  });
  final int tag;
  final int authCode;
  final int flags;

  /// Bytes per path hash: `1 << (flags & 3)`.
  int get hashSize => 1 << (flags & 0x03);

  /// Raw hash bytes, [hashSize] per hop.
  final Uint8List pathHashes;
  final List<double> hopSnrsDb;
  final double finalSnrDb;

  @override
  String toString() => 'TraceResult(tag: 0x${tag.toRadixString(16)}, '
      'hops: ${hopSnrsDb.length}, snrs: $hopSnrsDb, final: $finalSnrDb)';
}

/// One repeater's answer to a zero-hop discover request, carried in a
/// `PUSH_CODE_CONTROL_DATA` (0x8E) whose payload is a
/// `NODE_DISCOVER_RESP` (0x9X).
class DiscoverResponse {
  const DiscoverResponse({
    required this.nodeType,
    required this.tag,
    required this.publicKey,
    required this.theirSnrDb,
    required this.ourSnrDb,
    required this.ourRssi,
  });
  final int nodeType;
  final int tag;

  /// 32 bytes, or 8 when the request asked for prefixes only.
  final Uint8List publicKey;

  /// How well the repeater heard *us*.
  final double theirSnrDb;

  /// How well we heard the repeater.
  final double ourSnrDb;
  final int ourRssi;

  @override
  String toString() => 'DiscoverResponse(type: $nodeType, '
      'tag: 0x${tag.toRadixString(16)}, key: ${publicKey.length}B, '
      'them: $theirSnrDb, us: $ourSnrDb/$ourRssi)';
}
