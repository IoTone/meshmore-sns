// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../meshcore/chat_message.dart';
import '../meshcore/meshcore_controller.dart';
import 'checkin.dart';
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

  /// The channel slot the alarm goes out on, and the one the screen names.
  int _channelSlot = 0;

  /// Direct-message copies, as full 64-hex keys. Empty means channel-only,
  /// which also means no ACK can ever stop the alarm — the screen says so.
  List<String> _contactKeysHex = const <String>[];

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

  void start() {
    _channelSlot = emergencyChannelSlot ?? _mc.activeChannel;
    _channelSub ??= _mc.incomingChannelMessages.listen(_onChannel);
    _dmSub ??= _mc.incomingDirectMessages.listen(_onDm);
  }

  /// Picks the destination. The screen offers the radio's channels; this also
  /// drops any DM copy whose key would no longer be addressable.
  void setDestination({int? channelSlot, List<String>? contactKeysHex}) {
    if (channelSlot != null) _channelSlot = channelSlot;
    if (contactKeysHex != null) {
      _contactKeysHex = <String>[
        for (final String k in contactKeysHex.take(SosTargets.maxContactTargets))
          if (k.length == 64) k.toLowerCase(),
      ];
    }
    notifyListeners();
  }

  /// Arms the alarm: `idle` → `arming`. Nothing is sent until [confirm].
  SosRefusal? arm({required String words}) {
    _lastRefusal = null;
    final DateTime now = _clock();
    final List<int>? pubkey = _mc.selfInfo?.publicKey;
    final String callsign = _mc.selfInfo?.name.trim() ?? '';
    if (pubkey == null || pubkey.isEmpty || callsign.isEmpty) {
      // Without an identity the id cannot be derived and the callsign cannot
      // travel; the engine would report it as a malformed message instead.
      _lastRefusal = SosRefusal.noIdentity;
      notifyListeners();
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
    if (_lastRefusal == null) _acks.clear();
    notifyListeners();
    return _lastRefusal;
  }

  /// Completes the three-second hold. Refused before it elapses.
  SosRefusal? confirm() {
    _lastRefusal = _engine.confirm();
    if (_lastRefusal == null) {
      _ensureTicker();
      pump();
    }
    notifyListeners();
    return _lastRefusal;
  }

  void abort() {
    _engine.abort();
    _stopTicker();
    notifyListeners();
  }

  /// The raiser's own stop. [iAmSafe] is the one that also tells the mesh.
  void cancel() {
    _engine.cancel();
    _stopTicker();
    notifyListeners();
  }

  /// "I'm safe": one `[SAFE]` on the same destinations, then nothing more.
  Future<void> iAmSafe() async {
    final ({String? text, SosMessageRefusal? refusal})? safe =
        _engine.iAmSafe();
    _stopTicker();
    notifyListeners();
    if (safe?.text == null) return;
    await _send(safe!.text!);
  }

  void dismiss() {
    _engine.dismiss();
    _stopTicker();
    notifyListeners();
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
    notifyListeners();
    return watch.state;
  }

  /// One tick: every due packet, the hard stop, and the check-in deadline.
  ///
  /// Called by the timer in the app and directly by a test with a fake clock.
  void pump() {
    final DateTime now = _clock();
    for (final SosSend s in _engine.advanceTo(now)) {
      unawaited(_send(s.text));
    }
    _checkin?.tick();
    // The ticker lives as long as *something* is being watched: an alarm that
    // is still repeating, or a check-in whose deadline has not passed.
    final bool checkinWatching = _checkin?.state == CheckinState.watching;
    if (!_engine.isRunning && !checkinWatching) _stopTicker();
    notifyListeners();
  }

  /// Puts one packet on air, on every destination the alarm carries.
  Future<void> _send(String text) async {
    try {
      await _mc.sendChannelTextTo(_channelSlot, text);
      for (final String hex in _contactKeysHex) {
        await _mc.sendDirectText(hex, text);
      }
    } catch (_) {
      // A failed send is not a failed alarm: the schedule keeps its count and
      // the next packet is still due. Nothing is claimed about delivery
      // (`meshmore-sos-spec.md` §10), so there is nothing to correct here.
    }
  }

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
      notifyListeners();
      return;
    }

    // A check-in is answered by `[SAFE:<id>]` naming its id — the same
    // message a raiser sends to call off an alarm (`meshmore-sos-spec.md` §3).
    if (parsed is SosSafeMessage) {
      final CheckinWatch? w = _checkin;
      if (w != null && parsed.id == w.checkin.id) {
        w.recordAnswer(direct: direct, fromKey: fromKey);
        notifyListeners();
      }
    }
  }

  /// Channel text is `"name: body"` (the firmware prepends the sender's
  /// name); the tag starts after that, not at the beginning of the line.
  static String _afterSenderPrefix(String text) {
    final int sep = text.indexOf(': ');
    if (sep <= 0 || sep > 32) return text;
    return text.substring(sep + 2).trim();
  }

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

  @override
  void dispose() {
    _stopTicker();
    _channelSub?.cancel();
    _dmSub?.cancel();
    super.dispose();
  }
}
