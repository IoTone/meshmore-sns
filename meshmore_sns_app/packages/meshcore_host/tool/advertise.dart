// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:meshcore_host/meshcore_host.dart';

/// Makes one companion radio announce itself, so another node learns it.
///
/// A freshly flashed radio does not advertise on its own schedule for a long
/// time, and a peer that has never heard it cannot send to it. This sends
/// `CMD_SEND_SELF_ADVERT` a few times and prints what the radio says.
///
///   dart run tool/advertise.dart /dev/ttyACM1 [count] [flood|zero]
///
/// Default count is 3, default kind is flood. Wait for the peer to show the node
/// before assuming it landed: the radio answers OK on transmit, not on receipt.
Future<void> main(List<String> argv) async {
  final String path = argv.isNotEmpty ? argv[0] : '/dev/ttyACM0';
  final int count = argv.length > 1 ? int.parse(argv[1]) : 3;
  final bool flood = argv.length <= 2 || argv[2] != 'zero';

  final SerialPort serial = await SerialPort.open(path, 115200);
  final StreamController<List<int>> rx = StreamController<List<int>>();
  unawaited(serial.pump(rx));

  final SerialFrameTransport transport = SerialFrameTransport(
    inboundBytes: rx.stream,
    write: serial.write,
  )..start();
  transport.setConnected(true);

  final MeshcoreConnection link =
      MeshcoreConnection(appName: 'MeshMore advertise')..attach(transport);

  try {
    await link.states
        .firstWhere((MeshcoreConnectionState s) =>
            s == MeshcoreConnectionState.ready)
        .timeout(const Duration(seconds: 15));
    stdout.writeln('radio ${link.selfInfo!.name} '
        '${_hex(link.selfInfo!.publicKey)}');

    final Inbox inbox = Inbox(link.inbound);
    for (int i = 0; i < count; i++) {
      await link.sendCommand(MeshcoreFrameCodec.sendSelfAdvert(flood: flood));
      final MeshcoreInbound f = await inbox.next<MeshcoreInbound>();
      stdout.writeln('advert ${i + 1}/$count ${flood ? 'flood' : 'zero-hop'}: '
          '${f is OkFrame ? 'OK' : f.runtimeType}');
      if (i + 1 < count) {
        await Future<void>.delayed(const Duration(seconds: 4));
      }
    }
  } on TimeoutException {
    stderr.writeln('timed out: the radio did not answer');
    exitCode = 1;
  } finally {
    await link.dispose();
    await serial.close();
  }
}

class Inbox {
  Inbox(Stream<MeshcoreInbound> stream) {
    _sub = stream.listen(_frames.add);
  }
  late final StreamSubscription<MeshcoreInbound> _sub;
  final List<MeshcoreInbound> _frames = <MeshcoreInbound>[];

  Future<T> next<T extends MeshcoreInbound>({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final int i = _frames.indexWhere((MeshcoreInbound f) => f is T);
      if (i >= 0) return _frames.removeAt(i) as T;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw TimeoutException(
      'no $T within $timeout; saw ${_frames.map((f) => f.runtimeType)}',
    );
  }

  void dispose() => unawaited(_sub.cancel());
}

String _hex(Uint8List b) =>
    b.map((int v) => v.toRadixString(16).padLeft(2, '0')).join();
