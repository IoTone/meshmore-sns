// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:meshcore_host/meshcore_host.dart';

/// The MeshMore gateway process for a machine with a USB-serial companion
/// radio.
///
/// It is deliberately thin: open the port, start the L1 link, hand the link
/// to [SerialMeshSender], start the same L2 [Gateway] the phone runs. Every
/// MeshCore decision is made by `packages/meshcore`, every tunnel decision
/// by `packages/meshcore_gateway`. Nothing is re-implemented here.
///
/// Usage:
///   dart run bin/meshmore_gateway.dart --port /dev/ttyACM0 [--baud 115200]
///      [--token <hex>] [--state ~/.local/state/meshmore/gateway.json]
///      [--listen 41731]
Future<void> main(List<String> argv) async {
  final _Options o = _Options.parse(argv);
  if (o.help) {
    stdout.writeln(_Options.usage);
    return;
  }
  if (o.port == null) {
    stderr.writeln('error: --port is required\n\n${_Options.usage}');
    exitCode = 64;
    return;
  }

  final SerialPort serial = await SerialPort.open(o.port!, o.baud);
  final StreamController<List<int>> rx = StreamController<List<int>>();
  unawaited(serial.pump(rx));

  final SerialFrameTransport transport = SerialFrameTransport(
    inboundBytes: rx.stream,
    write: serial.write,
  )..start();
  transport.setConnected(true);

  final MeshcoreConnection link = MeshcoreConnection(
    appName: 'MeshMore host gateway',
  )..attach(transport);

  try {
    await link.states
        .firstWhere((MeshcoreConnectionState s) =>
            s == MeshcoreConnectionState.ready)
        .timeout(const Duration(seconds: 15));
  } on TimeoutException {
    stderr.writeln(
      'error: the radio did not answer APP_START within 15 s.\n'
      '  - is this a companion build? A BLE build has no USB companion\n'
      '    interface (the env must define ENABLE_USB_INTERFACE, e.g.\n'
      '    heltec_v4_companion_radio_usb).\n'
      '  - is another process holding the port?',
    );
    serial.stop();
    await serial.close();
    // A pending blocking read keeps the isolate alive, so returning from main
    // would hang the process. Exit explicitly.
    exit(69);
  }

  final SelfInfo info = link.selfInfo!;
  final SerialMeshSender sender = SerialMeshSender(
    link: MeshcoreConnectionLink(link),
  )..start();

  final _FilePairingPersistence persistence =
      _FilePairingPersistence(File(o.statePath));
  await persistence.prepare();
  if (o.token != null) {
    await persistence.save(_parseToken(o.token!));
  }

  final Gateway gateway = Gateway(
    mesh: sender,
    persistence: persistence,
    port: o.listenPort,
    // The governor must meter the radio's REAL preset, not a default.
    estimator: AirtimeEstimator.lora(
      bandwidthHz: (info.bandwidthKhz * 1000).round(),
      spreadingFactor: info.spreadingFactor,
      codingRate: info.codingRate,
    ),
  );
  await gateway.start();

  stdout
    ..writeln('radio   ${info.name}')
    ..writeln('key     ${_hex(info.publicKey)}')
    ..writeln('preset  ${info.frequencyMhz} MHz / ${info.bandwidthKhz} kHz'
        ' / SF${info.spreadingFactor} / CR${info.codingRate}')
    ..writeln('gateway 127.0.0.1:${gateway.port}')
    ..writeln('token   ${_hex(gateway.pairingToken)}')
    ..writeln('state   ${o.statePath}')
    ..writeln('ready. ctrl-c to stop.');

  final Timer stats = Timer.periodic(
    const Duration(seconds: 60),
    (_) => unawaited(sender.pollStats()),
  );

  final Completer<void> stop = Completer<void>();
  final StreamSubscription<ProcessSignal> sigint =
      ProcessSignal.sigint.watch().listen((_) {
    if (!stop.isCompleted) stop.complete();
  });
  final StreamSubscription<ProcessSignal> sigterm =
      ProcessSignal.sigterm.watch().listen((_) {
    if (!stop.isCompleted) stop.complete();
  });

  await stop.future;
  stats.cancel();
  await sigint.cancel();
  await sigterm.cancel();
  await gateway.stop();
  await sender.dispose();
  await link.dispose();
  await transport.close();
  serial.stop();
  await serial.close();
  stdout.writeln('stopped.');
  exit(0);
}

// ---------------------------------------------------------------------------
// Filesystem pairing persistence (the host has no Keystore: 0600 file).
// ---------------------------------------------------------------------------

class _FilePairingPersistence implements PairingPersistence {
  _FilePairingPersistence(this.file);
  final File file;

  Future<void> prepare() async {
    await file.parent.create(recursive: true);
    if (!await file.exists()) {
      await file.writeAsString('{}');
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['600', file.path]);
    }
  }

  @override
  Future<Uint8List?> load() async {
    try {
      final Map<String, dynamic> json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final Object? hex = json['pairingToken'];
      if (hex is! String || hex.isEmpty) return null;
      return _parseToken(hex);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Uint8List token) async {
    await file.writeAsString(jsonEncode(<String, String>{
      'pairingToken': _hex(token),
    }));
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['600', file.path]);
    }
  }

  @override
  Future<void> clear() async {
    await file.writeAsString('{}');
  }
}

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

class _Options {
  _Options(this.port, this.baud, this.token, this.statePath, this.listenPort,
      this.help);

  final String? port;
  final int baud;
  final String? token;
  final String statePath;
  final int listenPort;
  final bool help;

  static const String usage = '''
meshmore gateway (host, USB-serial companion radio)

  --port <path>     serial device, e.g. /dev/ttyACM0        (required)
  --baud <n>        baud rate                               (default 115200)
  --token <hex>     set the pairing token instead of keeping the stored one
  --state <path>    where the token is kept                 (default below)
  --listen <port>   loopback port                           (default 41731)
  --help

The radio must run a companion build with ENABLE_USB_INTERFACE. A BLE-only
build exposes no serial companion interface.''';

  static _Options parse(List<String> argv) {
    String? port;
    int baud = 115200;
    String? token;
    int listen = GatewayServer.defaultPort;
    bool help = false;
    final String home = Platform.environment['HOME'] ?? '.';
    String state = '$home/.local/state/meshmore/gateway.json';

    for (int i = 0; i < argv.length; i++) {
      final String a = argv[i];
      String? next() => i + 1 < argv.length ? argv[++i] : null;
      switch (a) {
        case '--help' || '-h':
          help = true;
        case '--port':
          port = next();
        case '--baud':
          baud = int.tryParse(next() ?? '') ?? baud;
        case '--token':
          token = next();
        case '--state':
          state = next() ?? state;
        case '--listen':
          listen = int.tryParse(next() ?? '') ?? listen;
        default:
          if (a.startsWith('--')) {
            stderr.writeln('warning: unknown option $a');
          }
      }
    }
    return _Options(port, baud, token, state, listen, help);
  }
}

// ---------------------------------------------------------------------------

String _hex(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _parseToken(String hex) {
  if (hex.length.isOdd) {
    throw FormatException('token must be an even number of hex digits');
  }
  return Uint8List.fromList(<int>[
    for (int i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}
