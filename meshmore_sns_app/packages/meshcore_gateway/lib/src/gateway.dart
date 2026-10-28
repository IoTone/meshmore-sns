// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'constants.dart';
import 'governor.dart';
import 'mesh_sender.dart';
import 'pairing_store.dart';
import 'server.dart';

/// The composition the app instantiates: pairing store, radio bridge,
/// governor and listener, in one object.
class Gateway {
  Gateway({
    required MeshSender mesh,
    PairingPersistence? persistence,
    Governor? governor,
    int port = GatewayServer.defaultPort,
    Duration preAuthTimeout = GatewayLimits.preAuthTimeout,
    AirtimeEstimator estimator = const AirtimeEstimator(),
  })  : _mesh = mesh,
        _governor = governor ?? Governor(),
        _store = PairingStore(persistence: persistence) {
    _server = GatewayServer(
      pairing: _store,
      mesh: _mesh,
      governor: _governor,
      port: port,
      preAuthTimeout: preAuthTimeout,
      estimator: estimator,
    );
  }

  final MeshSender _mesh;
  final Governor _governor;
  final PairingStore _store;
  late final GatewayServer _server;

  /// Load the persisted token, then listen. Call once.
  Future<void> start() async {
    await _store.load();
    await _server.start();
  }

  Future<void> stop() => _server.stop();

  /// The token to show as a QR in Settings -> Connected apps.
  Uint8List get pairingToken => _store.token;

  /// Revoke the current pairing and issue a new token.
  Future<void> reissuePairing() => _store.reissue();

  /// The peer bound by the current session, if any.
  Uint8List? get boundPeer => _server.boundPeer;

  RadioState get radioState => _mesh.radioState;

  Governor get governor => _governor;

  int get port => _server.port;

  bool get isRunning => _server.isRunning;

  /// Whether a client currently holds the single session slot.
  bool get hasSession => _server.hasSession;
}
