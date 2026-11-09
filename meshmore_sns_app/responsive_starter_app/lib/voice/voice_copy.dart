// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import '../gen/app_localizations.dart';

/// The voice feature's copy, in one place.
///
/// The app reads its strings through `AppLocalizations` at the call site, but a
/// feature that spans a capture, a codec and (next) a composer would otherwise
/// spell the same four button words and the same two refusals in each surface.
/// This is the same seam `LocalizedNotificationStrings` is for notifications:
/// one object that says what the feature says, so a surface cannot invent a
/// fifth way to name the button or a softer way to say the microphone is
/// missing.
///
/// Two of these carry a decision rather than a label:
///
/// * [limit] states the 20-second ceiling **before** the microphone opens, so
///   the user is not surprised by a recording that stops itself.
/// * [stoppedAtLimit] says that it happened, because a take that ended by
///   itself is otherwise indistinguishable from a button that was ignored.
final class VoiceCopy {
  const VoiceCopy(this.l10n);

  final AppLocalizations l10n;

  String get title => l10n.voiceTitle;

  /// "20 seconds, then it stops by itself."
  String get limit => l10n.voiceLimit;

  String get record => l10n.voiceRecord;

  String get stop => l10n.voiceStop;

  String get discard => l10n.voiceDiscard;

  /// The sentence for a take the ceiling ended.
  String get stoppedAtLimit => l10n.voiceStoppedAtLimit;

  /// The refusal when the microphone is not granted.
  String get noMicrophone => l10n.voiceNoMicrophone;

  /// The refusal when this build carries no codec — "rebuild", not "retry".
  String get noCodec => l10n.voiceNoCodec;

  /// What a send will cost, from the payload's own numbers.
  String cost({
    required int datagrams,
    required Duration airtime,
    required String mode,
  }) =>
      l10n.voiceCost(datagrams, airtime.inSeconds, mode);
}
