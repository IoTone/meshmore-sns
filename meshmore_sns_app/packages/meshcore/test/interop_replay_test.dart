// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:test/test.dart';

Uint8List _hex(String s) {
  final Uint8List out = Uint8List(s.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(List<int> b) =>
    b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Replays real captures dropped into `test/vectors/interop/`.
///
/// Two kinds, both recorded from a radio on the bench and both in
/// `SCHEMA.md`:
///
///  * `ota_advert_capture` — a `PUSH_CODE_LOG_RX_DATA` (0x88) notification
///    as the radio sent it, with the listening side's own decode of the
///    same event (sender key, name, position, SNR, RSSI) as the
///    independent expectation. This is the everyday conformance check:
///    the companion framing, the OTA packet parse and the advert layout
///    all have to agree with a real radio for it to pass.
///  * `grp_txt_capture` — a group text heard over the air, with the
///    plaintext and the PSK, used to settle the channel-secret tail. No
///    such capture exists yet, so that test stays skipped and says so.
void main() {
  final Directory dir = Directory('test/vectors/interop');
  final List<File> fixtures = dir.existsSync()
      ? (dir
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.json'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path)))
      : <File>[];

  Map<String, Object?> read(File f) =>
      jsonDecode(f.readAsStringSync()) as Map<String, Object?>;

  final List<File> adverts = fixtures
      .where((File f) => read(f)['kind'] == 'ota_advert_capture')
      .toList();
  final List<File> channelTexts = fixtures
      .where((File f) => read(f)['kind'] == 'grp_txt_capture')
      .toList();

  if (adverts.isEmpty) {
    test('over-the-air advert replay (no capture on disk)', () {},
        skip: 'No ota_advert_capture in test/vectors/interop/ — see '
            'test/vectors/interop/SCHEMA.md');
  }

  for (final File f in adverts) {
    final Map<String, Object?> fx = read(f);
    final String name = f.uri.pathSegments.last;

    test('interop advert: $name', () {
      // The recorded payload is the 0x88 body without its opcode; putting
      // the opcode back rebuilds the notification byte for byte.
      final Uint8List payload = _hex(fx['rf_log_payload_hex']! as String);
      final MeshcoreInbound frame = MeshcoreFrameCodec.decode(
          Uint8List.fromList(<int>[0x88, ...payload]));

      expect(frame, isA<RfLogFrame>(),
          reason: 'the recorded notification must decode as 0x88');
      final RfLog log = (frame as RfLogFrame).log;

      // SNR/RSSI as the listening radio reported them for this packet.
      expect(log.snrDb, (fx['snr_db']! as num).toDouble(),
          reason: 'SNR*4 byte in the 0x88 frame');
      expect(log.rssi, fx['rssi_dbm']! as int, reason: 'RSSI byte');
      expect(log.raw.length, payload.length - 2,
          reason: 'the OTA packet is everything after SNR and RSSI');

      final OtaPacket? pkt = log.packet;
      expect(pkt, isNotNull, reason: 'the captured OTA packet must parse');
      expect(pkt!.isAdvert, isTrue);
      expect(pkt.routeType, fx['route_code']! as int,
          reason: 'route bits of the captured header');

      final Advert? advert = pkt.advert;
      expect(advert, isNotNull, reason: 'ADVERT payload must decode');
      // The expectation is the listener's decode of the same capture, not
      // a value this codec produced.
      expect(_toHex(advert!.publicKey), fx['sender_key_hex']! as String,
          reason: 'sender key from the advert body');
      expect(advert.name, fx['sender_name']! as String);
      expect(advert.latitude, closeTo(fx['advert_lat']! as num, 1e-6));
      expect(advert.longitude, closeTo(fx['advert_lon']! as num, 1e-6));
      expect(advert.timestamp, greaterThan(0));
    });
  }

  if (channelTexts.isEmpty) {
    test('over-the-air channel text replay (no capture on disk)', () {},
        skip: 'No grp_txt_capture in test/vectors/interop/ — the channel-'
            'secret tail needs one; see SCHEMA.md');
  }

  for (final File f in channelTexts) {
    final Map<String, Object?> fx = read(f);
    final String name = f.uri.pathSegments.last;

    test('interop channel text: $name', () {
      final MeshcoreInbound frame = MeshcoreFrameCodec.decode(
          _hex(fx['rf_log_frame_hex']! as String));
      expect(frame, isA<RfLogFrame>(),
          reason: 'capture must be a 0x88 RF-log frame');

      final OtaPacket? pkt = (frame as RfLogFrame).log.packet;
      expect(pkt, isNotNull, reason: 'OTA packet failed to parse');
      expect(pkt!.isGrpTxt, isTrue, reason: 'expected a GRP_TXT packet');

      final ChannelTailResult r = resolveChannelTail(
        psk: _hex(fx['psk_hex']! as String),
        knownPlaintext: Uint8List.fromList(
            utf8.encode(fx['known_plaintext_utf8']! as String)),
        grpTxt: pkt.grpTxt!,
      );

      // The decisive M6 assertion + report.
      // ignore: avoid_print
      print('[interop] $name → channel-secret tail = '
          '${r.match?.name ?? "UNRESOLVED"} '
          '(channelHashOk: ${r.channelHashOk})');
      expect(r.resolved, isTrue,
          reason: 'no tail hypothesis reproduced the real device MAC + '
              'channel hash + plaintext for $name');
    });
  }
}
