// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Payloads that were mid-flight when the process ended.
///
/// A transfer lives in memory, so a kill — a low-memory kill, an OEM battery
/// manager, a force-stop — loses it with no trace: no receipt, no error, and
/// nothing on screen. One small record per payload in flight is enough for the
/// next launch to report the transfer as interrupted instead of dropping it
/// silently, which is the difference between a user retrying and a user
/// believing the photo arrived.
abstract final class MediaJournal {
  /// Test seam: keeps the journal off the preference store.
  @visibleForTesting
  static Set<int>? override;

  static const String _key = 'mm.media.inflight.v1';

  static Future<Set<int>> _read() async {
    if (override != null) return Set<int>.of(override!);
    final SharedPreferences p = await SharedPreferences.getInstance();
    return <int>{
      for (final String s in p.getStringList(_key) ?? const <String>[])
        if (int.tryParse(s) case final int id) id,
    };
  }

  static Future<void> _write(Set<int> ids) async {
    if (override != null) {
      override = Set<int>.of(ids);
      return;
    }
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setStringList(
        _key, <String>[for (final int id in ids) '$id']);
  }

  /// A transfer is about to start sending.
  static Future<void> markStarted(int payloadId) async {
    final Set<int> ids = await _read();
    if (ids.add(payloadId)) await _write(ids);
  }

  /// The transfer reached its end, whatever the end was.
  static Future<void> markFinished(int payloadId) async {
    final Set<int> ids = await _read();
    if (ids.remove(payloadId)) await _write(ids);
  }

  /// Payload ids that were in flight when the last process ended. Reading does
  /// not clear them: the caller decides when it has told the user.
  static Future<List<int>> interrupted() async {
    final List<int> ids = (await _read()).toList()..sort();
    return ids;
  }

  /// The user has seen the notice; forget the record so it is not shown twice.
  static Future<void> forget(List<int> payloadIds) async {
    final Set<int> ids = await _read();
    ids.removeAll(payloadIds);
    await _write(ids);
  }

  @visibleForTesting
  static void reset() => override = null;
}

/// How many transfers the last process left unfinished, for the one surface
/// that tells the user, and the action that clears it.
class MediaInterruptions extends ChangeNotifier {
  MediaInterruptions({Set<int>? initial}) : _ids = initial ?? <int>{};

  Set<int> _ids;

  int get count => _ids.length;

  bool get any => _ids.isNotEmpty;

  /// Reads what the last process left behind.
  Future<void> load() async {
    _ids = (await MediaJournal.interrupted()).toSet();
    notifyListeners();
  }

  /// The user has seen it.
  Future<void> acknowledge() async {
    if (_ids.isEmpty) return;
    await MediaJournal.forget(_ids.toList());
    _ids = <int>{};
    notifyListeners();
  }

  @visibleForTesting
  void setIds(Set<int> ids) {
    _ids = ids;
    notifyListeners();
  }
}
