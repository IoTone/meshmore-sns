// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:shared_preferences/shared_preferences.dart';

import '../util/prefs.dart';

/// Whether a picture goes out in colour.
///
/// Off by default, and the default is the point: a mesh photo has one budget,
/// and two of the three channels a colour picture spends are the cheapest third
/// of the data to give up. At 320x240 and a 2-4 KB target the app is choosing
/// image codecs at about 0.3 bits per pixel, and the same budget in greyscale
/// buys a sharp picture instead of a soft one.
///
/// It is a preference, not a policy, because a picture is sometimes the point:
/// a coloured map, a warning light, a person's clothing.
abstract final class MediaPrefs {
  static const String _kColor = 'mm.media.colorPhotos';

  static Future<bool> colorPhotos() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return Prefs.readBool(p, _kColor);
  }

  static Future<void> setColorPhotos(bool v) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setBool(p, _kColor, v);
  }
}
