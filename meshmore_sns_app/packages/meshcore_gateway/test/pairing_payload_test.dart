// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:test/test.dart';

/// The same vectors LDMUX's `MeshReachabilityTest` pins for `parseGatewayCode`.
/// The two repositories do not share a fixture file, so a change here that is
/// not made there (or the reverse) is a contract break: keep the lists equal.
void main() {
  const String tok = '0123456789abcdef0123456789abcdef';
  Uint8List unhex(String s) => Uint8List.fromList(<int>[
        for (int i = 0; i < s.length; i += 2)
          int.parse(s.substring(i, i + 2), radix: 16),
      ]);

  test('encode makes the structured payload and parse reads it back', () {
    final GatewayPairingPayload p =
        GatewayPairingPayload(port: 41999, token: unhex(tok));
    expect(
        p.encode(), 'meshmore://gateway?v=1&host=127.0.0.1:41999&token=$tok');
    expect(GatewayPairingPayload.parse(p.encode()), p);
    expect(
        GatewayPairingPayload.parse(
                GatewayPairingPayload(token: unhex(tok)).encode())!
            .port,
        GatewayServer.defaultPort);
  });

  test('a bare 32-hex token is the default endpoint', () {
    final GatewayPairingPayload? p = GatewayPairingPayload.parse(tok);
    expect(p, isNotNull);
    expect(p!.host, '127.0.0.1');
    expect(p.port, 41731);
    expect(p.token, unhex(tok));
  });

  test('other loopback forms and unknown parameters are accepted', () {
    expect(
        GatewayPairingPayload.parse('meshmore://gateway?v=1&token=$tok')!.port,
        41731);
    expect(
        GatewayPairingPayload.parse(
                'MESHMORE://gateway?v=1&host=localhost:5&token=$tok')!
            .host,
        'localhost');
    expect(
        GatewayPairingPayload.parse(
                'meshmore://gateway?v=1&host=[::1]:41731&token=$tok')!
            .host,
        '::1');
    expect(
        GatewayPairingPayload.parse(
            'meshmore://gateway?future=x&v=1&token=$tok'),
        isNotNull);
  });

  test('anything malformed or off the device is refused whole', () {
    final List<String> bad = <String>[
      'meshmore://gateway?v=1&host=100.64.0.1:41731&token=$tok',
      'meshmore://gateway?v=1&host=192.168.1.5:41731&token=$tok',
      'meshmore://gateway?v=1&host=example.com:41731&token=$tok',
      'meshmore://gateway?v=1&host=127.0.0.1&token=$tok',
      'meshmore://gateway?v=1&host=127.0.0.1:0&token=$tok',
      'meshmore://gateway?v=1&host=127.0.0.1:70000&token=$tok',
      'meshmore://gateway?v=2&token=$tok',
      'meshmore://gateway?token=$tok',
      'meshmore://gateway?v=1',
      'meshmore://gateway?v=1&token=${tok.substring(0, 30)}',
      'meshmore://gateway?v=1&token=${tok.toUpperCase()}',
      'meshmore://gateway',
      'meshmore://gatewayx?v=1&token=$tok',
      'ldmux://pair?v=1&token=$tok',
      '${tok}00',
      tok.toUpperCase(),
      '',
      'not a code',
    ];
    for (final String b in bad) {
      expect(GatewayPairingPayload.parse(b), isNull, reason: b);
    }
  });

  test('the constructor refuses what it would not emit', () {
    expect(() => GatewayPairingPayload(host: '100.64.0.1', token: unhex(tok)),
        throwsArgumentError);
    expect(() => GatewayPairingPayload(port: 0, token: unhex(tok)),
        throwsArgumentError);
    expect(
        () => GatewayPairingPayload(token: Uint8List(15)), throwsArgumentError);
  });

  test(
      'the payload carries the grant and no key material, and never prints the token',
      () {
    final GatewayPairingPayload p = GatewayPairingPayload(token: unhex(tok));
    expect(p.toString().contains(tok), isFalse);
    final Uri u = Uri.parse(p.encode());
    expect(u.queryParameters.keys.toSet(), <String>{'v', 'host', 'token'});
  });
}
