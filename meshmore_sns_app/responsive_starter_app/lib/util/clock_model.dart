// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

import '../gen/app_localizations.dart';
import 'mm_format.dart';

/// APP-N3 — three clocks, never mixed.
///
/// The phone's wall clock, the radio's clock (which can be unset, wrong, or
/// reset by a power cycle) and a message's own stamp are different claims. The
/// model keeps them apart and says which one a rendered time came from, so the
/// app never presents a 1970 date as if it were a fact.
enum ClockSource {
  /// The phone's own clock. Trustworthy for ordering and for "now".
  phone,

  /// The radio's clock, read from `CURR_TIME`. Unset on a fresh radio and
  /// reset by a power cycle.
  radio,

  /// A timestamp carried by the message or advert itself: a sender's clock.
  message,
}

/// One time reading and how much it can be trusted.
class ClockReading {
  const ClockReading({
    required this.source,
    this.at,
    this.unset = false,
    this.disagreement,
  });

  /// A phone-clock reading.
  factory ClockReading.phone(DateTime at) =>
      ClockReading(source: ClockSource.phone, at: at);

  /// A radio-clock reading. [unixSeconds] of zero or less is the firmware's
  /// own "never set" (`CURR_TIME` never answered, or answered 0).
  factory ClockReading.radio(int unixSeconds) => unixSeconds <= 0
      ? const ClockReading(source: ClockSource.radio, unset: true)
      : ClockReading(
          source: ClockSource.radio,
          at: DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000),
        );

  /// A timestamp carried by the frame. A time after [now] is a sender's clock
  /// ahead of ours, not a message from the future.
  factory ClockReading.message(DateTime at, {required DateTime now}) {
    final Duration ahead = at.difference(now);
    return ClockReading(
      source: ClockSource.message,
      at: at,
      disagreement: ahead > const Duration(minutes: 1) ? ahead : null,
    );
  }

  final ClockSource source;
  final DateTime? at;

  /// True when the clock that would carry this time has never been set.
  final bool unset;

  /// How far [at] is ahead of the reader's clock, when that is more than a
  /// minute. A message from a sender whose clock runs fast is the common case.
  final Duration? disagreement;

  bool get isUsable => !unset && at != null;

  /// True when this reading may be shown as an absolute date. Only a phone
  /// clock, or a radio clock that agrees with the phone, qualifies.
  bool get allowsAbsolute => isUsable && disagreement == null;

  /// How old the reading is, or null when it cannot be known.
  Duration? age(DateTime now) => isUsable ? now.difference(at!) : null;

  @override
  String toString() => 'ClockReading(${source.name}'
      '${unset ? ' unset' : ' ${at!.toIso8601String()}'})';
}

/// The stamp a message row shows: the sender's own `HH:MM` when that clock
/// agrees with the reader's, and an explicit marker when it does not.
///
/// Absolute is what a reader expects beside a message, so the common case
/// keeps its shape; the case that used to lie — a sender whose clock runs
/// ahead, which used to print a time in the future — is named instead.
String clockStamp(AppLocalizations l, DateTime at,
    {DateTime? now, bool clock24 = true}) {
  final ClockReading r = ClockReading.message(at, now: now ?? DateTime.now());
  if (!r.allowsAbsolute) return clockText(l, r, now: now);
  // The shape the reader chose in Settings: "14:32" or "2:32 PM". A message's
  // time is the fact the row deliberately never prints, so the one place it is
  // shown is the place to respect the setting.
  return MmFormat.clock(at, clock24: clock24);
}

/// Renders a reading: relative age when the clock can be trusted, the
/// "unknown" sentence when it cannot, and a marker when two clocks disagree
/// by more than a minute.
String clockText(AppLocalizations l, ClockReading r, {DateTime? now}) {
  if (!r.isUsable) return l.clockUnknown;
  final DateTime n = now ?? DateTime.now();
  final Duration? gap = r.disagreement;
  if (gap != null) {
    return l.clockAhead('${gap.inMinutes}');
  }
  final Duration age = n.difference(r.at!);
  if (age.isNegative) return l.clockAhead('${(-age).inMinutes}');
  if (age < const Duration(minutes: 1)) return l.clockJustNow;
  if (age < const Duration(hours: 1)) return l.clockMinutesAgo('${age.inMinutes}');
  if (age < const Duration(days: 1)) return l.clockHoursAgo('${age.inHours}');
  return l.clockDaysAgo('${age.inDays}');
}
