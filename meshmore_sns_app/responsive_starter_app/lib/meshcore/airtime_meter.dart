// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'airtime.dart';

/// What the meter says about one prospective send.
///
/// The three numbers are what the copy needs: whether it fits, what is left in
/// the window, and what the frame would cost. A refusal that cannot say how
/// much room is left is not actionable, and a send that is charged without
/// being told its price cannot show a cost line that matches the meter.
final class AirtimeSpend {
  const AirtimeSpend({
    required this.allowed,
    required this.spent,
    required this.budget,
    required this.needed,
  });

  /// Whether this frame fits inside the rolling window.
  final bool allowed;

  /// What has been charged inside the current window, including [needed] when
  /// [allowed] and nothing when it is not.
  final Duration spent;

  /// The policy's allowance, or null when the policy has no cap.
  final Duration? budget;

  /// What this frame would cost.
  final Duration needed;

  /// Room left after this frame, or null when there is no cap.
  Duration? get remaining {
    final Duration? b = budget;
    return b == null ? null : _clampZero(b - spent);
  }

  @override
  String toString() => 'AirtimeSpend(allowed: $allowed, spent: $spent, '
      'budget: $budget, needed: $needed)';
}

/// A send the meter refused.
///
/// Typed rather than a sentence so every caller can tell a self-imposed refusal
/// from a radio error: the radio never saw this frame, so nothing about it is
/// unknown and nothing needs retrying on the link.
final class AirtimeRefused implements Exception {
  const AirtimeRefused({required this.needed, required this.budget});

  /// What the frame would have cost.
  final Duration needed;

  /// The allowance it did not fit inside.
  final Duration? budget;

  @override
  String toString() => 'AirtimeRefused(needed: $needed, budget: $budget)';
}

/// The app's own transmitter meter: what this phone has spent in the last hour.
///
/// A rolling window, not a calendar hour, because a duty cycle is about the
/// last 3600 s rather than about the clock. Charges are kept per minute, so the
/// memory is 60 entries whatever the traffic and a bucket falls out of the
/// window by itself.
///
/// The meter always charges, even under [AirtimePolicy.ownedChannel], because
/// [AirtimePolicy.isUnlimited] means "no cap" and not "no measurement": the
/// figure stays honest so the user can see what a photo or a flood costs.
///
/// Nothing here knows about the radio. The caller supplies the estimate, which
/// is what lets a test spend an hour in a millisecond.
final class AirtimeMeter {
  AirtimeMeter({
    AirtimePolicy initialPolicy = AirtimePolicy.onePercentDutyCycle,
    DateTime Function()? clock,
  })  : policy = initialPolicy,
        _clock = clock ?? DateTime.now;

  /// Minutes held in the window. One hour of buckets, inclusive of the current
  /// one, so a charge made 59 minutes ago still counts.
  static const int windowMinutes = 60;

  final DateTime Function() _clock;

  /// Which policy the meter is enforcing. Assigning it keeps the history: what
  /// was already spent is a fact about the hour, not about the policy.
  AirtimePolicy policy;

  /// Epoch minute → charged time. Only minutes inside the window are kept.
  final Map<int, Duration> _minutes = <int, Duration>{};

  /// The policy's allowance, or null for no cap.
  Duration? get budget => policy.hourlyBudget;

  int _nowMinute() => _clock().millisecondsSinceEpoch ~/ 60000;

  /// Drops buckets that fell out of the window.
  ///
  /// A clock that jumps backwards (NTP correction, a manual change) would
  /// otherwise leave future buckets holding charges that never expire, so
  /// anything ahead of now is dropped too: the window follows the clock the
  /// user's phone reports, and it never holds time that has not happened.
  void _prune() {
    final int now = _nowMinute();
    _minutes.removeWhere((int minute, Duration _) =>
        minute > now || now - minute >= windowMinutes);
  }

  /// What has been charged in the current window.
  Duration get spent {
    _prune();
    Duration total = Duration.zero;
    for (final Duration d in _minutes.values) {
      total += d;
    }
    return total;
  }

  /// Room left in the window, or null when the policy has no cap.
  Duration? get remaining {
    final Duration? b = budget;
    return b == null ? null : _clampZero(b - spent);
  }

  /// What [cost] would do, without charging it.
  AirtimeSpend quote(Duration cost) {
    final Duration already = spent;
    final Duration? b = budget;
    final bool allowed = b == null || already + cost <= b;
    return AirtimeSpend(
      allowed: allowed,
      spent: allowed ? already + cost : already,
      budget: b,
      needed: cost,
    );
  }

  /// Adds [cost] to the window.
  ///
  /// Separate from [quote] on purpose: the caller charges only what actually
  /// left the phone, and refunds when the write threw.
  void charge(Duration cost) {
    if (cost <= Duration.zero) return;
    final int now = _nowMinute();
    _minutes[now] = (_minutes[now] ?? Duration.zero) + cost;
    _prune();
  }

  /// Takes a charge back after a write that did not leave the phone.
  void refund(Duration cost) {
    if (cost <= Duration.zero) return;
    final int now = _nowMinute();
    final Duration? held = _minutes[now];
    if (held == null) return;
    final Duration left = held - cost;
    if (left <= Duration.zero) {
      _minutes.remove(now);
    } else {
      _minutes[now] = left;
    }
  }

  /// Forgets everything. Tests only: a real window empties by itself.
  void reset() => _minutes.clear();
}

Duration _clampZero(Duration d) => d < Duration.zero ? Duration.zero : d;

/// The time-on-air of one frame, from the radio's own parameters where known.
///
/// A radio that has not reported its parameters yet falls back to the flat
/// figure [AirtimeEstimator] documents, which is calibrated to the US/Canada
/// preset. Under-counting before the first self-info is a bounded problem (the
/// handshake's frames are a few dozen bytes) and the alternative — refusing to
/// send until the radio is queried — would deadlock the handshake itself.
AirtimeEstimator airtimeEstimatorFor(AirtimeEstimator? reported) =>
    reported ?? const AirtimeEstimator();

/// Builds the exact estimator for a radio from its reported parameters.
///
/// Returns null when the values are not in range, because a partly decoded
/// self-info must not silently produce a 0 ms frame.
AirtimeEstimator? loraEstimator({
  required double bandwidthKhz,
  required int spreadingFactor,
  required int codingRate,
}) {
  final int bw = (bandwidthKhz * 1000).round();
  if (bw <= 0) return null;
  if (spreadingFactor < 5 || spreadingFactor > 12) return null;
  if (codingRate < 5 || codingRate > 8) return null;
  return AirtimeEstimator.lora(
    bandwidthHz: bw,
    spreadingFactor: spreadingFactor,
    codingRate: codingRate,
  );
}
