// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'constants.dart';
import 'server.dart';

/// What the gateway's "Connected apps" QR carries: the **L2 grant**, and only that.
///
///     meshmore://gateway?v=1&host=127.0.0.1:41731&token=<32 lowercase hex>
///
/// The gateway is a loopback service on this phone, so [host] is a loopback
/// literal. A code naming any other host is refused when read: the receiving
/// app would send the token off the device. The port is data because the gateway
/// may be run on another one.
///
/// **No key material.** The end-to-end session keys travel in the *other* app's
/// own pairing code (LDMUX `ldmux code --mesh-only`), never here: this payload
/// lets a holder talk to the radio gateway on this phone and nothing more, and
/// MeshMore must not learn what rides inside the session (architecture §13).
///
/// A bare 32-hex token, which earlier builds printed, is still read as "the
/// default endpoint". Mirrored by `parseGatewayCode` in LDMUX
/// (`dev.ldmux.mobile.mesh.MeshGatewayCode`); both repositories pin the same
/// vectors in their tests, so change one and change the other.
class GatewayPairingPayload {
  GatewayPairingPayload({
    this.host = '127.0.0.1',
    this.port = GatewayServer.defaultPort,
    required Uint8List token,
  }) : token = Uint8List.fromList(token) {
    if (token.length != GatewayLimits.pairingTokenBytes) {
      throw ArgumentError('pairing token must be '
          '${GatewayLimits.pairingTokenBytes} bytes');
    }
    if (!_isLoopback(host)) {
      throw ArgumentError('gateway host must be a loopback literal');
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError('gateway port must be 1..65535');
    }
  }

  /// The payload format version.
  static const int version = 1;

  final String host;
  final int port;

  /// The 16-byte pairing token. A credential: never in [toString].
  final Uint8List token;

  /// The text to put in the QR code.
  String encode() => 'meshmore://gateway?v=$version'
      '&host=${host.contains(':') ? '[$host]' : host}:$port&token=$_hex';

  String get _hex =>
      token.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// The grant in [text], or null if it is not one. Anything malformed is
  /// refused whole.
  static GatewayPairingPayload? parse(String text) {
    final String s = text.trim();
    if (_token32.hasMatch(s)) return GatewayPairingPayload(token: _unhex(s));
    const String prefix = 'meshmore://gateway';
    if (s.length < prefix.length ||
        s.substring(0, prefix.length).toLowerCase() != prefix) {
      return null;
    }
    String rest = s.substring(prefix.length);
    final int hash = rest.indexOf('#');
    if (hash >= 0) rest = rest.substring(0, hash);
    if (!rest.startsWith('?')) return null;
    final Map<String, String> params = <String, String>{};
    for (final String part in rest.substring(1).split('&')) {
      final int eq = part.indexOf('=');
      if (part.isEmpty || eq < 0) continue;
      params.putIfAbsent(part.substring(0, eq), () => part.substring(eq + 1));
    }
    if (params['v'] != '$version') return null;
    final String? token = params['token'];
    if (token == null || !_token32.hasMatch(token)) return null;
    String host = '127.0.0.1';
    int port = GatewayServer.defaultPort;
    final String? h = params['host'];
    if (h != null) {
      final RegExpMatch? m = _hostPort.firstMatch(h);
      if (m == null) return null;
      host = m.group(1)!.replaceAll(RegExp(r'^\[|\]$'), '');
      port = int.parse(m.group(2)!);
      if (!_isLoopback(host) || port < 1 || port > 65535) return null;
    }
    return GatewayPairingPayload(host: host, port: port, token: _unhex(token));
  }

  static final RegExp _token32 = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _hostPort =
      RegExp(r'^(\[[0-9a-fA-F:.]+\]|[^:\[\]]+):(\d{1,5})$');

  static bool _isLoopback(String host) {
    final String h = host.trim().toLowerCase();
    if (h == 'localhost' || h == '::1') return true;
    final List<String> p = h.split('.');
    if (p.length != 4 || p[0] != '127') return false;
    return p.every((String x) {
      if (x.isEmpty || x.length > 3 || int.tryParse(x) == null) return false;
      if (x.length > 1 && x.startsWith('0')) return false;
      return int.parse(x) <= 255;
    });
  }

  static Uint8List _unhex(String s) => Uint8List.fromList(<int>[
        for (int i = 0; i < s.length; i += 2)
          int.parse(s.substring(i, i + 2), radix: 16),
      ]);

  @override
  bool operator ==(Object other) =>
      other is GatewayPairingPayload &&
      other.host == host &&
      other.port == port &&
      _eq(other.token, token);

  static bool _eq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(host, port, Object.hashAll(token));

  @override
  String toString() => 'GatewayPairingPayload($host:$port)';
}
