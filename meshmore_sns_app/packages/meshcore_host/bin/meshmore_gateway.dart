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
    airtimePolicy: o.airtime,
    // The governor must meter the radio's REAL preset, not a default.
    estimator: AirtimeEstimator.lora(
      bandwidthHz: (info.bandwidthKhz * 1000).round(),
      spreadingFactor: info.spreadingFactor,
      codingRate: info.codingRate,
    ),
  );
  await gateway.start();

  // Resolve the peer by name, if asked. The radio's own contact table is the
  // authority: the firmware's raw-data push carries no sender key
  // (`MyPacket` -> `PUSH_CODE_RAW_DATA` is snr/rssi/payload only), so the host
  // must be told who the far radio is exactly once, and a name it already holds
  // is the least error-prone way to say it.
  String? peerKey;
  if (o.peerName != null) {
    final Contact? peer = await sender.contactByName(o.peerName!);
    if (peer == null) {
      stderr.writeln(
        'error: no contact named "${o.peerName}" on ${info.name}.\n'
        '  the radio holds: ${sender.contactNames.join(', ')}',
      );
      await sender.dispose();
      await link.dispose();
      await transport.close();
      serial.stop();
      await serial.close();
      exit(78);
    }
    peerKey = _hex(peer.publicKey);
    stdout.writeln('peer    ${peer.name} $peerKey'
        ' pathLen=${peer.outPathLen}');
  }

  await persistence.publishIdentity(
    address: '127.0.0.1:${gateway.port}',
    radioKey: _hex(info.publicKey),
    peerName: o.peerName,
    peerKey: peerKey,
  );

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

  /// The file's keys, or an empty map. A corrupt file is not silently kept: the
  /// caller re-mints a token, and every value written back replaces it whole.
  Future<Map<String, Object?>> _read() async {
    try {
      final Object? raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) return Map<String, Object?>.from(raw);
    } catch (_) {
      // Unreadable state is treated as absent; the token is re-minted.
    }
    return <String, Object?>{};
  }

  Future<void> _write(Map<String, Object?> values) async {
    final Map<String, Object?> merged = await _read()..addAll(values);
    await file.writeAsString(jsonEncode(merged));
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['600', file.path]);
    }
  }

  @override
  Future<Uint8List?> load() async {
    final Map<String, Object?> m = await _read();
    final Object? hex = m['pairingToken'];
    if (hex is! String || hex.isEmpty) return null;
    try {
      return _parseToken(hex);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Uint8List token) =>
      _write(<String, Object?>{'pairingToken': _hex(token)});

  @override
  Future<void> clear() => _write(<String, Object?>{'pairingToken': null});

  /// Publish what a daemon needs to reach this gateway, so nothing is copied by
  /// hand: where it listens, this radio's public key, and the peer's when a name
  /// was resolved. Additive; the token key is untouched.
  Future<void> publishIdentity({
    required String address,
    required String radioKey,
    String? peerName,
    String? peerKey,
  }) =>
      _write(<String, Object?>{
        'gatewayAddr': address,
        'radioKey': radioKey,
        'peerName': peerName,
        'peerKey': peerKey,
      });
}

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

class _Options {
  _Options(this.port, this.baud, this.token, this.statePath, this.listenPort,
      this.peerName, this.airtime, this.help);

  final String? port;
  final int baud;
  final String? token;
  final String statePath;
  final int listenPort;

  /// Contact name whose public key the daemon should send to, or null.
  final String? peerName;

  /// How much airtime the gateway allows itself. `duty` is the voluntary 1 %
  /// duty cycle (36 s/hour, the EU/UK limit and a safety margin elsewhere);
  /// `owned` is no voluntary cap, for a private frequency the operator controls.
  final AirtimePolicy airtime;
  final bool help;

  static const String usage = '''
meshmore gateway (host, USB-serial companion radio)

  --port <path>     serial device, e.g. /dev/ttyACM0        (required)
  --baud <n>        baud rate                               (default 115200)
  --token <hex>     set the pairing token instead of keeping the stored one
  --state <path>    identity + token file the daemon reads  (default below)
  --listen <port>   loopback port                           (default 41731)
  --peer-name <n>   resolve the peer radio by contact name, and publish its key
  --airtime <mode>  duty (36 s/hour, the default) or owned (no voluntary cap,
                    for a private frequency you control)
  --help

The state file is the one thing a host needs to hand to ldmuxd: it holds the
loopback address, the pairing token, this radio's public key, and -- when
--peer-name resolves -- the peer radio's public key. No key is ever copied by
hand. A name that does not resolve is a startup error listing what the radio
does hold, because guessing a peer would send records into the wrong path.

The radio must run a companion build with ENABLE_USB_INTERFACE. A BLE-only
build exposes no serial companion interface.''';

  static _Options parse(List<String> argv) {
    String? port;
    int baud = 115200;
    String? token;
    int listen = GatewayServer.defaultPort;
    String? peerName;
    AirtimePolicy airtime = AirtimePolicy.onePercentDutyCycle;
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
        case '--peer-name':
          peerName = next();
        case '--airtime':
          airtime = switch (next()) {
            'owned' => AirtimePolicy.ownedChannel,
            'duty' || null => AirtimePolicy.onePercentDutyCycle,
            final String other => (throw FormatException(
                '--airtime takes "duty" or "owned", not "$other"')),
          };
        default:
          if (a.startsWith('--')) {
            stderr.writeln('warning: unknown option $a');
          }
      }
    }
    return _Options(port, baud, token, state, listen, peerName, airtime, help);
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
