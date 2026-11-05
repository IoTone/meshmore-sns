// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';

/// The send-side budget for place-family messages
/// (`meshmore-places-spec.md` §7, decision D8.16): **6 per node per hour, burst
/// 2 in 5 minutes**.
///
/// A place message is 90–120 bytes, about a third of a second of airtime at
/// SF7/125 kHz, so this is channel politeness rather than cost: the failure it
/// prevents is one node posting twenty pins in a minute and making a channel
/// unusable. It is enforced at the send path, per reporter, not per channel,
/// and a confirmation is charged here too — otherwise the limit is bypassed by
/// confirming instead of reporting.
///
/// The refusal is never silent: [PlaceReportDecision.allowedAt] is the moment
/// the next report is allowed, which is what the composer shows as "you have
/// sent 6 in the last hour, next at 14:32".
final class PlaceReportBudget {
  PlaceReportBudget({required DateTime Function() clock}) : _clock = clock;

  /// Reports allowed in a rolling hour.
  static const int perHour = 6;

  /// Reports allowed inside [burstWindow].
  static const int burst = 2;

  static const Duration hourWindow = Duration(hours: 1);
  static const Duration burstWindow = Duration(minutes: 5);

  final DateTime Function() _clock;
  final List<DateTime> _sent = <DateTime>[];

  /// How many reports the last hour holds; also what the refusal copy quotes.
  int get sentInLastHour => _pruned().length;

  /// Asks whether a report may go now, without spending one.
  PlaceReportDecision check() =>
      _decide(_pruned(), wantToSend: false);

  /// Spends one when the budget allows it.
  PlaceReportDecision take() => _decide(_pruned(), wantToSend: true);

  /// Forgets the history (a new reporter, or a test).
  void reset() => _sent.clear();

  List<DateTime> _pruned() {
    final DateTime now = _clock();
    _sent.removeWhere((DateTime t) => now.difference(t) >= hourWindow);
    return _sent;
  }

  PlaceReportDecision _decide(List<DateTime> times, {required bool wantToSend}) {
    final DateTime now = _clock();
    final List<DateTime> inBurst = times
        .where((DateTime t) => now.difference(t) < burstWindow)
        .toList(growable: false);

    DateTime? blockedUntil;
    if (times.length >= perHour) {
      // The oldest of the newest six leaves the hour first.
      blockedUntil = times[times.length - perHour].add(hourWindow);
    }
    if (inBurst.length >= burst) {
      final DateTime burstFrees = inBurst[inBurst.length - burst]
          .add(burstWindow);
      if (blockedUntil == null || burstFrees.isAfter(blockedUntil)) {
        blockedUntil = burstFrees;
      }
    }

    final bool allowed = blockedUntil == null;
    if (allowed && wantToSend) _sent.add(now);
    return PlaceReportDecision(
      allowed: allowed,
      allowedAt: blockedUntil,
      sentInLastHour: times.length,
    );
  }
}

/// The budget's answer: allowed, or when it will be.
@immutable
final class PlaceReportDecision {
  const PlaceReportDecision({
    required this.allowed,
    required this.allowedAt,
    required this.sentInLastHour,
  });

  final bool allowed;

  /// The first moment another report may go, or null when [allowed].
  final DateTime? allowedAt;

  /// What the refusal copy quotes ("you have sent 6 in the last hour").
  final int sentInLastHour;
}
