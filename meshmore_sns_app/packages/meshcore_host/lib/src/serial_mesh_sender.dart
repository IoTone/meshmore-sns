// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';

import 'companion_link.dart';

/// A [MeshSender] over a USB-serial companion radio.
///
/// This is the host-side twin of the app's `MeshcoreMeshSender`: same
/// contract, same L1 codec, different transport. It adds one thing the BLE
/// adapter did not need, because serial introduces it: an explicit
/// serialisation queue. The firmware has no correlation tag for `OK`/`ERR`
/// on a raw-data send (`MyMesh.cpp` writes a bare `writeOKFrame`), so two
/// sends in flight cannot be told apart. Everything that expects a reply
/// runs one at a time.
/// How a record is addressed.
enum PathMode {
  /// Use the bound route while it keeps answering, and reset it when it does not.
  auto,

  /// Never use a route. Every record floods.
  ///
  /// This is not a throwback: MeshCore learns a route only from traffic that *arrived along it*,
  /// so two ends that both flood never teach each other a route, and a route learned once can go
  /// stale with nothing to correct it - the radio answers every send `OK` and delivers it nowhere.
  /// On a private two-radio link flood is the honest setting; on a shared mesh it costs every
  /// repeater a transmission, which is why `auto` is the default.
  flood,
}

class SerialMeshSender implements MeshSender {
  SerialMeshSender({
    required CompanionLink link,
    // A record that is never answered must not hold the queue for twenty seconds: the
    // firmware answers a raw send as soon as `sendDirect` returns, so a reply that has not
    // arrived in a few seconds is lost, not slow. Measured on the device: a five-record screen
    // took six seconds to leave because each record waited out a long, silent timeout.
    this.linkTimeout = const Duration(seconds: 3),
    // How long a learned path stays worth trying. The radio's contact table holds the route a
    // peer *was* reachable by; nothing expires it, and nothing reports when it goes stale.
    this.pathMode = PathMode.auto,
    this.pathTrust = const Duration(seconds: 10),
    DateTime Function()? clock,
  })  : _link = link,
        _clock = clock ?? DateTime.now;

  /// How long a path learned from the radio stays worth trying. See [_pathForSend].
  final Duration pathTrust;

  /// How records are addressed. See [PathMode].
  final PathMode pathMode;

  /// Has this radio stopped hearing the air altogether?
  ///
  /// `true` when no packet of any kind has arrived since [since]. Only the USB side is known to
  /// work then, and a reboot is the one cure that does not need someone to walk over and unplug
  /// it.
  bool radioLooksDeaf(DateTime since, {Duration deafAfter = const Duration(minutes: 2)}) {
    final DateTime? heard = _heardAirAt;
    if (heard != null && _clock().difference(heard) < deafAfter) return false;
    // Give a freshly opened port its minute before judging it: the radio answers USB immediately
    // and only then starts listening.
    return _clock().difference(since) >= deafAfter;
  }

  /// Ask the radio to reboot. There is no reply: the link drops and the device re-enumerates.
  Future<void> rebootRadio() => _link.sendCommand(MeshcoreFrameCodec.reboot());

  /// How many records must go unanswered before the radio is told to forget the route. The
  /// session's own window is eight, so three is well inside one window: a working chain answers
  /// the first record, and nothing is reset on a link that is merely busy.
  static const int SUSPECT_SENDS = 3;

  /// How many records a fresh link sends by flood. One ARQ window: enough for `msg2`, `msg3` and
  /// the attach reply, after which both radios have heard each other on a real path.
  static const int WARMUP_SENDS = 8;

  /// See [pathTrust]. Injected so a test can age a path without sleeping.
  final DateTime Function() _clock;

  final CompanionLink _link;

  /// How long to wait for the reply the firmware promises to send.
  /// Raw data is answered immediately after `sendDirect` returns, so this
  /// is a link-failure deadline, not an airtime estimate.
  final Duration linkTimeout;

  final StreamController<Uint8List> _inbound =
      StreamController<Uint8List>.broadcast();
  final StreamController<RadioState> _radioStates =
      StreamController<RadioState>.broadcast();
  final Map<String, Contact> _contacts = <String, Contact>{};

  StreamSubscription<MeshcoreInbound>? _sub;
  StreamSubscription<MeshcoreConnectionState>? _stateSub;

  Completer<void>? _awaitingContacts;
  Completer<bool>? _awaitingReply;
  Uint8List? _boundPath;
  Uint8List? _boundKey;

  /// When this radio last heard *anything* from the peer. A path is a claim about the mesh at
  /// the moment it was learned, and only that moment.
  DateTime? _heardPeerAt;

  /// Records sent since the peer was last heard. Their count is the evidence that a path has
  /// stopped working: the peer acknowledges every record, so sending several without hearing a
  /// thing back means the chain is not delivering.
  int _sentSinceHeard = 0;

  /// When the radio last heard *any* frame off the air, as opposed to a USB reply.
  ///
  /// The distinction matters because the two failures look nothing alike from here and have
  /// different cures: a radio whose USB side is fine but whose receiver has stopped (measured
  /// 2026-10-31: 350 contact pushes over USB, one air packet in twenty-five minutes, `rssi -128`
  /// throughout) needs a reboot, while a radio that hears other nodes but not the peer needs a
  /// path reset. Nothing else in the daemon can tell those apart, and the symptom - "the host
  /// stopped answering" - is identical.
  DateTime? _heardAirAt;

  /// Records still to be sent by flood at the start of a link.
  ///
  /// Hearing the peer is not proof that the *reverse* chain works, and a flooded packet teaches
  /// the radio no route at all: a peer whose traffic arrives with an empty path leaves the stored
  /// path exactly as stale as it was. That is how a handshake could be accepted eight times while
  /// the phone received none of the answers - the host heard every `msg1` and kept sending `msg2`
  /// down the same dead chain. The first window of every bind therefore floods, which costs a few
  /// records once and lets both ends learn a route from traffic that provably arrived.
  int _floodWarmup = WARMUP_SENDS;
  int _uplinkMax = GatewayLimits.recordFloor;
  int _lastRssi = GatewayLimits.unknownRssi;

  Future<void> _tail = Future<void>.value();
  bool _started = false;

  // -------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------

  /// Subscribe to the link. Called once, after the link is ready.
  void start() {
    if (_started) return;
    _started = true;
    _sub = _link.inbound.listen(_onInbound);
    _stateSub = _link.states.listen((MeshcoreConnectionState s) {
      _emitRadioState(_mapState(s));
      if (s != MeshcoreConnectionState.ready) {
        // A dropped link loses the bound path's validity: the radio may have
        // a new contact table after a reboot. Keep the key, drop the path so
        // the next bind re-resolves it rather than sending into a stale hop
        // chain.
        _boundPath = null;
        _uplinkMax = GatewayLimits.recordFloor;
        _floodWarmup = WARMUP_SENDS;
      }
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _stateSub?.cancel();
    _completeReply(false);
    _awaitingContacts?.complete();
    _awaitingContacts = null;
    await _inbound.close();
    await _radioStates.close();
  }

  // -------------------------------------------------------------------
  // MeshSender
  // -------------------------------------------------------------------

  @override
  int get uplinkRecordMax => _uplinkMax;

  @override
  int get airtimeOverheadBytes => 2 + (_boundPath?.length ?? 0);

  @override
  Future<bool> isContact(List<int> pubKey) {
    return _serialise(() async {
      final String key = meshKeyHex(pubKey);
      if (_contacts.containsKey(key)) return true;
      await _syncContactsLocked();
      return _contacts.containsKey(key);
    });
  }

  @override
  Future<BindError?> bindPeer(Uint8List pubKey) {
    return _serialise(() async {
      final String key = meshKeyHex(pubKey);
      Contact? contact = _contacts[key];
      if (contact == null) {
        await _syncContactsLocked();
        contact = _contacts[key];
      }
      if (contact == null) return BindError.notAContact;

      // A zero-hop path is a neighbour, not a missing route; `directPath`
      // keeps that distinction (and is the same rule the app binds with).
      final Uint8List? path = contact.directPath;
      if (path == null) return BindError.noPath;

      final int capacity = MeshCarryLimits.rawDataPayloadMax(path.length);
      if (capacity < GatewayLimits.recordFloor) return BindError.noPath;

      _boundPath = path;
      _boundKey = Uint8List.fromList(pubKey);
      _floodWarmup = WARMUP_SENDS;
      _uplinkMax = capacity > GatewayLimits.recordMax
          ? GatewayLimits.recordMax
          : capacity;
      _emitRadioState(radioState);
      // The radio was told to send to this peer, so its last-RSSI reading is
      // the one worth showing. Best effort: a missing stats reply must not
      // fail a bind that already has a valid path.
      unawaited(pollStats());
      return null;
    });
  }

  @override
  Future<SendOutcome> sendRecord(Uint8List record, {required int seq}) {
    return _serialise(() async {
      if (_boundPath == null) return SendOutcome.errNotFound;
      // **Ask the radio to forget the route when the route has stopped answering.** Sends along a
      // learned chain are answered `OK` by the firmware whether or not the chain still exists, so
      // the radio itself never learns that a hop went away: it keeps using the dead path for ever.
      // `CMD_RESET_PATH` is the documented cure - the next send floods, and the flood's own reply
      // teaches the radio a fresh route. Done before the record is framed, because the point is
      // for *this* record to go out over flood.
      if (_pathIsSuspect()) {
        await _link.sendCommand(MeshcoreFrameCodec.resetPath(_boundKey!));
        _sentSinceHeard = 0;
      }
      final Uint8List path = _pathForSend();
      _sentSinceHeard++;
      if (record.length > _uplinkMax) return SendOutcome.errTooLong;

      final Uint8List frame;
      try {
        frame = MeshCarryCodec.sendRawData(path: path, payload: record);
      } on MeshCarryLengthError {
        return SendOutcome.errTooLong;
      } on ArgumentError {
        return SendOutcome.errTooLong;
      }

      _awaitingReply = Completer<bool>();
      try {
        await _link.sendCommand(frame);
      } catch (_) {
        _completeReply(false);
        // The link refused the write. Attributable to this seq, so report it
        // here rather than dropping the connection silently.
        return SendOutcome.errBusy;
      }

      final bool ok;
      try {
        ok = await _awaitingReply!.future.timeout(linkTimeout);
      } on TimeoutException {
        _awaitingReply = null;
        return SendOutcome.localTimeout;
      }
      _awaitingReply = null;
      return ok ? SendOutcome.sentDirect : _lastErrorOutcome;
    });
  }

  @override
  Stream<Uint8List> get inbound => _inbound.stream;

  @override
  RadioState get radioState => _mapState(_link.state);

  @override
  Stream<RadioState> get radioStateChanges => _radioStates.stream;

  @override
  int get rssiDbm => _lastRssi;

  @override
  int get batteryPercent => GatewayLimits.unknownBattery;

  // -------------------------------------------------------------------
  // Diagnostics the host binary exposes
  // -------------------------------------------------------------------

  /// The self info the handshake captured (name, key, radio parameters).
  SelfInfo? get selfInfo => _link.selfInfo;

  /// The peer currently bound, if any.
  Uint8List? get boundPeer => _boundKey;

  /// How many contacts the cached table holds.
  int get contactCount => _contacts.length;

  /// The contact named [name], syncing the table when it is not cached.
  ///
  /// Names are what a radio and its owner actually use, and a human typing one is
  /// not making a cryptographic claim: this is a lookup, not a trust decision. The
  /// key it returns is the key the radio itself holds, which is the only answer
  /// that will route. Match is case-insensitive and trimmed; the first exact match
  /// wins, and a duplicate name is not resolved by guessing.
  Future<Contact?> contactByName(String name) {
    return _serialise(() async {
      final String want = name.trim().toLowerCase();
      if (want.isEmpty) return null;
      Contact? find() {
        for (final Contact c in _contacts.values) {
          if (c.name.trim().toLowerCase() == want) return c;
        }
        return null;
      }

      final Contact? cached = find();
      if (cached != null) return cached;
      await _syncContactsLocked();
      return find();
    });
  }

  /// Every contact name currently cached, for an error that can say what exists.
  List<String> get contactNames => <String>[
        for (final Contact c in _contacts.values)
          if (c.name.trim().isNotEmpty) c.name,
      ]..sort();

  /// The cached contact table, keyed by public-key hex. Read-only: the radio is
  /// the authority for what is in it (`isContact` re-syncs on a miss).
  ///
  /// Exists so an operator can answer "which key is this node?" without a second
  /// tool or a phone in hand. The host gateway logs the peer's name from here
  /// when it binds.
  Map<String, Contact> get contacts => Map<String, Contact>.unmodifiable(_contacts);

  /// Ask the radio for its counters and cache its last RSSI.
  ///
  /// Called on bind, and by the host binary on a timer. Failures are
  /// swallowed: a missing reading is reported as [GatewayLimits.unknownRssi],
  /// which clients are required to render as "no reading", never as 0.
  Future<void> pollStats() {
    return _serialise(() async {
      try {
        await _link
            .sendCommand(MeshcoreFrameCodec.getStats(kStatsTypeRadio));
      } catch (_) {
        return;
      }
    });
  }

  /// Reload the whole contact table. Public because the host binary may want
  /// to refresh after adding a contact in MeshMore on another device.
  Future<void> syncContacts() => _serialise(_syncContactsLocked);

  // -------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------

  SendOutcome _lastErrorOutcome = SendOutcome.errBusy;

  /// The path to put on the next record: the bound hop chain when it is worth trusting, and an
  /// empty one (flood) when it is not.
  ///
  /// **Direct is a promise the mesh has to keep, and the radio cannot tell us when it stops.**
  /// A record sent along a stale chain is answered `OK` by the firmware the moment `sendDirect`
  /// returns, so the gateway reports `sentDirect`, the airtime is spent, and nothing arrives.
  /// The only evidence that a chain is still real is hearing the peer travel it, and that
  /// evidence decays: a repeater moved, a node rebooted, a neighbour's table was rewritten.
  ///
  /// Flood costs every repeater a transmission, so it is not the default - but it is the honest
  /// choice when the path is unproven, and one flooded record buys back the proof. In the steady
  /// state the peer's own records arrive every few seconds, so [pathTrust] is satisfied and
  /// direct is used as before.
  /// Has the bound chain gone quiet after we leaned on it?
  ///
  /// One silent send proves nothing (the radio may be busy), and the clock alone cannot decide:
  /// a session that is idle sends nothing, so silence is harmless. What is not harmless is
  /// sending again and again and hearing nothing back, which is what a dead hop chain looks like
  /// from here.
  bool _pathIsSuspect() {
    if (pathMode == PathMode.flood) return false;
    final DateTime? heard = _heardPeerAt;
    // The warm-up is already flood, so there is nothing to reset on top of it.
    if (_floodWarmup > 0) return false;
    if (_boundPath == null || _sentSinceHeard < SUSPECT_SENDS) return false;
    if (heard != null && _clock().difference(heard) <= pathTrust) return false;
    return true;
  }

  Uint8List _pathForSend() {
    final Uint8List? path = _boundPath;
    if (path == null || pathMode == PathMode.flood) return Uint8List(0);
    if (_floodWarmup > 0) {
      _floodWarmup--;
      return Uint8List(0);
    }
    final DateTime? heard = _heardPeerAt;
    if (heard == null) return Uint8List(0);
    return _clock().difference(heard) > pathTrust ? Uint8List(0) : path;
  }

  void _onInbound(MeshcoreInbound frame) {
    switch (frame) {
      case RawDataFrame():
        // Only a record from the peer proves the chain is real; an advert or a neighbour's
        // traffic says nothing about these hops. Hearing it also clears the suspicion, whatever
        // the radio is doing with its stored route.
        _heardPeerAt = _clock();
        _heardAirAt = _clock();
        _sentSinceHeard = 0;
        if (!_inbound.isClosed) _inbound.add(frame.payload);
      case ContactFrame(contact: final Contact c):
        _contacts[meshKeyHex(c.publicKey)] = c;
      case NewAdvertFrame(contact: final Contact c):
        // An advert means the receiver works, whoever it came from.
        _heardAirAt = _clock();
        _contacts[meshKeyHex(c.publicKey)] = c;
      case ContactDeletedFrame(publicKey: final Uint8List key):
        _contacts.remove(meshKeyHex(key));
      case EndOfContactsFrame():
        _awaitingContacts?.complete();
      case OkFrame():
        _completeReply(true);
      case ErrorFrame(code: final int? code):
        _lastErrorOutcome = _outcomeForError(code);
        _completeReply(false);
      case StatsFrame(radio: final RadioStats? radio):
        if (radio != null) _lastRssi = radio.lastRssi;
      default:
        break;
    }
  }

  void _completeReply(bool ok) {
    final Completer<bool>? waiting = _awaitingReply;
    if (waiting != null && !waiting.isCompleted) waiting.complete(ok);
  }

  /// Raw data is answered with `OK` or `ERR`. Only `not_found` has a distinct
  /// meaning at this layer ("the radio holds no path to that peer"). Table
  /// full means the radio is momentarily out of packet slots. Every other
  /// code collapses to `errBusy`, which is the honest statement that this
  /// layer cannot attribute it further (recorded in the audit as an open
  /// limitation, not an oversight).
  static SendOutcome _outcomeForError(int? code) {
    // Extension-type getters are not const, so this cannot be a switch
    // pattern over `.code`.
    if (code == MeshcoreErrorCode.notFound.code ||
        code == MeshcoreErrorCode.unsupportedCmd.code) {
      return SendOutcome.errNotFound;
    }
    return SendOutcome.errBusy;
  }

  Future<void> _syncContactsLocked() async {
    if (_link.state != MeshcoreConnectionState.ready) {
      return;
    }
    _awaitingContacts = Completer<void>();
    try {
      await _link.sendCommand(MeshcoreFrameCodec.getContacts());
    } catch (_) {
      _awaitingContacts = null;
      return;
    }
    try {
      await _awaitingContacts!.future.timeout(linkTimeout);
    } on TimeoutException {
      // Partial lists are still useful: keep whatever arrived.
    } finally {
      _awaitingContacts = null;
    }
  }

  RadioState _mapState(MeshcoreConnectionState s) {
    switch (s) {
      case MeshcoreConnectionState.ready:
        return _boundPath == null ? RadioState.noContact : RadioState.connected;
      case MeshcoreConnectionState.reconnecting:
        return RadioState.radioLost;
      case MeshcoreConnectionState.failed:
      case MeshcoreConnectionState.disconnected:
      case MeshcoreConnectionState.handshaking:
        return RadioState.disconnected;
    }
  }

  void _emitRadioState(RadioState state) {
    if (!_radioStates.isClosed) _radioStates.add(state);
  }

  /// Runs [action] after every previously queued action. One outstanding
  /// request at a time is a protocol requirement here, not a simplification.
  Future<T> _serialise<T>(Future<T> Function() action) {
    final Future<void> previous = _tail;
    final Completer<void> done = Completer<void>();
    _tail = done.future;
    // One queue for everything that talks to the radio, which is what makes the reply-to-command
    // pairing safe on a firmware with no correlation tag. The cost is that a slow operation holds
    // every later one, so the wait is worth being able to see: `MESHMORE_GATEWAY_DEBUG=1` prints
    // how long each action spent waiting for the queue and how long it then took.
    final bool trace = Platform.environment['MESHMORE_GATEWAY_DEBUG'] == '1';
    final Stopwatch queued = Stopwatch()..start();
    return previous.then((_) {
      if (!trace) return action();
      final int waited = queued.elapsedMilliseconds;
      final Stopwatch ran = Stopwatch()..start();
      return action().whenComplete(() {
        stdout.writeln('gateway: serialised wait=${waited}ms ran=${ran.elapsedMilliseconds}ms');
      });
    }).whenComplete(done.complete);
  }
}
