// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-channel **last-read** timestamps, the channel sibling of [DmReadStore].
///
/// A channel badge used to be the whole channel's traffic, because nothing
/// recorded when the reader last looked. This records it: an inbound message
/// whose time is after the channel's last-read is unread, and opening the
/// channel clears the badge by moving the mark past it.
///
/// The mark only ever moves forward, so a stale "read" from a slower path
/// cannot un-read a later message.
class ChannelReadStore extends ChangeNotifier {
  ChannelReadStore({Map<int, int>? seed})
      : _data = <int, int>{...?seed};

  static const String _key = 'mm.channelRead.v1';

  final Map<int, int> _data;

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
        _data.clear();
        for (final MapEntry<String, dynamic> e in j.entries) {
          final int? idx = int.tryParse(e.key);
          final Object? v = e.value;
          if (idx == null || v is! num) continue;
          _data[idx] = v.toInt();
        }
      } catch (_) {
        // A corrupt blob is not worth a dialog: starting fresh shows more
        // unread than there is, which errs toward the reader noticing.
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(<String, int>{
      for (final MapEntry<int, int> e in _data.entries) '${e.key}': e.value,
    }));
  }

  /// Last-read millis for [channelIdx], or 0 when it was never opened.
  int lastReadAtMs(int channelIdx) => _data[channelIdx] ?? 0;

  /// Mark [channelIdx] read up to [at] (defaults to now). Idempotent and
  /// monotonic.
  Future<void> markRead(int channelIdx, {DateTime? at}) async {
    final int t = (at ?? DateTime.now()).millisecondsSinceEpoch;
    if (t <= (_data[channelIdx] ?? 0)) return;
    _data[channelIdx] = t;
    notifyListeners();
    await _persist();
  }

  /// Test seam.
  @visibleForTesting
  Map<int, int> snapshot() => Map<int, int>.unmodifiable(_data);
}
