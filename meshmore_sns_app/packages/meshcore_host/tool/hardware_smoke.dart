// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:meshcore_host/meshcore_host.dart';

/// Exercises the real wire path against a companion radio on a serial port.
///
/// Not a unit test: it needs hardware, it changes the radio's contact table
/// (one synthetic contact, removed again), and it transmits one packet. Run it
/// by hand:
///
///   dart run tool/hardware_smoke.dart /dev/ttyACM0
///
/// Every failure here is a fact about the firmware or the wiring, not about a
/// mock. The synthetic contact has a one-hop path to an address that does not
/// exist, so the send is answered by the radio (OK) and goes nowhere.
Future<void> main(List<String> argv) async {
  final String path = argv.isEmpty ? '/dev/ttyACM0' : argv.first;
  final Uint8List syntheticKey = Uint8List(32)..fillRange(0, 32, 0xCE);

  final SerialPort serial = await SerialPort.open(path, 115200);
  final StreamController<List<int>> rx = StreamController<List<int>>();
  unawaited(serial.pump(rx));

  final SerialFrameTransport transport = SerialFrameTransport(
    inboundBytes: rx.stream,
    write: serial.write,
  )..start();
  transport.setConnected(true);

  final MeshcoreConnection link =
      MeshcoreConnection(appName: 'MeshMore hardware smoke')..attach(transport);

  final Inbox inbox = Inbox(link.inbound);
  int failures = 0;
  bool added = false;
  Future<void> check(String what, Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      failures++;
      stdout.writeln('FAIL  $what: $e');
    }
  }

  try {
    await link.states
        .firstWhere((MeshcoreConnectionState s) =>
            s == MeshcoreConnectionState.ready)
        .timeout(const Duration(seconds: 15));
    final SelfInfo info = link.selfInfo!;
    stdout
      ..writeln('radio   ${info.name}')
      ..writeln('key     ${_hex(info.publicKey)}')
      ..writeln('preset  ${info.frequencyMhz} MHz / ${info.bandwidthKhz} kHz'
          ' / SF${info.spreadingFactor} / CR${info.codingRate}')

      // The governor's estimator, built from what the radio just told us.
      ..writeln('est     176 B = '
          '${AirtimeEstimator.lora(
            bandwidthHz: (info.bandwidthKhz * 1000).round(),
            spreadingFactor: info.spreadingFactor,
            codingRate: info.codingRate,
          ).forBytes(176).inMilliseconds} ms');

    await check('device info', () async {
      await link.sendCommand(MeshcoreFrameCodec.deviceQuery());
      final DeviceInfoFrame f = await inbox.next<DeviceInfoFrame>();
      stdout.writeln('firmware ${f.info.firmwareVersion} '
          '(build ${f.info.firmwareBuildDate}) '
          'pathHashMode ${f.info.pathHashMode} '
          'maxContacts ${f.info.maxContacts}');
    });

    await check('battery', () async {
      await link.sendCommand(MeshcoreFrameCodec.getBatteryStorage());
      final BatteryStorageFrame f = await inbox.next<BatteryStorageFrame>();
      stdout.writeln('battery  ${f.battery.batteryMillivolts} mV, '
          'storage ${f.battery.storageUsedKb}/${f.battery.storageTotalKb} kB');
    });

    await check('contact table', () async {
      final List<Contact> contacts = await _readContacts(link, inbox);
      final int direct =
          contacts.where((Contact c) => c.outPathLen != 0xFF).length;
      stdout.writeln('contacts ${contacts.length} '
          '($direct with a direct path, ${contacts.length - direct} flood)');
      for (final Contact c in contacts.where((Contact c) => c.outPathLen != 0xFF)) {
        stdout.writeln('direct   ${_hex(c.publicKey)} '
            '${c.name} pathLen ${c.outPathLen}');
      }

      // Never overwrite a real contact. If the table has room, add a
      // synthetic one; if it is full (observed: 350/350), report it and use an
      // existing direct-path contact read-only.
      if (contacts.length < 350) {
        await link.sendCommand(MeshcoreFrameCodec.addUpdateContact(
          _syntheticContact(syntheticKey),
        ));
        final MeshcoreInbound reply = await inbox.next<MeshcoreInbound>();
        if (reply is! OkFrame) throw StateError('add contact: $reply');
        added = true;
        stdout.writeln('contacts added a synthetic contact');
      } else {
        stdout.writeln('contacts table is full: not adding anything');
      }
    });

    await check('bind and send', () async {
      final SerialMeshSender sender =
          SerialMeshSender(link: MeshcoreConnectionLink(link))..start();
      try {
        if (added) {
          final BindError? err = await sender.bindPeer(syntheticKey);
          if (err != null) throw StateError('bind refused: ${err.name}');
          stdout.writeln('bound   capacity ${sender.uplinkRecordMax} B, '
              'overhead ${sender.airtimeOverheadBytes} B');

          final Uint8List record =
              Uint8List.fromList(List<int>.generate(64, (int i) => i));
          final SendOutcome outcome = await sender.sendRecord(record, seq: 1);
          stdout.writeln('send    ${record.length} B -> ${outcome.name}');
          if (outcome != SendOutcome.sentDirect) {
            throw StateError('expected sentDirect, got ${outcome.name}');
          }
        } else {
          // No synthetic contact, so prove the same wire path at L1: a
          // zero-hop raw frame, answered by the radio with OK. Nothing is
          // addressed to a real node and no contact record is touched.
          final Uint8List record =
              Uint8List.fromList(List<int>.generate(64, (int i) => i));
          await link.sendCommand(MeshCarryCodec.sendRawData(
            path: const <int>[],
            payload: record,
          ));
          final MeshcoreInbound reply = await inbox.next<MeshcoreInbound>();
          stdout.writeln('send    ${record.length} B (0-hop raw) -> '
              '${reply.runtimeType}');
          if (reply is! OkFrame) {
            throw StateError('expected OK, got $reply');
          }
        }

        await sender.pollStats();
        stdout.writeln('stats   rssi ${sender.rssiDbm} dBm, '
            'battery ${sender.batteryPercent}');
      } finally {
        await sender.dispose();
      }
    });

    await check('remove the synthetic contact', () async {
      if (!added) {
        stdout.writeln('contacts nothing to remove');
        return;
      }
      await link.sendCommand(MeshcoreFrameCodec.removeContact(syntheticKey));
      final MeshcoreInbound reply = await inbox.next<MeshcoreInbound>();
      if (reply is! OkFrame) throw StateError('remove contact: $reply');
      final List<Contact> left = await _readContacts(link, inbox);
      stdout.writeln('contacts ${left.length} after removal');
    });
  } finally {
    inbox.dispose();
    await link.dispose();
    await transport.close();
    serial.stop();
    await serial.close();
  }

  stdout.writeln(failures == 0 ? 'HARDWARE OK' : 'HARDWARE FAILURES: $failures');
  exit(failures == 0 ? 0 : 1);
}

Contact _syntheticContact(Uint8List key) {
  final Uint8List path = Uint8List(kMaxPathSize)..[0] = 0xAA;
  return Contact(
    publicKey: key,
    type: 1,
    flags: 0,
    outPathLen: 1,
    outPath: path,
    name: 'hw-smoke',
    lastAdvertTimestamp: 0,
    latitudeMicros: 0,
    longitudeMicros: 0,
    lastMod: 0,
  );
}

Future<List<Contact>> _readContacts(MeshcoreConnection link, Inbox inbox) async {
  await link.sendCommand(MeshcoreFrameCodec.getContacts());
  final List<Contact> contacts = <Contact>[];
  while (true) {
    final MeshcoreInbound frame =
        await inbox.next<MeshcoreInbound>(timeout: const Duration(seconds: 10));
    if (frame is EndOfContactsFrame) return contacts;
    if (frame is ContactFrame) contacts.add(frame.contact);
  }
}

String _hex(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Collects inbound frames so each step can wait for the one it needs.
class Inbox {
  Inbox(Stream<MeshcoreInbound> stream) {
    _sub = stream.listen(_frames.add);
  }
  late final StreamSubscription<MeshcoreInbound> _sub;
  final List<MeshcoreInbound> _frames = <MeshcoreInbound>[];

  Future<T> next<T extends MeshcoreInbound>({
    Duration timeout = const Duration(seconds: 5),
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
