import 'dart:async';

import 'package:flutter/services.dart';

import 'meshcore_controller.dart';

/// **Share the radio with other apps on this phone.**
///
/// A MeshCore BLE companion accepts exactly one central, by firmware design, and Android gives no
/// app a way to close another app's GATT link. So two apps that want the same radio cannot both have
/// it, and without an agreement they take turns evicting each other — which the operator sees as a
/// link that "works, then drops, then handshakes for ever".
///
/// The agreement is two broadcasts: `RADIO_WANTED` from the app that needs the radio, and
/// `RADIO_FREE` when it is done. `RadioLeaseReceiver` in the Android layer answers the first by
/// telling this class to let go, and answers the second by telling it to come back. The app keeps
/// running throughout: the foreground service, the notification and the pending work stay exactly as
/// they were, because losing the radio is not the same as being finished.
abstract final class RadioLease {
  static const MethodChannel _channel = MethodChannel('meshmore/radio_lease');

  /// Wiring the request to the controller. Called once, before the first frame's work starts.
  static void attach(MeshcoreController controller) {
    _channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'yield':
          await controller.yieldRadio();
        case 'resume':
          controller.resumeRadio();
      }
      return null;
    });
  }

  /// Whether another app holds the radio right now, as recorded before this process started.
  ///
  /// Read at launch so the app does not spend the first minute of somebody else's session trying to
  /// take back a radio it was told to give up.
  /// The answer last read from the platform, or null before the first read.
  static bool? _cached;

  /// Whether another app holds the radio, as last read.
  ///
  /// Synchronous on purpose. The probe is a platform channel, and a widget test
  /// that awaits one before pumping never advances the fake clock, so the
  /// timeout below cannot fire and the test hangs instead of failing: measured
  /// as `test/screens/diagnostics_screen_test.dart` never completing. Boot reads
  /// it once through [refresh]; everything else reads this.
  static bool get yieldedNow => _cached ?? false;

  /// Read the platform's answer once, for the boot chain to call before the
  /// first connect. Never throws: an unanswered channel means "not yielded".
  static Future<bool> refresh() async => _cached = await isYielded();

  static Future<bool> isYielded() async {
    try {
      // A timeout, because a platform channel that has no handler does not
      // always throw: in a test process the call is simply never answered, and
      // `autoConnectIfPaired` waited on it forever. Measured as the whole
      // diagnostics suite hanging rather than failing. A lease probe must never
      // be able to hold up the boot, so "nobody answered" means "not yielded".
      return await _channel
              .invokeMethod<bool>('isYielded')
              .timeout(const Duration(milliseconds: 300)) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } on TimeoutException {
      return false;
    }
  }
}
