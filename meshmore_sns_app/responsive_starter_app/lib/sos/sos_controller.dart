// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../meshcore/chat_message.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/meshcore_controller.dart';
import 'checkin.dart';
import 'sos_alarm_record.dart';
import 'sos_prefs.dart';
import 'sos_engine.dart';
import 'sos_message.dart';
import 'sos_schedule.dart';

/// One acknowledgement the alarm screen shows, with the path it arrived by.
///
/// The two paths are kept apart because they mean different things
/// (`meshmore-sos-spec.md` §9): a channel ACK is a name in decrypted text and
/// stops nothing, a direct-message ACK is authenticated by the sender's key.
final class SosAckRow {
  const SosAckRow({
    required this.name,
    required this.claimed,
    required this.at,
  });

  /// The name the ACK carried: the callsign for a channel line, the peer's
  /// display name for a direct message.
  final String name;

  /// True when it arrived on a channel, i.e. it is a claim, not a proof.
  final bool claimed;

  final DateTime at;
}

/// Drives one alarm and one check-in over the live radio.
///
/// The engine decides *what* goes out and *when* (`sos_engine.dart`); this
/// class is the only place that turns that decision into frames, because it is
/// the only place that knows the radio. The wires are the controller's public
/// members and nothing else: [MeshcoreController.sendChannelTextTo],
/// [MeshcoreController.sendDirectText], the two inbound message streams and
/// [MeshcoreController.selfInfo].
///
/// It also owns the local watch the radio cannot do: a one-second tick that
/// emits due packets (so the schedule survives the screen being closed — the
/// foreground service keeps the isolate alive) and marks a check-in overdue at
/// its deadline.
final class SosController extends ChangeNotifier {
  SosController({
    required MeshcoreController mc,
    DateTime Function()? clock,
    Random? random,
    this.autoTick = true,
    this.isBlockedKey,
    this.onRunningChanged,
  })  : _mc = mc,
        _clock = clock ?? DateTime.now,
        _engine = SosEngine(clock: clock ?? DateTime.now, random: random);

  final MeshcoreController _mc;
  final DateTime Function() _clock;
  final SosEngine _engine;

  /// False in a test that moves the clock by hand: a real timer would fire on
  /// wall time and the assertions would race it.
  final bool autoTick;

  Timer? _ticker;
  StreamSubscription<ChatMessage>? _channelSub;
  StreamSubscription<ChatMessage>? _dmSub;

  final List<SosAckRow> _acks = <SosAckRow>[];
  SosRefusal? _lastRefusal;
  CheckinWatch? _checkin;

  /// Counters behind the panel's honesty: what the radio refused, and what the
  /// sleep window swallowed. Both reset when a new alarm is raised.
  int _failedSends = 0;
  int _unconfirmedSends = 0;
  int _missedSends = 0;

  /// True when this alarm came back from a snapshot rather than from a hold
  /// in this session, so the screen can say the app was closed in between.
  bool _resumed = false;
  bool get resumedFromRestart => _resumed;

  /// What became of the `[SAFE]` message: null when no stop was attempted,
  /// true when it left, false when the radio refused it or there was none.
  bool? _safeSent;
  bool? get safeSent => _safeSent;

  /// The "I'm safe" write left no answer. Kept apart from [safeSent] because
  /// "we do not know" is a different sentence from "it did not go".
  bool _safeUnconfirmed = false;
  bool get safeUnconfirmed => _safeUnconfirmed;

  /// A blocked key's copy or claim must not appear here either: the block
  /// spec's rule is that every surface hides it, and the alarm is one.
  bool Function(String keyHex)? isBlockedKey;

  /// Told when the schedule starts and stops, so the app can carry one sign of
  /// a running alarm outside this screen.
  void Function(bool running)? onRunningChanged;
  bool _wasRunning = false;

  /// The channel slot the alarm goes out on, and the one the screen names.
  int _channelSlot = 0;

  /// Direct-message copies, as full 64-hex keys. Empty means channel-only,
  /// which also means no ACK can ever stop the alarm — the screen says so.
  List<String> _contactKeysHex = const <String>[];

  /// True when a remembered destination named a channel the radio no longer
  /// lists. A named state, not a silent fallback: the alarm refuses to arm
  /// until the user picks again, because sending an alarm to a channel nobody
  /// chose is worse than asking.
  bool _destinationMissing = false;
  bool get destinationMissing => _destinationMissing;

  /// True once the destination came from the user rather than from the radio's
  /// own default, so the screen can say whose choice it is.
  bool _destinationChosen = false;
  bool get destinationChosen => _destinationChosen;

  SosState get state => _engine.state;
  SosRaise? get request => _engine.activeRequest;
  List<SosPacket> get plan => _engine.plan;
  List<SosPacket> get remaining => _engine.remaining;
  bool get isRunning => _engine.isRunning;

  /// Why the last arm/confirm was refused, for the screen to translate.
  SosRefusal? get lastRefusal => _lastRefusal;

  /// Every acknowledgement shown on the alarm, oldest first.
  List<SosAckRow> get acks => List<SosAckRow>.unmodifiable(_acks);

  /// The claim that stopped the alarm, or null while it is still running.
  SosAckRow? get stoppedBy => state == SosState.acknowledged && _acks.isNotEmpty
      ? _acks.lastWhere((SosAckRow r) => !r.claimed, orElse: () => _acks.last)
      : null;

  int get channelSlot => _channelSlot;
  String get channelName {
    for (final MapEntry<int, String> e in _mc.channels) {
      if (e.key == _channelSlot) return e.value;
    }
    return '#$_channelSlot';
  }
  List<String> get contactKeysHex => List<String>.unmodifiable(_contactKeysHex);

  CheckinWatch? get checkin => _checkin;

  /// How long until the next packet is due, or null when nothing is left.
  Duration? get untilNextSend {
    final List<SosPacket> left = _engine.remaining;
    if (left.isEmpty) return null;
    final Duration d = left.first.dueAt.difference(_clock());
    return d.isNegative ? Duration.zero : d;
  }

  /// How long the alarm has been running, from its raise.
  Duration get elapsed {
    final SosRaise? r = _engine.activeRequest;
    return r == null ? Duration.zero : _clock().difference(r.raisedAt);
  }

  /// The slot the emergency channel lives in, when the radio lists one.
  ///
  /// APP-H5: reach is the point of an alarm, so `#emergency` is the default
  /// destination when the radio has it. Nothing is created here — if the
  /// radio has no such channel the active one is the destination and the
  /// screen offers no silent add.
  int? get emergencyChannelSlot {
    for (final MapEntry<int, String> e in _mc.channels) {
      final String n = e.value.replaceFirst('#', '').toLowerCase();
      if (n == 'emergency') return e.key;
    }
    return null;
  }

  bool get canArm => _mc.isReady && _mc.selfInfo != null;

  /// Message ids this alarm has written, and whether each has been counted.
  ///
  /// A radio answers ERR a moment after the frame leaves, so a refusal is not
  /// knowable at the call site. The controller mutates the row it returned,
  /// and this watch turns that mutation into the panel's three states.
  final Map<String, bool> _watched = <String, bool>{};
  bool _mcHasListener = false;

  void _watch(ChatMessage? m) {
    if (m == null) return;
    _watched[m.id] = false;
  }

  void _classifyWatched() {
    if (_watched.isEmpty) return;
    bool changed = false;
    for (final String id in _watched.keys.toList()) {
      ChatMessage? row;
      for (final ChatMessage m in _mc.messagesFor(_channelSlot)) {
        if (m.id == id) {
          row = m;
          break;
        }
      }
      if (row == null) continue;
      final MessageDelivery? d = row.delivery;
      if (d == MessageDelivery.failed) {
        if (_watched[id] != true) {
          _watched[id] = true;
          _failedSends++;
          _unconfirmedSends = 0;
          if (_safeSent == true) _safeSent = false;
          changed = true;
        }
      } else if (d == MessageDelivery.unknown) {
        if (_watched[id] != true) {
          _watched[id] = true;
          _unconfirmedSends++;
          if (_safeSent == true) {
            _safeSent = null;
            _safeUnconfirmed = true;
          }
          changed = true;
        }
      } else if (d == MessageDelivery.sent ||
          d == MessageDelivery.delivered) {
        _watched.remove(id);
      }
    }
    if (changed) _notify();
  }

  void start() {
    // The initial default is not a fallback: with nothing remembered, the
    // emergency channel is the destination when the radio lists it, and the
    // active channel otherwise (`meshmore-sos-spec.md` §6).
    _channelSlot = emergencyChannelSlot ?? _mc.activeChannel;
    _channelSub ??= _mc.incomingChannelMessages.listen(_onChannel);
    _dmSub ??= _mc.incomingDirectMessages.listen(_onDm);
    if (!_mcHasListener) {
      _mc.addListener(_classifyWatched);
      _mcHasListener = true;
    }
    unawaited(_restoreDestination());
    unawaited(_restoreAlarm());
  }

  /// Rebuilds an alarm that was running when the process died.
  ///
  /// The engine's rule is the spec's (§13.10): packets already on air are not
  /// replayed, what is left of the hour goes out with fresh sends, and an hour
  /// that elapsed while the app was dead opens on `expired` rather than
  /// pretending. A record that cannot be read is cleared, not retried.
  Future<void> _restoreAlarm() async {
    final Map<String, Object?>? json = await SosPrefs.alarm();
    if (json == null) return;
    final SosSnapshot? snap = alarmFromJson(json);
    if (snap == null) {
      await SosPrefs.saveAlarm(null);
      return;
    }
    final SosRaise r = snap.raise;
    final int? slot = int.tryParse(r.targets.channelId ?? '');
    if (slot != null) _channelSlot = slot;
    final List<String> keys = <String>[
      for (final List<int> k in r.targets.contactKeys) hexOfKey(k),
    ];
    if (keys.isNotEmpty) {
      _contactKeysHex = keys;
      _destinationChosen = true;
    }
    _engine.restore(snap);
    _resumed = _engine.state == SosState.active;
    _notify();
    if (_engine.isRunning) {
      _ensureTicker();
      // Reconciles with the wall clock immediately: if the hour has run out
      // this moves the alarm to `expired` without sending anything.
      pump();
    }
  }

  /// Writes the current alarm, or clears the record once nothing is running.
  ///
  /// The schedule ticks once a second, and a write per tick would be 3,600
  /// preference writes over an alarm for no new information: the record only
  /// changes when the state does or when another packet has gone out. So the
  /// write is keyed on exactly that.
  void _persistAlarm() {
    final SosSnapshot? snap = _engine.snapshot();
    if (snap == null) {
      if (_persistedSignature == null) return;
      _persistedSignature = null;
      unawaited(SosPrefs.saveAlarm(null));
      return;
    }
    final String signature = '${snap.state.name}|${snap.issued.length}';
    if (signature == _persistedSignature) return;
    _persistedSignature = signature;
    unawaited(SosPrefs.saveAlarm(alarmToJson(snap)));
  }

  /// What the last write recorded, so an unchanged alarm is not rewritten.
  String? _persistedSignature;

  /// Applies a remembered destination once preferences answer. A test that
  /// never saved one keeps the radio's default, because the load is a no-op.
  Future<void> _restoreDestination() async {
    final int? slot = await SosPrefs.channelSlot();
    if (slot == null) return;
    final List<String> targets =
        await SosPrefs.contactTargets() ?? const <String>[];
    _channelSlot = slot;
    _contactKeysHex = <String>[
      for (final String k in targets)
        if (k.length == 64) k.toLowerCase(),
    ];
    _destinationChosen = true;
    _destinationMissing = !_hasChannel(slot);
    _notify();
  }

  /// Picks the destination. The screen offers the radio's channels; this also
  /// drops any DM copy whose key would no longer be addressable.
  void setDestination({int? channelSlot, List<String>? contactKeysHex}) {
    if (channelSlot != null) {
      _channelSlot = channelSlot;
      _destinationMissing = false;
    }
    if (contactKeysHex != null) {
      _contactKeysHex = <String>[
        for (final String k in contactKeysHex.take(SosTargets.maxContactTargets))
          if (k.length == 64) k.toLowerCase(),
      ];
    }
    _destinationChosen = true;
    _destinationMissing = _destinationMissing || !_hasChannel(_channelSlot);
    unawaited(SosPrefs.save(
      channelSlot: _channelSlot,
      contactTargets: _contactKeysHex,
    ));
    _notify();
  }

  /// Whether the radio lists [slot]. `channels` is the sorted view, not the map.
  bool _hasChannel(int slot) => _mc.channels.any((MapEntry<int, String> e) => e.key == slot);

  /// The direct copies, each with the name the radio knows, or null when the
  /// key is no longer in the contact list. The picker needs both halves: a
  /// key with no name is a destination the user cannot recognise.
  List<({String keyHex, String? name})> get contactTargets {
    final Map<String, String> names = <String, String>{
      for (final DiscoveredNode n in _mc.nodes) n.pubKeyHex.toLowerCase(): n.name,
    };
    final bool Function(String keyHex)? blocked = isBlockedKey;
    return <({String keyHex, String? name})>[
      for (final String hex in _contactKeysHex)
        if (blocked == null || !blocked(hex)) (keyHex: hex, name: names[hex]),
    ];
  }

  /// Arms the alarm: `idle` → `arming`. Nothing is sent until [confirm].
  SosRefusal? arm({required String words}) {
    _lastRefusal = null;
    if (_destinationMissing) {
      // The remembered channel is gone. Refusing here is what makes the state
      // visible: the screen names the channel and offers the picker instead of
      // quietly sending the alarm somewhere else.
      _lastRefusal = SosRefusal.noDestination;
      _notify();
      return _lastRefusal;
    }
    final DateTime now = _clock();
    final List<int>? pubkey = _mc.selfInfo?.publicKey;
    final String callsign = _mc.selfInfo?.name.trim() ?? '';
    if (pubkey == null || pubkey.isEmpty || callsign.isEmpty) {
      // Without an identity the id cannot be derived and the callsign cannot
      // travel; the engine would report it as a malformed message instead.
      _lastRefusal = SosRefusal.noIdentity;
      _notify();
      return _lastRefusal;
    }

    final List<int> nonce = _nonce();
    final double? lat = _mc.ownLocation?.latitude;
    final double? lon = _mc.ownLocation?.longitude;
    final SosRaise raise = SosRaise(
      id: sosIdFor(nonce: nonce, pubkey: pubkey),
      nonce: nonce,
      raisedAt: now,
      callsign: callsign,
      words: words.trim(),
      targets: SosTargets(
        channelId: '$_channelSlot',
        contactKeys: <List<int>>[
          for (final String hex in _contactKeysHex) _bytesOf(hex),
        ],
      ),
      lat: lat,
      lon: lon,
      // The radio reports its own live position in SELF_INFO; it carries no
      // timestamp for it. Treating the position the radio reports *now* as
      // the fix means a radio with no fix (0,0, which `ownLocation` already
      // treats as unset) sends NOFIX and nothing else does.
      fixAt: lat == null || lon == null ? null : now,
    );
    _lastRefusal = _engine.raise(raise);
    if (_lastRefusal == null) {
      _acks.clear();
      _resumed = false;
      _safeSent = null;
    }
    _persistAlarm();
    _notify();
    return _lastRefusal;
  }

  /// Completes the three-second hold. Refused before it elapses.
  SosRefusal? confirm() {
    _lastRefusal = _engine.confirm();
    if (_lastRefusal == null) {
      _failedSends = 0;
      _missedSends = 0;
      _ensureTicker();
      pump();
    }
    _persistAlarm();
    _notify();
    return _lastRefusal;
  }

  void abort() {
    _engine.abort();
    _stopTicker();
    _persistAlarm();
    _notify();
  }

  /// The raiser's own stop. [iAmSafe] is the one that also tells the mesh.
  void cancel() {
    _engine.cancel();
    _stopTicker();
    _persistAlarm();
    _notify();
  }

  /// "I'm safe": one `[SAFE]` on the same destinations, then nothing more.
  Future<void> iAmSafe() async {
    final ({String? text, SosMessageRefusal? refusal})? safe =
        _engine.iAmSafe();
    _stopTicker();
    _notify();
    if (safe?.text == null) {
      // Nothing was built, so nothing left: the panel must not read as though
      // the mesh was told (safety audit SOS-3).
      _safeSent = false;
      _safeUnconfirmed = false;
      _persistAlarm();
      _notify();
      return;
    }
    switch (await _send(safe!.text!)) {
      case _SendOutcome.sent:
        // The write was accepted. A refusal can still arrive a moment later
        // and the watcher may already have counted it, so only a clean count
        // lets this read as sent.
        if (!_watched.values.any((bool counted) => counted) &&
            !_safeUnconfirmed) {
          _safeSent = true;
        }
      case _SendOutcome.refused:
        _safeSent = false;
      case _SendOutcome.unconfirmed:
        _safeSent = null;
        _safeUnconfirmed = true;
    }
    _persistAlarm();
    _notify();
  }

  void dismiss() {
    _engine.dismiss();
    _stopTicker();
    // The alarm is over and the record goes with it: a dismissed alarm must
    // not come back as a ghost on the next launch.
    unawaited(SosPrefs.saveAlarm(null));
    _notify();
  }

  /// Sends exactly one check-in and starts watching its deadline (D8.5: the
  /// intervals are 15, 30 and 60 minutes, chosen by the user).
  Future<CheckinState> sendCheckin({required Duration within}) async {
    final DateTime now = _clock();
    final List<int>? pubkey = _mc.selfInfo?.publicKey;
    final String callsign = _mc.selfInfo?.name.trim() ?? '';
    if (pubkey == null || pubkey.isEmpty || callsign.isEmpty) {
      return CheckinState.pending;
    }
    final List<int> nonce = _nonce();
    final double? lat = _mc.ownLocation?.latitude;
    final double? lon = _mc.ownLocation?.longitude;
    final Checkin row = Checkin(
      id: sosIdFor(nonce: nonce, pubkey: pubkey),
      nonce: nonce,
      callsign: callsign,
      raisedAt: now,
      until: now.add(within),
      lat: lat,
      lon: lon,
      fixAt: lat == null || lon == null ? null : now,
    );
    final CheckinWatch watch = CheckinWatch(checkin: row, clock: _clock);
    final ({String? text, SosMessageRefusal? refusal}) built = watch.text();
    if (built.text == null) return CheckinState.pending;
    await _send(built.text!);
    watch.markSent();
    _checkin = watch;
    _ensureTicker();
    _notify();
    return watch.state;
  }

  /// One packet per tick, never a catch-up burst.
  ///
  /// Called by the timer in the app and directly by a test with a fake clock.
  /// When the isolate was asleep the engine can have several packets due at
  /// once; firing them back to back fills the radio's packet table and loses
  /// all of them, and each one carries a position the user has since walked
  /// away from. The most recent due packet goes out, the rest are counted as
  /// missed and shown, so the panel never claims sends that did not happen.
  void pump() {
    final DateTime now = _clock();
    final List<SosSend> due = _engine.advanceTo(now);
    if (due.length > 1) {
      _missedSends += due.length - 1;
    }
    if (due.isNotEmpty) unawaited(_send(due.last.text));
    _checkin?.tick();
    // The ticker lives as long as *something* is being watched: an alarm that
    // is still repeating, or a check-in whose deadline has not passed.
    final bool checkinWatching = _checkin?.state == CheckinState.watching;
    if (!_engine.isRunning && !checkinWatching) _stopTicker();
    _persistAlarm();
    _notify();
  }

  /// Puts one packet on air, on every destination the alarm carries.
  ///
  /// Three outcomes, because the app can tell them apart and they mean
  /// different things to someone waiting for help (`meshmore-sos-spec.md`
  /// §10): the frame left, the radio refused it, or the link died and nobody
  /// knows. A refusal is evidence nobody heard this repeat. An unconfirmed
  /// write is not evidence of anything, and calling it a refusal would
  /// overstate the app's knowledge in the direction that looks worse than it
  /// is.
  Future<_SendOutcome> _send(String text) async {
    bool refused = false;
    bool unconfirmed = false;
    try {
      final ChatMessage? ch =
          await _mc.sendChannelTextTo(_channelSlot, text, urgent: true);
      _watch(ch);
      if (ch == null) {
        unconfirmed = true;
      } else if (ch.delivery == MessageDelivery.failed) {
        refused = true;
      } else if (ch.delivery == MessageDelivery.unknown) {
        unconfirmed = true;
      }
      for (final String hex in _contactKeysHex) {
        final ChatMessage? dm =
            await _mc.sendDirectText(hex, text, urgent: true);
        _watch(dm);
        if (dm == null) {
          unconfirmed = true;
        } else if (dm.delivery == MessageDelivery.failed) {
          refused = true;
        } else if (dm.delivery == MessageDelivery.unknown) {
          unconfirmed = true;
        }
      }
    } catch (_) {
      // A throw is the link going away at the worst moment: the radio may
      // already hold the frame, so this is not a refusal.
      unconfirmed = true;
    }
    if (refused) {
      _failedSends++;
      _unconfirmedSends = 0;
      _notify();
    } else if (unconfirmed) {
      _unconfirmedSends++;
      _notify();
    } else {
      _failedSends = 0;
      _unconfirmedSends = 0;
    }
    if (refused) return _SendOutcome.refused;
    if (unconfirmed) return _SendOutcome.unconfirmed;
    return _SendOutcome.sent;
  }

  /// Repeats the radio refused, since the alarm was raised.
  int get failedSends => _failedSends;

  /// Repeats whose write left no answer either way. Not a refusal, and not a
  /// send the app can vouch for.
  int get unconfirmedSends => _unconfirmedSends;

  /// Repeats that were due while the app was asleep and were not sent.
  int get missedSends => _missedSends;

  void _onChannel(ChatMessage m) {
    if (m.outgoing) return;
    attributeInbound(m.text, direct: false);
  }

  void _onDm(ChatMessage m) {
    if (m.outgoing) return;
    final String? peer = m.peerPubKeyHex;
    attributeInbound(
      m.text,
      direct: true,
      fromKey: peer == null ? null : _bytesOf(peer),
      peerName: peer,
    );
  }

  /// Reads one inbound line: an ACK for this alarm, or an answer to the
  /// check-in. Everything else is ordinary chat and is ignored.
  ///
  /// Public because it is the inbound entry point: the two stream listeners
  /// call it, and a test drives it without inventing a whole mesh frame. A
  /// channel line arrives with the firmware's `sender: ` prefix in front, so
  /// the tag is found after it rather than at byte zero.
  void attributeInbound(
    String text, {
    required bool direct,
    List<int>? fromKey,
    String? peerName,
  }) {
    // Only channel text carries the firmware's `sender: ` prefix; a direct
    // message's body is the body, so it is read as it stands.
    final SosMessage? parsed =
        parseSos(direct ? text : _afterSenderPrefix(text));
    if (parsed == null) return;

    if (parsed is SosAckMessage) {
      // A blocked key's claim is not shown: the block spec's rule is that
      // every surface hides it, and an acknowledgement on the alarm is a
      // surface.
      final bool Function(String keyHex)? blocked = isBlockedKey;
      if (direct && blocked != null && fromKey != null) {
        final String hex = hexOfKey(fromKey);
        if (blocked(hex)) return;
      }
      final SosAckOutcome outcome = _engine.recordAck(
        parsed,
        direct: direct,
        fromKey: fromKey,
      );
      if (outcome == SosAckOutcome.ignored) return;
      if (outcome == SosAckOutcome.duplicate) return;
      if (outcome == SosAckOutcome.claimed) {
        _acks.add(SosAckRow(
            name: parsed.callsign, claimed: true, at: _clock()));
      } else {
        _acks.add(SosAckRow(
            name: _nameFor(peerName) ?? parsed.callsign,
            claimed: false,
            at: _clock()));
      }
      if (!_engine.isRunning) _stopTicker();
      _notify();
      return;
    }

    // A check-in is answered by `[SAFE:<id>]` naming its id — the same
    // message a raiser sends to call off an alarm (`meshmore-sos-spec.md` §3).
    if (parsed is SosSafeMessage) {
      final CheckinWatch? w = _checkin;
      if (w != null && parsed.id == w.checkin.id) {
        w.recordAnswer(direct: direct, fromKey: fromKey);
        _notify();
      }
    }
  }

  /// Channel text is `"name: body"` (the firmware prepends the sender's
  /// name); the tag starts after that, not at the beginning of the line. The
  /// rule lives in `sos_message.dart` so the notification handler cannot
  /// spell it differently.
  static String _afterSenderPrefix(String text) => withoutSenderPrefix(text);

  /// A direct message carries the peer's key (full or a 12-hex prefix); the
  /// name behind it is the fabric's, not the message's, so it is looked up
  /// rather than trusted from the text.
  String? _nameFor(String? peerHex) {
    if (peerHex == null || peerHex.isEmpty) return null;
    for (final node in _mc.nodes) {
      if (node.pubKeyHex.toLowerCase().startsWith(peerHex.toLowerCase())) {
        return node.name.isEmpty ? null : node.name;
      }
    }
    return null;
  }

  void _ensureTicker() {
    if (!autoTick || _ticker != null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer _) => pump());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// 16 random bytes. The id is derived from this and the key, so two raises
  /// in the same minute cannot collide (`meshmore-sos-spec.md` §5).
  List<int> _nonce() {
    final Random r = Random.secure();
    return List<int>.generate(16, (_) => r.nextInt(256));
  }

  static List<int> _bytesOf(String hex) => <int>[
        for (int i = 0; i + 1 < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];

  /// Tells the screen, but never from inside a frame the framework has locked.
  ///
  /// A gesture arena can resolve while an element is being unmounted — the
  /// alarm screen's hold is exactly that case, because a released hold aborts
  /// an armed alarm — and `finalizeTree` is not a legal place to mark an
  /// ancestor dirty. The state changes immediately either way; only the
  /// notification waits for the frame to end, and one deferral is enough for
  /// however many transitions happen in that frame.
  void _notify() {
    final bool running = _engine.isRunning;
    if (running != _wasRunning) {
      _wasRunning = running;
      final void Function(bool running)? changed = onRunningChanged;
      if (changed != null) {
        // Deferred like the listener notification: a show/cancel is a platform
        // call, and mid-frame is not the place for one.
        scheduleMicrotask(() => changed(running));
      }
    }
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    final bool locked = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (!locked) {
      notifyListeners();
      return;
    }
    if (_notifyPending) return;
    _notifyPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyPending = false;
      if (_disposed) return;
      notifyListeners();
    });
  }

  bool _notifyPending = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _stopTicker();
    _channelSub?.cancel();
    _dmSub?.cancel();
    if (_mcHasListener) {
      _mc.removeListener(_classifyWatched);
      _mcHasListener = false;
    }
    super.dispose();
  }
}

/// What the alarm learned about one repeat.
enum _SendOutcome { sent, refused, unconfirmed }
