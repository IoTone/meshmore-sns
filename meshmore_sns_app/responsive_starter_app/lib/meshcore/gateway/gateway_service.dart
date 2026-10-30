// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshcore_gateway/meshcore_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../airtime_prefs.dart';
import '../meshcore_controller.dart';
import 'gateway_handoff.dart';
import 'mesh_sender_adapter.dart';
import 'secure_pairing_persistence.dart';

/// Why the gateway is not serving.
enum GatewayRunState {
  /// The user has not turned it on (the default).
  off,

  /// On, but no radio link yet.
  waitingForRadio,

  /// Listening on loopback.
  running,

  /// Could not start. See [GatewayService.error].
  failed,
}

/// Owns the loopback [Gateway]: starts it when the user has enabled it and the
/// radio is connected, stops it when either stops being true, and reports
/// failures instead of throwing them.
///
/// It never crashes the app: a taken port, a secure-storage failure or a
/// radio error ends in [GatewayRunState.failed] with a message.
class GatewayService extends ChangeNotifier {
  GatewayService(
    this._mc, {
    PairingPersistence? persistence,
    int port = GatewayServer.defaultPort,
    Future<SharedPreferences> Function()? prefs,
    GatewayHandoffPublisher? handoff,
  })  : _persistence = persistence ?? SecurePairingPersistence(),
        _handoff = handoff ?? const NoGatewayHandoff(),
        _port = port,
        _prefs = prefs ?? SharedPreferences.getInstance {
    _mc.addListener(_reconcile);
  }

  /// Not a secret: just whether the user turned the feature on.
  static const String enabledKey = 'mm.gateway.enabled.v1';

  final MeshcoreController _mc;
  final PairingPersistence _persistence;
  final int _port;
  final Future<SharedPreferences> Function() _prefs;
  final GatewayHandoffPublisher _handoff;
  GatewayOffer? _published;

  bool _enabled = false;
  AirtimePolicy _airtimePolicy = AirtimePolicyPrefs.fallback;
  bool _disposed = false;
  bool _busy = false;
  bool _again = false;
  GatewayRunState _status = GatewayRunState.off;
  String? _error;
  Gateway? _gateway;
  MeshcoreMeshSender? _sender;
  Uint8List? _token;
  String? _radioTuple;

  /// The radio tuple a failed start was attempted on. The controller
  /// notifies constantly, so without this a taken port would be retried (and
  /// the failure re-announced) on every notification. A new tuple or toggling
  /// the switch clears it.
  String? _failedTuple;
  bool _hasFailed = false;

  bool get enabled => _enabled;

  /// The airtime policy this gateway meters itself under. The policy is chosen by the
  /// operator, not negotiated: both ends meter their own transmissions.
  AirtimePolicy get airtimePolicy => _airtimePolicy;

  GatewayRunState get status => _status;

  /// A human-readable reason when [status] is [GatewayRunState.failed].
  String? get error => _error;

  /// The token to hand to the other app. Null until the gateway has started.
  Uint8List? get pairingToken => _token == null
      ? null
      : Uint8List.fromList(_token!);

  /// The port the listener is bound to, or the configured one when stopped.
  int get port => _gateway?.port ?? _port;

  /// Public key of the peer the connected app is bound to, if any.
  Uint8List? get boundPeer => _gateway?.boundPeer;

  /// The bound peer's contact name, if known.
  String? get boundPeerName {
    final Uint8List? k = boundPeer;
    if (k == null) return null;
    final String hex =
        k.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
    return _mc.contactRecordFor(hex)?.name;
  }

  /// Airtime this gateway has spent in the last hour, and its budget.
  Duration get airtimeUsed => _gateway?.governor.used ?? Duration.zero;
  Duration get airtimeBudget =>
      _gateway?.governor.budget ?? const Duration(seconds: 36);

  /// Read the persisted switch. Call once at startup.
  Future<void> load() async {
    try {
      final SharedPreferences p = await _prefs();
      _enabled = p.getBool(enabledKey) ?? false;
    } catch (_) {
      _enabled = false;
    }
    _airtimePolicy = await AirtimePolicyPrefs.policy();
    await _reconcile();
  }

  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    _hasFailed = false;
    try {
      final SharedPreferences p = await _prefs();
      await p.setBool(enabledKey, value);
    } catch (_) {
      // The switch still applies this run; it just won't persist.
    }
    await _reconcile();
  }

  /// Choose the policy and restart so the running governor follows it. A
  /// governor is built with the gateway, so changing the figure without
  /// rebuilding it would leave the old cap in force and the switch lying.
  Future<void> setAirtimePolicy(AirtimePolicy value) async {
    if (value == _airtimePolicy) return;
    _airtimePolicy = value;
    await AirtimePolicyPrefs.setPolicy(value);
    notifyListeners();
    await _stop();
    await _reconcile();
  }

  /// Revoke the current pairing and issue a new token.
  Future<void> revokePairing() async {
    final Gateway? g = _gateway;
    if (g == null) return;
    try {
      await g.reissuePairing();
      _token = g.pairingToken;
    } catch (e) {
      _fail('could not store the new pairing token: $e');
    }
    notifyListeners();
  }

  /// Bring the running state in line with (enabled, radio ready, radio tuple).
  /// Serialised: a change arriving mid-start runs once more afterwards.
  Future<void> _reconcile() async {
    if (_disposed) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _step();
      } while (_again && !_disposed);
    } finally {
      _busy = false;
    }
  }

  Future<void> _step() async {
    final SelfInfo? radio = _mc.selfInfo;
    final bool ready = _mc.isReady && radio != null;
    // The governor's estimate is built for one radio tuple. If the user
    // applies other parameters, restart so the estimate follows.
    final String? tuple = radio == null
        ? null
        : '${radio.frequencyMhz}/${radio.bandwidthKhz}/'
            '${radio.spreadingFactor}/${radio.codingRate}';
    final bool shouldRun = _enabled && ready;

    if (!shouldRun) {
      await _stop();
      _set(!_enabled ? GatewayRunState.off : GatewayRunState.waitingForRadio);
      return;
    }
    if (_gateway != null && tuple == _radioTuple) return;
    if (_hasFailed && tuple == _failedTuple) return;
    await _stop();
    await _start(radio, tuple);
  }

  Future<void> _start(SelfInfo radio, String? tuple) async {
    final MeshcoreMeshSender sender = MeshcoreMeshSender(_mc);
    final Gateway gateway = Gateway(
      mesh: sender,
      persistence: _persistence,
      port: _port,
      estimator: estimatorFor(radio),
      airtimePolicy: _airtimePolicy,
    );
    try {
      await gateway.start();
    } catch (e) {
      // `start` loads the token before binding, so a secure-storage failure
      // means nothing is listening.
      await sender.dispose();
      _hasFailed = true;
      _failedTuple = tuple;
      _fail(e.toString());
      return;
    }
    if (_disposed || !_enabled) {
      await gateway.stop();
      await sender.dispose();
      return;
    }
    _gateway = gateway;
    _sender = sender;
    _radioTuple = tuple;
    // Hold the process alive for as long as anything is listening: the client is
    // another app and cannot keep this one from being killed. Assigned first so
    // that _stop() -- which releases only when a gateway is present -- can never
    // miss a hold taken during a dispose that lands inside this await.
    await _mc.holdKeepaliveForGateway();
    _token = gateway.pairingToken; // after start(): load() may replace it
    _error = null;
    _hasFailed = false;
    _set(GatewayRunState.running);
  }

  Future<void> _stop() async {
    final Gateway? g = _gateway;
    final MeshcoreMeshSender? s = _sender;
    if (g != null) await _mc.releaseKeepaliveForGateway();
    _gateway = null;
    _sender = null;
    _token = null;
    _radioTuple = null;
    try {
      await g?.stop();
    } catch (_) {
      // Already closed.
    }
    await s?.dispose();
  }

  void _fail(String message) {
    _error = message;
    _set(GatewayRunState.failed);
  }

  void _set(GatewayRunState s) {
    final bool changed = _status != s;
    _status = s;
    if (changed || s == GatewayRunState.failed) notifyListeners();
    if (s != GatewayRunState.failed) _error = null;
  }

  /// What another app on this phone may be told right now. Built from the same fields the screen
  /// reads, so the handoff can never disagree with what the user sees.
  GatewayOffer get offer {
    // Running with no token is not a thing to offer: it is "off" to a client.
    final String state = switch (_status) {
      GatewayRunState.running => _token == null ? 'off' : 'running',
      GatewayRunState.waitingForRadio => 'waitingForRadio',
      GatewayRunState.failed => 'failed',
      GatewayRunState.off => 'off',
    };
    if (state != 'running') return GatewayOffer(state: state, port: 0);
    final Uint8List? self = _mc.selfInfo?.publicKey;
    return GatewayOffer(
      state: 'running',
      port: port,
      token: Uint8List.fromList(_token!),
      radioKey:
          self?.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(),
      peerName: boundPeerName,
    );
  }

  /// Every change a listener hears is a change the handoff must hear, so this rides on the one
  /// notification rather than a second set of call sites that could miss one (state, port, token
  /// rotation and stop all notify). Unchanged offers are not re-sent.
  @override
  void notifyListeners() {
    super.notifyListeners();
    if (_disposed) return;
    final GatewayOffer next = offer;
    if (next == _published) return;
    _published = next;
    unawaited(_handoff.publish(next));
  }

  /// Idempotent.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _published = null;
    unawaited(_handoff.clear());
    _mc.removeListener(_reconcile);
    unawaited(_stop());
    super.dispose();
  }
}
