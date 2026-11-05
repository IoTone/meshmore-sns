// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math';

/// The SOS packet schedule (`meshmore-sos-spec.md` §7, decision D8.4 as
/// amended 2026-11-04): **twelve sends one minute apart, then ten beacons five
/// minutes apart, ending inside the hour.**
///
/// D8.4's original parenthetical did not add up — "12 at 60 s" plus "a beacon
/// every 5 minutes for 60 minutes" ends at 72 minutes. The prior art's engine
/// counts `MAX_SENDS` as a total, so the sends are twelve in total and the
/// beacons start after the last one, which is what makes 22 packets fit in 57
/// minutes.
///
/// Each send is jittered by ±3 s. Twenty devices raising at once is 160–200 s
/// of airtime in one minute; the jitter, not the interval, is what keeps
/// simultaneous alarms from colliding in lockstep.
enum SosPacketKind { send, beacon }

final class SosPacket {
  const SosPacket({
    required this.kind,
    required this.index,
    required this.dueAt,
  });

  final SosPacketKind kind;

  /// 1-based within its own kind: send 1..12, beacon 1..10.
  final int index;

  final DateTime dueAt;

  @override
  String toString() => '${kind.name}#$index@${dueAt.toIso8601String()}';

  @override
  bool operator ==(Object other) =>
      other is SosPacket &&
      other.kind == kind &&
      other.index == index &&
      other.dueAt == dueAt;

  @override
  int get hashCode => Object.hash(kind, index, dueAt);
}

/// The fixed arithmetic of the schedule. All times are offsets from the raise.
abstract final class SosSchedule {
  static const int sendCount = 12;
  static const Duration sendInterval = Duration(seconds: 60);

  static const int beaconCount = 10;
  static const Duration beaconStart = Duration(seconds: 720);
  static const Duration beaconInterval = Duration(seconds: 300);

  /// Nothing is sent at or after this offset.
  static const Duration hardStop = Duration(seconds: 3600);

  /// Jitter is applied to sends (±3 s); beacons are already five minutes
  /// apart, so a second of jitter there would buy nothing.
  static const int jitterSeconds = 3;

  /// Total packets one alarm may ever emit: the bound the budget is reasoned
  /// about (22 packets, 8–10 s of airtime).
  static int get packetCount => sendCount + beaconCount;

  /// The plan for one alarm.
  ///
  /// [random] supplies the ±3 s jitter. Passing null gives the un-jittered
  /// times, which is what a test that pins a tick time wants; the app passes a
  /// real `Random`.
  static List<SosPacket> plan({
    required DateTime raisedAt,
    Random? random,
  }) {
    final List<SosPacket> packets = <SosPacket>[];
    for (int i = 1; i <= sendCount; i++) {
      final int jitter = random == null ? 0 : random.nextInt(2 * jitterSeconds + 1) - jitterSeconds;
      packets.add(SosPacket(
        kind: SosPacketKind.send,
        index: i,
        dueAt: raisedAt.add(sendInterval * (i - 1)).add(Duration(seconds: jitter)),
      ));
    }
    for (int i = 1; i <= beaconCount; i++) {
      final Duration offset =
          beaconStart + beaconInterval * (i - 1);
      packets.add(SosPacket(
        kind: SosPacketKind.beacon,
        index: i,
        dueAt: raisedAt.add(offset),
      ));
    }
    return List<SosPacket>.unmodifiable(packets);
  }

  /// The moment the schedule stops, whether or not a packet was due then.
  static DateTime hardStopAt(DateTime raisedAt) => raisedAt.add(hardStop);
}
