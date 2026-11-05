// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:math';

import 'sos_message.dart';
import 'sos_schedule.dart';

/// The SOS state machine (`meshmore-sos-spec.md` §8, §9).
///
/// ```
/// idle --raise--> arming --confirm--> active --ack(key)--> acknowledged --dismiss--> closed
///                     |                 |  --cancel-----> cancelled ----------------> closed
///                     |                 |  --t=3600s----> expired ------------------> closed
///                     +--abort--------> idle
/// ```
///
/// The engine owns only the decision logic — when a packet is due, whether an
/// acknowledgement is attributable, when the schedule stops. It emits text and
/// events; it does not send, store or draw. That is what makes a 3600-second
/// scenario run in milliseconds with a fake clock.
enum SosState { idle, arming, active, acknowledged, cancelled, expired, closed }

/// Why a raise or a confirmation was refused. Named so the screen can say it.
enum SosRefusal {
  alreadyActive,
  holdNotComplete,
  tooLong,
  noDestination,
  noWords,
  noIdentity,
}

/// Where an alarm is addressed. The two destinations carry different
/// guarantees, which is why they are separate: a channel is heard by whoever
/// is in range, a direct message is attributable to a key.
final class SosTargets {
  SosTargets({this.channelId, List<List<int>>? contactKeys})
      : contactKeys = List<List<int>>.unmodifiable(
            (contactKeys ?? const <List<int>>[])
                .take(maxContactTargets)
                .map((List<int> k) => List<int>.unmodifiable(k)));

  /// Up to four contact keys get a direct copy (`meshmore-sos-spec.md` §6).
  static const int maxContactTargets = 4;

  final String? channelId;
  final List<List<int>> contactKeys;

  bool get isEmpty => channelId == null && contactKeys.isEmpty;
}

/// Everything one alarm needs, and everything the store must keep when the
/// process dies: the id, the nonce it was derived from, the words, the fix at
/// raise, and where it goes.
final class SosRaise {
  const SosRaise({
    required this.id,
    required this.nonce,
    required this.raisedAt,
    required this.callsign,
    required this.words,
    required this.targets,
    this.lat,
    this.lon,
    this.fixAt,
  });

  final String id;
  final List<int> nonce;
  final DateTime raisedAt;
  final String callsign;
  final String words;
  final SosTargets targets;
  final double? lat;
  final double? lon;
  final DateTime? fixAt;
}

/// One packet the engine says is due, with the exact text it would send.
final class SosSend {
  const SosSend({
    required this.packet,
    required this.text,
    required this.fixAge,
  });

  final SosPacket packet;
  final String text;

  /// Null when the send went out as `NOFIX` (no fix, or one older than an
  /// hour, APP-H2). The schedule does not change: twelve sends and ten beacons
  /// go out either way, the position does not.
  final Duration? fixAge;
}

/// What an acknowledgement did.
enum SosAckOutcome {
  /// A direct ACK from a key this alarm was addressed to: the alarm stops.
  stopped,

  /// A direct ACK from some other key: shown and counted, alarm continues.
  countedNotAddressed,

  /// A channel ACK: a display name in decrypted text, nothing more. The alarm
  /// continues until the user says otherwise.
  claimed,

  /// The same key acknowledged this id already; one row, no state change.
  duplicate,

  /// An ACK for another request, or one arriving after the schedule ended.
  ignored,
}

/// The row the store keeps. Rebuilt on relaunch so an alarm never silently
/// disappears mid-schedule (§13.10).
final class SosSnapshot {
  const SosSnapshot({
    required this.state,
    required this.raise,
    required this.issued,
  });

  final SosState state;
  final SosRaise raise;

  /// Packet keys already emitted, as `'send#3'` / `'beacon#7'`.
  final Set<String> issued;
}

final class SosEngine {
  SosEngine({required DateTime Function() clock, Random? random})
      : _clock = clock,
        _random = random;

  /// The raise is destructive to the channel, so it is a three-second hold
  /// with the destination and the fix shown, not a dialog to read.
  static const Duration hold = Duration(seconds: 3);

  /// An alarm already running refuses a second raise and brings itself to the
  /// front instead (§8: one active alarm per device).
  final DateTime Function() _clock;
  final Random? _random;

  SosState _state = SosState.idle;
  SosRaise? _raise;
  List<SosPacket> _plan = const <SosPacket>[];
  final Set<String> _issued = <String>{};
  final List<DateTime> _armingAt = <DateTime>[];
  final Map<String, List<int>> _acks = <String, List<int>>{};
  bool _safeSent = false;

  SosState get state => _state;
  SosRaise? get activeRequest => _raise;
  List<SosPacket> get plan => _plan;

  /// True while the schedule should keep emitting.
  bool get isRunning => _state == SosState.active;

  /// The packets the schedule still owes, in order.
  ///
  /// The screen counts down to the first one and says how many are left; the
  /// sender loop reports each as it goes. Read from the same plan the sender
  /// emits from, so the countdown cannot disagree with what goes on air.
  List<SosPacket> get remaining => <SosPacket>[
        for (final SosPacket p in _plan)
          if (!_issued.contains(_keyOf(p))) p,
      ];

  SosSnapshot? snapshot() {
    final SosRaise? r = _raise;
    if (r == null) return null;
    return SosSnapshot(
      state: _state,
      raise: r,
      issued: Set<String>.unmodifiable(_issued),
    );
  }

  /// Rebuilds an alarm that was running when the process died.
  ///
  /// Packets already on air are **not** replayed: the radio's seen table drops
  /// an identical repeat, so a replay would send nothing and pretend to. What
  /// is left of the schedule goes out with fresh salts. An alarm whose hour
  /// ran while the app was dead is `expired`, not resumed.
  void restore(SosSnapshot snapshot) {
    _raise = snapshot.raise;
    _plan = SosSchedule.plan(raisedAt: snapshot.raise.raisedAt, random: _random);
    _issued
      ..clear()
      ..addAll(snapshot.issued);
    switch (snapshot.state) {
      case SosState.active:
        _state = SosState.active;
        break;
      case SosState.acknowledged:
      case SosState.cancelled:
      case SosState.expired:
      case SosState.closed:
      case SosState.idle:
      case SosState.arming:
        // A schedule that is not running is not resumed; `arming` never
        // survived a process death because the hold is three seconds.
        _state = snapshot.state == SosState.arming ? SosState.idle : snapshot.state;
        break;
    }
  }

  /// Raises an alarm: `idle` → `arming`. Refusals are named, never silent.
  SosRefusal? raise(SosRaise request) {
    if (_state == SosState.arming ||
        _state == SosState.active ||
        _state == SosState.acknowledged) {
      return SosRefusal.alreadyActive;
    }
    if (request.targets.isEmpty) return SosRefusal.noDestination;
    if (request.words.trim().isEmpty) return SosRefusal.noWords;
    if (!RegExp(r'^[0-9a-f]{6}$').hasMatch(request.id)) {
      return SosRefusal.noIdentity;
    }

    // Prove the whole message fits before the hold starts: a truncated SOS
    // loses the callsign or the coordinate, so an over-long one is refused at
    // the composer with the byte count, not cut on air.
    final ({String? text, SosMessageRefusal? refusal}) first = encodeSos(
      id: request.id,
      callsign: request.callsign,
      words: request.words,
      fixAt: request.fixAt,
      now: _clock(),
      lat: request.lat,
      lon: request.lon,
      nonce: request.nonce,
      index: 1,
    );
    if (first.refusal != null) return SosRefusal.tooLong;

    _raise = request;
    _plan = SosSchedule.plan(raisedAt: request.raisedAt, random: _random);
    _issued.clear();
    _acks.clear();
    _armingAt
      ..clear()
      ..add(_clock());
    _safeSent = false;
    _state = SosState.arming;
    return null;
  }

  /// Completes the hold. Before three seconds the alarm is not raised.
  SosRefusal? confirm() {
    if (_state != SosState.arming) return SosRefusal.alreadyActive;
    final DateTime? started = _armingAt.isEmpty ? null : _armingAt.first;
    if (started == null || _clock().difference(started) < hold) {
      return SosRefusal.holdNotComplete;
    }
    _state = SosState.active;
    return null;
  }

  /// `arming` → `idle`, no packet ever sent.
  void abort() {
    if (_state != SosState.arming) return;
    _state = SosState.idle;
    _raise = null;
    _armingAt.clear();
  }

  /// The raiser's deliberate stop, `active` → `cancelled`. Distinct from an
  /// acknowledgement, which is somebody else's word.
  void cancel() {
    if (_state == SosState.arming) {
      abort();
      return;
    }
    if (_state != SosState.active && _state != SosState.acknowledged) return;
    _state = SosState.cancelled;
  }

  /// "I'm safe": one `[SAFE:<id6>]`, then nothing more.
  ///
  /// The frame is returned rather than sent so the caller can record its
  /// result, and it is sent exactly once: a second call returns null.
  ({String? text, SosMessageRefusal? refusal})? iAmSafe() {
    final SosRaise? r = _raise;
    // Nothing was raised while arming, so there is no alarm to call off.
    if (r == null ||
        _state == SosState.idle ||
        _state == SosState.arming ||
        _state == SosState.cancelled ||
        _state == SosState.closed) {
      return null;
    }
    if (_safeSent) return null;
    _safeSent = true;
    _state = SosState.cancelled;
    return encodeSafe(id: r.id, callsign: r.callsign);
  }

  /// The user dismisses an ended or acknowledged alarm; the row stays.
  void dismiss() {
    if (_state == SosState.acknowledged ||
        _state == SosState.cancelled ||
        _state == SosState.expired) {
      _state = SosState.closed;
    }
  }

  /// Everything due at [now] that has not been emitted, and the hard stop.
  ///
  /// Called on a tick; returns an empty list when nothing is due, which is the
  /// common case (22 packets across 57 minutes).
  List<SosSend> advanceTo(DateTime now) {
    final SosRaise? r = _raise;
    if (r == null) return const <SosSend>[];
    if (now.isBefore(r.raisedAt)) {
      // A clock that jumped backwards must not replay the schedule.
      return const <SosSend>[];
    }
    if (_state == SosState.active &&
        !now.isBefore(SosSchedule.hardStopAt(r.raisedAt))) {
      _state = SosState.expired;
    }
    if (_state != SosState.active) return const <SosSend>[];

    final List<SosSend> due = <SosSend>[];
    for (final SosPacket p in _plan) {
      if (p.dueAt.isAfter(now)) break;
      if (_issued.contains(_keyOf(p))) continue;
      final bool usableFix = _fixIsUsable(r.fixAt, now);
      final ({String? text, SosMessageRefusal? refusal}) built = encodeSos(
        id: r.id,
        callsign: r.callsign,
        words: r.words,
        fixAt: r.fixAt,
        now: now,
        lat: usableFix ? r.lat : null,
        lon: usableFix ? r.lon : null,
        nonce: r.nonce,
        index: p.kind == SosPacketKind.send ? p.index : SosSchedule.sendCount + p.index,
      );
      if (built.text == null) continue; // refused, nothing goes on air
      _issued.add(_keyOf(p));
      due.add(SosSend(
        packet: p,
        text: built.text!,
        fixAge: usableFix && r.fixAt != null ? now.difference(r.fixAt!) : null,
      ));
    }
    return due;
  }

  /// Attributes an acknowledgement (`meshmore-sos-spec.md` §9).
  ///
  /// A direct message's packet was authenticated by the sender's key, so a key
  /// this alarm was addressed to stops it. A channel ACK is a display name in
  /// decrypted text: six hex characters are 24 bits and guessable, so the key
  /// is the load-bearing part and a channel ACK never stops the alarm.
  SosAckOutcome recordAck(
    SosAckMessage ack, {
    required bool direct,
    List<int>? fromKey,
  }) {
    final SosRaise? r = _raise;
    if (r == null || ack.id != r.id) return SosAckOutcome.ignored;
    if (_state != SosState.active) return SosAckOutcome.ignored;

    if (!direct) {
      // Deduplicated by name on a channel: there is no key to dedupe by.
      final String claimedKey = 'claimed:${ack.callsign}';
      _acks.putIfAbsent(claimedKey, () => const <int>[]);
      return SosAckOutcome.claimed;
    }
    final List<int> key = fromKey ?? const <int>[];
    final String keyId = key.join(':');
    if (_acks.containsKey(keyId)) return SosAckOutcome.duplicate;
    _acks[keyId] = key;
    final bool addressed =
        r.targets.contactKeys.any((List<int> k) => _sameKey(k, key));
    if (!addressed) return SosAckOutcome.countedNotAddressed;

    _state = SosState.acknowledged;
    return SosAckOutcome.stopped;
  }

  /// Forces the clock forward to the hard stop; used by the expiry test and by
  /// a relaunch after the hour passed.
  void expireIfDue() {
    final SosRaise? r = _raise;
    if (r == null || _state != SosState.active) return;
    if (!_clock().isBefore(SosSchedule.hardStopAt(r.raisedAt))) {
      _state = SosState.expired;
    }
  }

  static String _keyOf(SosPacket p) => '${p.kind.name}#${p.index}';

  static bool _fixIsUsable(DateTime? fixAt, DateTime now) {
    if (fixAt == null) return false;
    final Duration age = now.difference(fixAt);
    if (age.isNegative) return false;
    return age <= const Duration(hours: 1);
  }

  static bool _sameKey(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
