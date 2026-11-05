// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math';

/// Why a coverage ping may not go out now
/// (`meshmore-telemetry-coverage-spec.md` §7, decision D8.17).
enum CoveragePacingRefusal {
  /// Inside the 30-second floor. A manual ping never overrides this.
  tooSoon,

  /// This cell was pinged inside the last hour.
  cellFresh,

  /// The one manual override per hour is spent.
  manualAlreadyUsed,
}

/// One ping per 30 seconds, one per geohash-6 cell per hour, jittered.
///
/// No firmware-side reply cap was found in the companion or repeater code, so
/// the app paces itself and the copy says the app is doing the pacing: it
/// cannot promise other clients will. The 30-second floor is a hard limit at
/// the send path; the cell limit is what makes standing still cost one ping an
/// hour instead of 120.
///
/// A manual "ping now" overrides the cell limit once per hour and never the
/// floor: a person tapping a button cannot turn the app into a jammer.
final class CoveragePacing {
  CoveragePacing({required DateTime Function() clock, Random? random})
      : _clock = clock,
        _random = random;

  static const Duration floor = Duration(seconds: 30);
  static const Duration cellWindow = Duration(hours: 1);

  /// The scheduler jitters its own interval by this fraction so several phones
  /// in one place do not ping in lockstep.
  static const double jitterFraction = 0.2;

  final DateTime Function() _clock;
  final Random? _random;

  DateTime? _lastPing;
  DateTime? _manualUsedAt;
  final Map<String, DateTime> _cells = <String, DateTime>{};

  /// Asks whether a ping may go now, without spending anything.
  CoveragePacingRefusal? check({required String cell, bool manual = false}) {
    final DateTime now = _clock();
    final DateTime? last = _lastPing;
    if (last != null && now.difference(last) < floor) {
      return CoveragePacingRefusal.tooSoon;
    }
    final DateTime? cellAt = _cells[cell];
    final bool cellFresh =
        cellAt != null && now.difference(cellAt) < cellWindow;
    if (manual) {
      final DateTime? used = _manualUsedAt;
      if (used != null && now.difference(used) < cellWindow) {
        return CoveragePacingRefusal.manualAlreadyUsed;
      }
      // The override buys an early ping in this cell, nothing more.
      return null;
    }
    return cellFresh ? CoveragePacingRefusal.cellFresh : null;
  }

  /// Records a ping that went out. Returns false when it should not have.
  bool markPinged({required String cell, bool manual = false}) {
    if (check(cell: cell, manual: manual) != null) return false;
    final DateTime now = _clock();
    _lastPing = now;
    _cells[cell] = now;
    if (manual) _manualUsedAt = now;
    return true;
  }

  /// When the cell limit next allows a ping, for the "next in 12 minutes" copy.
  DateTime? nextAllowedAt(String cell) {
    final DateTime? cellAt = _cells[cell];
    if (cellAt == null) return null;
    return cellAt.add(cellWindow);
  }

  /// The interval with ±20 % jitter applied.
  Duration jittered(Duration base) {
    final Random? r = _random;
    if (r == null) return base;
    final int span = (base.inMilliseconds * jitterFraction).round();
    final int offset = r.nextInt(2 * span + 1) - span;
    return base + Duration(milliseconds: offset);
  }

  /// Forget everything (a new session, or a test).
  void reset() {
    _lastPing = null;
    _manualUsedAt = null;
    _cells.clear();
  }
}
