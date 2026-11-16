// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/screens/diagnostics_redaction.dart';

/// L1/L2 — a capture that leaves the screen must not carry the material that
/// would let someone else read the mesh, and must keep the material that makes
/// it evidence.
void main() {
  const String psk =
      '9f2c1d4b77ae03c5e6b8d0a1f3c7e29b'; // 16-byte channel key
  const DiagnosticsRedaction redactor = DiagnosticsRedaction();

  test('a channel key is masked to its first four bytes and its width', () {
    final String out = redactor.json(
        '{"kind":"grp_txt_capture","psk_hex":"$psk","rf_log_frame_hex":"8811a4f0"}');
    expect(out.contains(psk), isFalse,
        reason: 'a channel PSK decrypts every message on that channel');
    expect(out, contains('9f2c1d4b…32'));
  });

  test('the encrypted frame survives, because it is the evidence', () {
    const String frame = '8811a4f0ffee00112233445566778899';
    final String out = redactor
        .json('{"rf_log_frame_hex":"$frame","channel_name":"Public"}');
    expect(out, contains(frame));
    expect(out, contains('Public'));
  });

  test('a node key in any spelling is masked', () {
    final String out = redactor.json(
        '{"contact_key":"$psk","token":"$psk","secret":"$psk","pubkey":"$psk"}');
    expect(out.contains(psk), isFalse);
  });

  test('a coordinate is coarsened by default and kept only on request', () {
    final String masked = redactor.json('{"lat":"38.924131","lon":"-104.77322"}');
    expect(masked, contains('38.92'));
    expect(masked, contains('-104.77'));
    expect(masked.contains('38.924131'), isFalse);

    final String revealed = const DiagnosticsRedaction(revealPosition: true)
        .json('{"lat":"38.924131","lon":"-104.77322"}');
    expect(revealed, contains('38.924131'));
  });

  test('a coordinate or PIN sent as a number is masked like a string', () {
    // The JSON form of a capture carries lat/lon as numbers and the radio's
    // BLE PIN as an int, so a string-only redactor leaked both into whatever
    // the capture was pasted into.
    final String out =
        redactor.json('{"lat":38.924131,"lon":-104.77322,"ble_pin":123456}');
    expect(out.contains('38.924131'), isFalse);
    expect(out.contains('-104.77322'), isFalse);
    expect(out.contains('123456'), isFalse);

    final String revealed = const DiagnosticsRedaction(revealPosition: true)
        .json('{"lat":38.924131,"ble_pin":123456}');
    expect(revealed, contains('38.92'),
        reason: 'a position may be revealed on request');
    expect(revealed.contains('123456'), isFalse,
        reason: 'a PIN is never revealed by the position switch');
  });

  test('a secret in plain text is masked, and a bare frame is not', () {
    final String out = redactor.maskSecrets(
        'channel key: $psk\nrun rx 12 tx 3\nframe 8811a4f0ffee00112233');
    expect(out.contains(psk), isFalse);
    expect(out, contains('8811a4f0ffee00112233'));
    expect(out, contains('run rx 12 tx 3'));
  });

  test('anything that is not JSON still masks instead of throwing', () {
    final String out = redactor.json('psk: $psk');
    expect(out.contains(psk), isFalse);
  });

  test('position aliases are coarsened, including an E6 pair and an altitude', () {
    // The place and soak paths spell a fix latE6/lonE6 and alt, and a field
    // called lat/lon is not the only way one arrives.
    final String out = redactor.json('{"latE6":38924131,"lonE6":-104773220,'
        '"alt":1652.4,"position":"38.924131,-104.77322","fix":"38.924131"}');
    expect(out.contains('38924131'), isFalse);
    expect(out.contains('104773220'), isFalse);
    expect(out, contains('38.92'));
    expect(out, contains('-104.77'));
    expect(out, contains('1652'));
    expect(out.contains('1652.4'), isFalse);
    expect(out.contains('38.924131'), isFalse);
  });

  test('a coordinate inside a soak line is coarsened in place', () {
    final String out = redactor.maskSecrets(
        'soak tx 42 rx 7 lat=38.924131 lon=-104.77322 alt=1652');
    expect(out.contains('38.924131'), isFalse);
    expect(out.contains('-104.77322'), isFalse);
    expect(out, contains('lat=38.92'));
    expect(out, contains('lon=-104.77'));
    // The counters that make the line evidence survive.
    expect(out, contains('tx 42 rx 7'));
  });

  test('a copied frame log keeps every frame except the channel secret', () {
    // A fixed 32-byte channel name, as the frame carries it.
    final String name = '41' * 32;
    final String info = '12' '02' '$name' '$psk';
    const String advert = '8811a4f0ffee00112233445566778899';
    final List<String> out = redactor.frames(<String>[info, advert]);

    expect(out[0].contains(psk), isFalse,
        reason: 'a pasted frame log must not hand out a channel PSK');
    expect(out[0], contains('1202'));
    expect(out[0], contains(name), reason: 'the slot is evidence');
    expect(out[0], contains('16_bytes'));
    expect(out[1], advert,
        reason: 'every other frame stays byte-for-byte replayable');
  });

  test('a frame too short to carry a secret is left alone', () {
    const String short = '12' '02' '41424344';
    expect(redactor.frame(short), short);
  });
}
