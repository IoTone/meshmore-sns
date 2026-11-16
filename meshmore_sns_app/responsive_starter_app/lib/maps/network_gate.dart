// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/services.dart';

/// Whether the current connection is one the user pays for by the byte.
///
/// A region pack is tens to hundreds of megabytes, so the downloader honours a
/// Wi-Fi-only preference by default. The answer comes from the platform's own
/// `NetworkCapabilities`, not from a plugin's guess: an unmetered hotspot and a
/// metered "unlimited" plan both have to be judged by the system that knows the
/// carrier's own metering flag. Null means "this host cannot say", which is
/// treated as unmetered so a test or a desktop is never blocked.
abstract class NetworkGate {
  const NetworkGate();

  /// True when the connection is unmetered, false when metered, null when
  /// unknown.
  Future<bool?> unmetered();
}

/// The real thing on Android: `ConnectivityManager` + `NetworkCapabilities`.
class PlatformNetworkGate extends NetworkGate {
  const PlatformNetworkGate();

  static const MethodChannel _channel = MethodChannel('meshmore/network');

  @override
  Future<bool?> unmetered() async {
    try {
      return await _channel.invokeMethod<bool>('unmetered');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// Always unmetered. Tests and hosts without a platform side.
class AlwaysUnmetered extends NetworkGate {
  const AlwaysUnmetered();

  @override
  Future<bool?> unmetered() async => true;
}
