// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

import '../gen/app_localizations.dart';

/// The app's one relative-time ladder.
///
/// Six screens had each written this by hand — the device sheet, the radio
/// configuration block, the node list, the node sheet, the weather view (twice,
/// in the same file) and the docs reader — with the same thresholds copied
/// between them and only one of them localized. The thresholds are what they
/// agreed on, so they live here; the words stay with the family that owns the
/// tone, because "2 min ago" on a radio's status line and "2分前" in a docs
/// header are different sentences even when they measure the same thing.
///
/// Every function takes the age rather than a timestamp, so a widget test can
/// state an age without waiting for a clock.
enum AgeBand {
  /// Too recent to spell out, or a clock that ran backwards.
  now,

  /// Whole seconds, under a minute: only the surfaces that report on a live
  /// stream use this band.
  seconds,

  /// Whole minutes, under an hour.
  minutes,

  /// Whole hours, under a day.
  hours,

  /// Whole days.
  days,
}

/// Where an age falls on the ladder, and how many whole units it is.
final class AgeReading {
  const AgeReading(this.band, this.count);

  final AgeBand band;
  final int count;

  @override
  String toString() => 'AgeReading(${band.name}, $count)';

  @override
  bool operator ==(Object other) =>
      other is AgeReading && other.band == band && other.count == count;

  @override
  int get hashCode => Object.hash(band, count);
}

/// Where [age] falls.
///
/// A negative age is a clock that ran backwards — a sender whose stamp is ahead
/// of the reader, or a radio that was reset — and it reads as [AgeBand.now]
/// rather than as a negative count.
///
/// [nowUnder] is the only boundary the call sites disagreed on: the radio
/// surfaces fold anything under ninety seconds into "now" (a link that answered
/// a moment ago is not "30 s ago"), while the rest report whole seconds under a
/// minute. Pass the fold the surface uses; leave it at [Duration.zero] to get
/// the seconds band.
AgeReading readAge(Duration age, {Duration nowUnder = Duration.zero}) {
  final int s = age.inSeconds;
  if (s < 0) return const AgeReading(AgeBand.now, 0);
  if (nowUnder > Duration.zero && s < nowUnder.inSeconds) {
    return const AgeReading(AgeBand.now, 0);
  }
  if (s < 60) return AgeReading(AgeBand.seconds, s);
  if (s < 3600) return AgeReading(AgeBand.minutes, s ~/ 60);
  if (s < 86400) return AgeReading(AgeBand.hours, s ~/ 3600);
  return AgeReading(AgeBand.days, s ~/ 86400);
}

/// The age of a unix-seconds stamp, measured against [now] (the phone clock by
/// default). A stamp of zero or less is the firmware's own "never", and the
/// caller decides what that means before asking — this returns zero for it.
Duration ageSinceUnix(int unixSeconds, {DateTime? now}) {
  // The upper bound is the year 2100: `fromMillisecondsSinceEpoch` throws for
  // a value near 2^63, and a corrupt stored stamp would crash a list row.
  if (unixSeconds <= 0 || unixSeconds > 4102444800) return Duration.zero;
  final DateTime at = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  return (now ?? DateTime.now()).difference(at);
}

/// The radio-device family: "just now", "5 min ago", "2 h ago", "3 d ago".
///
/// Used by Device configuration's read-only block and by the paired-device
/// sheet, which describe a radio rather than a conversation.
String deviceAgo(AppLocalizations l, Duration age) {
  final AgeReading a = readAge(age, nowUnder: const Duration(seconds: 90));
  return switch (a.band) {
    AgeBand.now || AgeBand.seconds => l.deviceMgrAgoNow,
    AgeBand.minutes => l.deviceMgrAgoMinutes(a.count),
    AgeBand.hours => l.deviceMgrAgoHours(a.count),
    AgeBand.days => l.deviceMgrAgoDays(a.count),
  };
}

/// The node-sheet family, which spells out its seconds.
/// The age of a node's last-heard stamp, as the list and the detail sheet both
/// state it.
///
/// Two stamps cannot be read as an age and both are reported as unknown. A
/// stamp of zero is the firmware's "never": an unknown advert time must not be
/// written up as a hearing, and it used to be, which made every contact-synced
/// node read "0s ago". A stamp in the future is the phone and the radio
/// disagreeing about the clock, and `readAge` folds a negative age into "0s",
/// which claims a precision nobody has.
///
/// One function, because the two surfaces did disagree: the list said "—" and
/// the sheet said "0s ago" about the same node in the same session.
/// [compact] is the list's form ("12h"): a column of ages is scanned, not read,
/// and the sheet is where the sentence belongs.
String nodeHeardAgo(AppLocalizations l, int unixSeconds,
    {bool compact = false}) {
  if (unixSeconds <= 0) return '—';
  final Duration age = ageSinceUnix(unixSeconds);
  if (age < const Duration(seconds: -60)) return '—';
  return compact ? compactAgo(age) : nodeAgo(l, age);
}

String nodeAgo(AppLocalizations l, Duration age) {
  final AgeReading a = readAge(age);
  return switch (a.band) {
    AgeBand.now || AgeBand.seconds => l.nodeDetailAgoSeconds(a.count),
    AgeBand.minutes => l.nodeDetailAgoMinutes(a.count),
    AgeBand.hours => l.nodeDetailAgoHours(a.count),
    AgeBand.days => l.nodeDetailAgoDays(a.count),
  };
}

/// The docs family: "just now" when the snapshot has no timestamp or is new.
String docsAgo(AppLocalizations l, Duration? age) {
  if (age == null) return l.docsAgoJustNow;
  final AgeReading a = readAge(age);
  return switch (a.band) {
    AgeBand.now || AgeBand.seconds => l.docsAgoJustNow,
    AgeBand.minutes => l.docsAgoMinutes(a.count),
    AgeBand.hours => l.docsAgoHours(a.count),
    AgeBand.days => l.docsAgoDays(a.count),
  };
}

/// The weather family, which stops at hours because a reading older than a day
/// is stale rather than old: the view says "no reading" in that case.
String weatherAgo(AppLocalizations l, Duration age) {
  final AgeReading a = readAge(age);
  return switch (a.band) {
    AgeBand.now || AgeBand.seconds => l.weatherAgoSeconds(a.count),
    AgeBand.minutes => l.weatherAgoMinutes(a.count),
    AgeBand.hours => l.weatherAgoHours(a.count),
    // This family has no days word, and rounding to the days count would print
    // "2h ago" for something two days old. Hours is what its widest unit is.
    AgeBand.days => l.weatherAgoHours(age.inHours),
  };
}

/// The compact form the node rows carry: `12s`, `3m`, `2h`, `1d`.
///
/// Units are the letters a field instrument uses and read the same in every
/// locale, which is why this form takes no strings; it is still one
/// implementation rather than a copy per screen. A clock that ran backwards
/// reads `0s`, never a negative count.
String compactAgo(Duration age) {
  final AgeReading a = readAge(age);
  return switch (a.band) {
    AgeBand.now => '0s',
    AgeBand.seconds => '${a.count}s',
    AgeBand.minutes => '${a.count}m',
    AgeBand.hours => '${a.count}h',
    AgeBand.days => '${a.count}d',
  };
}
