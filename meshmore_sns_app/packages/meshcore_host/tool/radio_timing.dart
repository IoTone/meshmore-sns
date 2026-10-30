// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:meshcore_host/meshcore_host.dart';

/// Time the radio itself, with none of the LDMUX stack in the way.
///
/// This exists to separate two questions that looked identical from the phone: is a record slow
/// because the *radio* takes seconds to acknowledge it, or because something in the host stack
/// serialises on that acknowledgement? Here there is no L3 session, no ARQ and no bridge: five
/// raw records, each measured from the moment it is handed to the sender until the sender says
/// the radio accepted it.
///
///   dart run tool/radio_timing.dart /dev/ttyACM2 HELTEC-BASE 5
///
/// The first line is the preset the radio reports, so a slow run with a wide preset is visibly
/// not the preset's fault.
Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln('usage: radio_timing <port> <peer-name> [count]');
    exit(64);
  }
  final String path = argv[0];
  final String peerName = argv[1];
  final int count = argv.length > 2 ? int.parse(argv[2]) : 5;

  final SerialPort serial = await SerialPort.open(path, 115200);
  final StreamController<List<int>> rx = StreamController<List<int>>();
  unawaited(serial.pump(rx));
  final SerialFrameTransport transport = SerialFrameTransport(
    inboundBytes: rx.stream,
    write: serial.write,
  )..start();
  transport.setConnected(true);

  final MeshcoreConnection link = MeshcoreConnection(appName: 'ldmux radio timing')
    ..attach(transport);
  try {
    await link.states
        .firstWhere((MeshcoreConnectionState s) =>
            s == MeshcoreConnectionState.ready)
        .timeout(const Duration(seconds: 15));
  } on TimeoutException {
    stderr.writeln('error: the radio did not answer APP_START within 15 s');
    serial.stop();
    await serial.close();
    exit(69);
  }
  final SelfInfo info = link.selfInfo!;
  stdout.writeln('preset   ${info.frequencyMhz} MHz / ${info.bandwidthKhz} kHz / '
      'SF${info.spreadingFactor} / CR${info.codingRate}');

  final SerialMeshSender sender = SerialMeshSender(
    link: MeshcoreConnectionLink(link),
  )..start();
  final Contact? peer = await sender.contactByName(peerName);
  if (peer == null) {
    stderr.writeln('no contact named $peerName: ${sender.contactNames.join(", ")}');
    serial.stop();
    await serial.close();
    exit(1);
  }
  final BindError? refused = await sender.bindPeer(peer.publicKey);
  stdout.writeln('peer     $peerName refused=${refused?.name ?? "no"} '
      'max=${sender.uplinkRecordMax} contacts=${sender.contactNames.length}');

  for (int i = 0; i < count; i++) {
    final Uint8List record = Uint8List(120)..fillRange(0, 120, 0x41 + i);
    final Stopwatch w = Stopwatch()..start();
    final SendOutcome out = await sender.sendRecord(record, seq: i);
    w.stop();
    stdout.writeln('record $i  ${out.name.padRight(12)} ${w.elapsedMilliseconds} ms');
  }

  serial.stop();
  await serial.close();
}
