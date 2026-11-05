// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:shared_preferences/shared_preferences.dart';
import '../util/prefs.dart';

/// The alarm's destination, remembered between launches.
///
/// The owner's decision, 2026-11-05: the destination is chosen on the SOS
/// screen and remembered. It lives in preferences rather than in the
/// encrypted store because it is a routing choice, not message content: a
/// channel slot and up to four public keys, both of which are already visible
/// on air.
///
/// Every failure here is swallowed on purpose. A preference that cannot be
/// written leaves this session's alarm working, and a preference that cannot
/// be read falls back to the radio's own channel; neither is worth failing an
/// alarm over.
abstract final class SosPrefs {
  static const String _kChannel = 'mm.sos.channelSlot';
  static const String _kTargets = 'mm.sos.contactTargets';

  /// The saved channel slot, or null when the user never chose one.
  static Future<int?> channelSlot() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      return Prefs.readInt(p, _kChannel, fallback: -1) < 0
          ? null
          : Prefs.readInt(p, _kChannel);
    } catch (_) {
      return null;
    }
  }

  /// The saved direct-copy keys, as 64-hex strings, or null when none were
  /// chosen. An empty list is a real answer: channel-only.
  static Future<List<String>?> contactTargets() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      return p.getStringList(_kTargets);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save({
    required int channelSlot,
    required List<String> contactTargets,
  }) async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setInt(_kChannel, channelSlot);
      await p.setStringList(_kTargets, contactTargets);
    } catch (_) {
      // See the class comment: the alarm does not depend on this write.
    }
  }
}
