// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

import '../gen/app_localizations.dart';

/// APP-N4 — four degraded states, named rather than discovered.
///
/// Each one keeps the app usable for what still works and says what does not.
/// The states are inputs, not guesses: the caller passes what it observed, so
/// a banner can be tested without a radio, a full disk or a flat battery.
enum DegradedMode {
  /// No radio, or a radio that is not answering.
  radioDown,

  /// A write was refused for space. Nothing is deleted to make room.
  storageFull,

  /// The radio's clock has never been set, so its timestamps are not times.
  clockUnset,

  /// The radio's battery is at the level where transmissions get cut.
  batteryCritical,
}

/// The battery voltage at or below which the firmware's own transmissions
/// become unreliable. The radio reports millivolts (`CoreStats`); the app's
/// line is deliberately conservative.
const int kCriticalBatteryMilliVolts = 3400;

/// Which degraded states are active right now.
///
/// A plain value type: the widget layer decides when to recompute it, and a
/// test can construct any combination without a running radio.
class DegradedState {
  const DegradedState(this.modes);

  const DegradedState.none() : modes = const <DegradedMode>{};

  factory DegradedState.observe({
    required bool connected,
    required bool radioAnswering,
    required bool storageFull,
    required bool clockUnset,
    required int? batteryMilliVolts,
  }) {
    return DegradedState(<DegradedMode>{
      if (!connected || !radioAnswering) DegradedMode.radioDown,
      if (storageFull) DegradedMode.storageFull,
      if (clockUnset) DegradedMode.clockUnset,
      if (batteryMilliVolts != null &&
          batteryMilliVolts > 0 &&
          batteryMilliVolts <= kCriticalBatteryMilliVolts)
        DegradedMode.batteryCritical,
    });
  }

  final Set<DegradedMode> modes;

  bool get isDegraded => modes.isNotEmpty;

  /// The copy for the banner: what is wrong, then what still works. Ordered so
  /// the most consequential state is the one a reader sees first.
  String text(AppLocalizations l) {
    const List<DegradedMode> order = <DegradedMode>[
      DegradedMode.radioDown,
      DegradedMode.storageFull,
      DegradedMode.clockUnset,
      DegradedMode.batteryCritical,
    ];
    final List<DegradedMode> active =
        order.where(modes.contains).toList(growable: false);
    return active.map((DegradedMode m) => _line(l, m)).join('\n');
  }

  String _line(AppLocalizations l, DegradedMode m) => switch (m) {
        DegradedMode.radioDown => l.degradedRadioDown,
        DegradedMode.storageFull => l.degradedStorageFull,
        DegradedMode.clockUnset => l.degradedClockUnset,
        DegradedMode.batteryCritical => l.degradedBatteryCritical,
      };
}
