// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/services.dart';

/// What the gateway offers another app on this phone, as the Android side serves it.
///
/// The gateway's state is Dart's; the Android `GatewayHandoffService` only stores and serves what is
/// published here. `token` is present only while [state] is `running`.
class GatewayOffer {
  const GatewayOffer({
    required this.state,
    required this.port,
    this.token,
    this.radioKey,
    this.peerName,
  });

  final String state;
  final int port;
  final Uint8List? token;
  final String? radioKey;
  final String? peerName;

  static const GatewayOffer off = GatewayOffer(state: 'off', port: 0);

  Map<String, Object?> toArguments() => <String, Object?>{
        'state': state,
        'port': port,
        // Never a token for a gateway that is not running.
        'token': state == 'running' ? token : null,
        'radioKey': radioKey,
        'peerName': peerName,
      };

  @override
  bool operator ==(Object other) =>
      other is GatewayOffer &&
      other.state == state &&
      other.port == port &&
      other.radioKey == radioKey &&
      other.peerName == peerName &&
      _same(other.token, token);

  @override
  int get hashCode => Object.hash(state, port, radioKey, peerName, token?.length);

  static bool _same(Uint8List? a, Uint8List? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Where [GatewayService] puts its offer. An interface so the service is testable without a
/// platform channel, and so a platform with no handoff (iOS, desktop, tests) is a no-op.
abstract class GatewayHandoffPublisher {
  Future<void> publish(GatewayOffer offer);
  Future<void> clear();
}

/// [GatewayHandoffPublisher] over the `meshmore/gateway_handoff` channel.
///
/// Best effort by design: the handoff is a convenience over typing a code, so a missing platform
/// side (no plugin on this platform) must never break the gateway itself.
class ChannelGatewayHandoffPublisher implements GatewayHandoffPublisher {
  ChannelGatewayHandoffPublisher([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel('meshmore/gateway_handoff');

  final MethodChannel _channel;

  @override
  Future<void> publish(GatewayOffer offer) async {
    try {
      await _channel.invokeMethod<void>('publish', offer.toArguments());
    } on MissingPluginException {
      // No Android side on this platform.
    } on PlatformException {
      // The handoff is optional; the gateway keeps serving.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } on MissingPluginException {
      // No Android side on this platform.
    } on PlatformException {
      // Nothing to clear if the channel refuses.
    }
  }
}

/// Does nothing. The default off Android.
class NoGatewayHandoff implements GatewayHandoffPublisher {
  const NoGatewayHandoff();
  @override
  Future<void> publish(GatewayOffer offer) async {}
  @override
  Future<void> clear() async {}
}
