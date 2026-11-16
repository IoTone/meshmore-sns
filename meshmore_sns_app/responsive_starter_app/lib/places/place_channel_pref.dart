// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:shared_preferences/shared_preferences.dart';

import '../util/prefs.dart';

/// The channel slot a place report goes to, remembered between reports.
///
/// A place is ordinary channel text (`meshmore-places-spec.md` §3), so it lands
/// on exactly one slot and every client on that slot can read it. The sheet
/// used to send to whichever channel happened to be active, which meant a
/// report dropped while #cos was open went to #cos, and the reader could
/// neither choose the slot nor find out afterwards which one it went to.
///
/// The choice is remembered because a reader who reports on #field once is
/// reporting there again, and re-picking the slot on every report would make
/// the picker a tax rather than a control. Nothing is stored until the reader
/// picks something: an unset preference means "follow the active channel",
/// which is the behaviour the app had, and it stays the default.
abstract final class PlaceChannelPref {
  static const String key = 'mm.places.channel';

  /// The remembered slot, or null when the reader has never chosen one.
  ///
  /// A stored value that is not an int is dropped and counted by [Prefs], the
  /// same way every other preference read survives a value it did not expect.
  static Future<int?> read() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    if (!p.containsKey(key)) return null;
    final int slot = Prefs.readInt(p, key, fallback: -1);
    return slot < 0 ? null : slot;
  }

  static Future<void> write(int channelIdx) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setInt(key, channelIdx);
  }

  /// Forgets the choice, so the next report follows the active channel again.
  static Future<void> clear() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.remove(key);
  }
}
