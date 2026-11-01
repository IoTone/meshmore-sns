// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';

import 'package:meshcore/meshcore.dart';
import 'package:meshcore_host/meshcore_host.dart';

/// Prints what a companion radio says about itself: uptime, battery, noise floor, airtime, and the
/// packet counters.
///
///   dart run tool/radio_stats.dart /dev/ttyACM0 [seconds]
///
/// It answers the one question no protocol-level work can: **is this radio receiving at all?** A
/// radio whose TX path is fine and whose RX path is dead answers every command over USB, reports a
/// plausible preset, transmits successfully, and shows nothing unusual anywhere except here:
/// `received` stays flat while `sent` climbs, and `rx airtime` does not grow.
///
/// The numbers come from the firmware's own counters (`STATS_TYPE_CORE / RADIO / PACKETS`), so this
/// works on any MeshCore companion, not on a particular board. Poll it for a few seconds while
/// another node transmits to see the difference between "nothing arrives" and "arrives and is
/// dropped" (`receive errors` moves in the second case).
///
/// The port is usually held by a running gateway: stop it first.
Future<void> main(List<String> argv) async {
  final String path = argv.isNotEmpty ? argv[0] : '/dev/ttyACM0';
  final int seconds = argv.length > 1 ? int.parse(argv[1]) : 10;

  final SerialPort serial = await SerialPort.open(path, 115200);
  final StreamController<List<int>> rx = StreamController<List<int>>();
  unawaited(serial.pump(rx));

  final SerialFrameTransport transport = SerialFrameTransport(
    inboundBytes: rx.stream,
    write: serial.write,
  )..start();
  transport.setConnected(true);

  final MeshcoreConnection link =
      MeshcoreConnection(appName: 'MeshMore stats')..attach(transport);

  try {
    await link.states
        .firstWhere((MeshcoreConnectionState s) =>
            s == MeshcoreConnectionState.ready)
        .timeout(const Duration(seconds: 15));
    final SelfInfo me = link.selfInfo!;
    stdout.writeln('radio  ${me.name} ${_hex(me.publicKey).substring(0, 8)}');
    stdout.writeln('preset ${me.frequencyMhz.toStringAsFixed(3)} MHz / '
        '${me.bandwidthKhz} kHz / SF${me.spreadingFactor} / CR${me.codingRate}');

    // One pass per stat group; the reply carries which group it is.
    for (int pass = 0; pass < 1 + (seconds ~/ 3); pass++) {
      final Map<String, String> out = <String, String>{};
      for (final int sub in <int>[
        kStatsTypeCore,
        kStatsTypeRadio,
        kStatsTypePackets,
      ]) {
        await link.sendCommand(MeshcoreFrameCodec.getStats(sub));
        final StatsFrame f = await link.inbound
            .where((MeshcoreInbound e) => e is StatsFrame)
            .cast<StatsFrame>()
            .first
            .timeout(const Duration(seconds: 3));
        if (f.core != null) {
          out['uptime'] = '${f.core!.uptimeSecs} s';
          out['battery'] = '${f.core!.batteryMilliVolts} mV';
          out['queue'] = '${f.core!.queueLen}';
          out['errFlags'] = '0x${f.core!.errFlags.toRadixString(16)}';
        }
        if (f.radio != null) {
          final RadioStats r = f.radio!;
          out['noise'] = '${r.noiseFloorDbm} dBm';
          out['lastRssi'] = '${r.lastRssi} dBm';
          out['lastSnr'] = '${r.lastSnrDb.toStringAsFixed(2)} dB';
          out['txAir'] = '${r.txAirSecs} s';
          out['rxAir'] = '${r.rxAirSecs} s';
        }
        if (f.packets != null) {
          final PacketStats p = f.packets!;
          out['received'] = '${p.received}';
          out['sent'] = '${p.sent}';
          out['recvFlood'] = '${p.receivedFlood}';
          out['recvDirect'] = '${p.receivedDirect}';
          out['recvErrors'] = '${p.receiveErrors ?? 'not reported'}';
        }
      }
      stdout.writeln('--- ${pass == 0 ? 'now' : '+${pass * 3}s'} '
          '(waiting ${seconds}s: the second line is the one that matters)');
      for (final MapEntry<String, String> e in out.entries) {
        stdout.writeln('  ${e.key.padRight(10)} ${e.value}');
      }
      if (pass * 3 < seconds) {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  } on TimeoutException {
    stderr.writeln('timed out: the radio did not answer a stats request');
    exitCode = 1;
  } finally {
    await link.dispose();
    await rx.close();
    await serial.close();
  }
}

String _hex(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
