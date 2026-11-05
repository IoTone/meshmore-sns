// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'sos_message.dart';

/// The check-in watch (`meshmore-sos-spec.md` §3, §5, D8.5).
///
/// A check-in is **one** send. The deadline travels as text in the message
/// (`until <local time>`) and the app watches it locally; nothing asks the
/// radio to keep a timer, because the radio cannot know whether the message
/// arrived and a firmware timer would be a protocol feature we do not control.
///
/// The row is not a promise that anyone will notice. An overdue check-in is
/// the app saying "the deadline passed and no answer came back", which is the
/// only claim the mechanism supports.
enum CheckinState {
  /// Raised, not yet sent.
  pending,

  /// Sent, deadline still ahead.
  watching,

  /// Sent, deadline passed, nobody has answered.
  overdue,

  /// Somebody answered before the deadline (`[SAFE:<id>]`, a direct message or
  /// a channel line naming the id).
  answered,
}

/// What kind of answer closed a check-in. A key is attributable; a channel
/// name is not, which is why the two are recorded apart.
enum CheckinAnswer { directKey, claimedOnChannel }

/// One check-in, as the store keeps it.
final class Checkin {
  const Checkin({
    required this.id,
    required this.nonce,
    required this.callsign,
    required this.raisedAt,
    required this.until,
    this.lat,
    this.lon,
    this.fixAt,
  });

  final String id;
  final List<int> nonce;
  final String callsign;
  final DateTime raisedAt;
  final DateTime until;
  final double? lat;
  final double? lon;
  final DateTime? fixAt;
}

final class CheckinWatch {
  CheckinWatch({required this.checkin, required DateTime Function() clock})
      : _clock = clock,
        _state = CheckinState.pending;

  final Checkin checkin;
  final DateTime Function() _clock;

  CheckinState _state;
  CheckinAnswer? _answer;
  List<int>? _answerKey;

  CheckinState get state => _state;
  CheckinAnswer? get answer => _answer;
  List<int>? get answerKey => _answerKey;

  /// The text to send, once. The `NOFIX` form when the fix is older than an
  /// hour, so a late responder is not sent to a stale coordinate.
  ({String? text, SosMessageRefusal? refusal}) text() {
    final DateTime now = _clock();
    final bool usableFix = _fixIsUsable(checkin.fixAt, now);
    return encodeCheckin(
      id: checkin.id,
      callsign: checkin.callsign,
      until: checkin.until,
      now: now,
      fixAt: checkin.fixAt,
      lat: usableFix ? checkin.lat : null,
      lon: usableFix ? checkin.lon : null,
    );
  }

  /// Records that the single send happened.
  void markSent() {
    if (_state != CheckinState.pending) return;
    _state = CheckinState.watching;
  }

  /// Re-evaluates the deadline. Called on a tick; the watch is the only place
  /// that decides a check-in is overdue, so the UI never counts time itself.
  void tick() {
    if (_state != CheckinState.watching) return;
    if (!_clock().isBefore(checkin.until)) _state = CheckinState.overdue;
  }

  /// An answer before the deadline closes it; after the deadline it is still
  /// evidence, but the row is already overdue and stays honest about that.
  CheckinState recordAnswer({
    required bool direct,
    List<int>? fromKey,
  }) {
    if (_state == CheckinState.answered) return _state;
    _answer = direct ? CheckinAnswer.directKey : CheckinAnswer.claimedOnChannel;
    _answerKey = fromKey == null ? null : List<int>.unmodifiable(fromKey);
    if (_state == CheckinState.watching) _state = CheckinState.answered;
    return _state;
  }

  static bool _fixIsUsable(DateTime? fixAt, DateTime now) {
    if (fixAt == null) return false;
    final Duration age = now.difference(fixAt);
    if (age.isNegative) return false;
    return age <= const Duration(hours: 1);
  }
}
