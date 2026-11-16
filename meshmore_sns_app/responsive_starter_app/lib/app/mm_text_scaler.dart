// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/painting.dart' show TextScaler;

/// The app's text scale: the platform curve, multiplied by the user's own
/// setting, capped.
///
/// Two things were wrong with rebuilding `TextScaler.linear(osScale *
/// userScale)`:
///
///  * the platform scale is a *curve* on Android 14 and later, and taking
///    `scale(1.0)` and re-linearising it threw that curve away, so the same
///    body text rendered at different relative sizes in different places;
///  * the product was unbounded: the OS maximum times the in-app 1.6 is a 3.2x
///    scale, well past what any layout here is tested at, and labels clipped on
///    exactly the devices that need large text.
///
/// So the platform scaler is kept and multiplied, and the product is capped at
/// [ceiling] — the largest scale the accessibility floor test builds.
final class MmTextScaler extends TextScaler {
  const MmTextScaler({
    required this.os,
    required this.user,
    this.ceiling = 2.0,
  });

  /// The platform's own scaler, kept as a curve.
  final TextScaler os;

  /// The user's multiplier from Personalisation, 0.8 to 1.6.
  final double user;

  /// The largest ratio the app supports, in multiples of the base font size.
  final double ceiling;

  @override
  double scale(double fontSize) {
    final double scaled = os.scale(fontSize) * user;
    final double cap = fontSize * ceiling;
    return scaled < cap ? scaled : cap;
  }

  /// The linear equivalent, for the few framework paths that still ask for a
  /// single factor. The curve itself is only expressible through [scale].
  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => scale(1.0);

  @override
  bool operator ==(Object other) =>
      other is MmTextScaler &&
      other.os == os &&
      other.user == user &&
      other.ceiling == ceiling;

  @override
  int get hashCode => Object.hash(os, user, ceiling);

  @override
  String toString() =>
      'MmTextScaler(os: $os, user: $user, ceiling: $ceiling)';
}
