// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:meshcore_host/meshcore_host.dart';

/// Sets a companion radio's four radio numbers and its transmit power, then
/// reads them back from the radio itself.
///
/// This exists because a freshly flashed companion radio has no radio settings
/// at all: `NodePrefs.freq/sf/cr/bw` default to zero and the firmware applies no
/// region default, so the radio cannot transmit until an app sets them. The
/// phone app does that for its own radio; a host that drives a second radio over
/// USB has no app, so this is that app, reduced to one command.
///
///   dart run tool/configure_radio.dart /dev/ttyACM0 910.525 62.5 7 5 22
///
/// Arguments after the port are frequency MHz, bandwidth kHz, spreading factor,
/// coding rate and TX power dBm. The read-back is the proof: if the radio
/// reports different numbers, it did not accept them.
Future<void> main(List<String> argv) async {
  if (argv.length < 6) {
    stderr.writeln('usage: configure_radio <port> <freqMHz> <bwKHz> <sf> <cr> <txDbm>');
    exit(64);
  }
  final String path = argv[0];
  final double freq = double.parse(argv[1]);
  final double bw = double.parse(argv[2]);
  final int sf = int.parse(argv[3]);
  final int cr = int.parse(argv[4]);
  final int tx = int.parse(argv[5]);

  final SerialPort serial = await SerialPort.open(path, 115200);
  final StreamController<List<int>> rx = StreamController<List<int>>();
  unawaited(serial.pump(rx));

  final SerialFrameTransport transport = SerialFrameTransport(
    inboundBytes: rx.stream,
    write: serial.write,
  )..start();
  transport.setConnected(true);

  final MeshcoreConnection link =
      MeshcoreConnection(appName: 'MeshMore radio provisioning')..attach(transport);

  try {
    await link.states
        .firstWhere((MeshcoreConnectionState s) =>
            s == MeshcoreConnectionState.ready)
        .timeout(const Duration(seconds: 15));

    final SelfInfo before = link.selfInfo!;
    stdout
      ..writeln('radio   ${before.name}')
      ..writeln('key     ${_hex(before.publicKey)}')
      ..writeln('before  ${before.frequencyMhz} MHz / ${before.bandwidthKhz} kHz'
          ' / SF${before.spreadingFactor} / CR${before.codingRate}');

    final Inbox inbox = Inbox(link.inbound);

    await link.sendCommand(MeshcoreFrameCodec.setRadioParams(RadioParams(
      frequencyMhz: freq,
      bandwidthKhz: bw,
      spreadingFactor: sf,
      codingRate: cr,
    )));
    await _expectOk(inbox, 'set radio params');

    await link.sendCommand(MeshcoreFrameCodec.setRadioTxPower(tx));
    await _expectOk(inbox, 'set tx power');

    // The radio's own answer, not ours: re-read SELF_INFO after a fresh query so
    // the numbers printed are what the firmware stored.
    await link.sendCommand(MeshcoreFrameCodec.appStart(appName: 'MeshMore radio provisioning'));
    final SelfInfo after =
        (await inbox.next<SelfInfoFrame>()).selfInfo;

    stdout.writeln(
        'after   ${after.frequencyMhz} MHz / ${after.bandwidthKhz} kHz'
        ' / SF${after.spreadingFactor} / CR${after.codingRate}');
    stdout.writeln('tx power $tx dBm');

    final bool ok = (after.frequencyMhz - freq).abs() < 0.001 &&
        (after.bandwidthKhz - bw).abs() < 0.001 &&
        after.spreadingFactor == sf &&
        after.codingRate == cr;
    if (!ok) {
      stderr.writeln('REFUSED: the radio reports different numbers');
      exitCode = 1;
    }
  } on TimeoutException catch (e) {
    stderr.writeln('timed out: $e');
    exitCode = 1;
  } finally {
    await link.dispose();
    await serial.close();
  }
}

Future<void> _expectOk(Inbox inbox, String what) async {
  final MeshcoreInbound f = await inbox.next<MeshcoreInbound>();
  if (f is ErrorFrame) {
    throw StateError('$what refused: error ${f.code}');
  }
  if (f is! OkFrame) {
    throw StateError('$what: unexpected ${f.runtimeType}');
  }
}

/// Frames arrive in one stream and a test needs to wait for a *kind*, so this
/// buffers and hands out the first matching frame. Same shape as the smoke tool.
class Inbox {
  Inbox(Stream<MeshcoreInbound> stream) {
    _sub = stream.listen(_frames.add);
  }
  late final StreamSubscription<MeshcoreInbound> _sub;
  final List<MeshcoreInbound> _frames = <MeshcoreInbound>[];

  Future<T> next<T extends MeshcoreInbound>({
    Duration timeout = const Duration(seconds: 8),
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
