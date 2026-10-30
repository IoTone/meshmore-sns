// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'constants.dart';
import 'frame.dart';
import 'governor.dart';
import 'messages.dart';
import 'mesh_sender.dart';
import 'pairing_store.dart';
import 'session.dart';

/// The L2 listener.
///
/// One client at a time, loopback only. A second connection is accepted and
/// immediately told `CLOSE(busy)` rather than left to time out, so the
/// rejection is unambiguous.
/// Binding is a seam so the fallback rule can be tested without needing a port
/// the OS actually refuses. Production always uses [ServerSocket.bind].
typedef BindSocket = Future<ServerSocket> Function(InternetAddress, int);

class GatewayServer {
  GatewayServer({
    required PairingStore pairing,
    required MeshSender mesh,
    required Governor governor,
    int port = defaultPort,
    InternetAddress? address,
    Duration preAuthTimeout = GatewayLimits.preAuthTimeout,
    AirtimeEstimator estimator = const AirtimeEstimator(),
    BindSocket? bind,
  })  : _bindSocket = bind ?? _defaultBind,
        _pairing = pairing,
        _mesh = mesh,
        _governor = governor,
        _port = port,
        _address = address ?? InternetAddress.loopbackIPv4,
        _preAuthTimeout = preAuthTimeout,
        _estimator = estimator;

  /// Preferred, not required.
  ///
  /// A fixed port is convenient, but it cannot be assumed: Android keeps a
  /// list of ports reserved for its own use (`/proc/sys/net/ipv4/
  /// ip_local_reserved_ports`) and binding one of them returns EPERM, not
  /// EADDRINUSE. 41731 is on the list of the Pixel-era Android 16 build this
  /// was tested on, so a fixed bind failed with "Operation not permitted".
  /// The gateway therefore treats this as a preference and falls back to an
  /// ephemeral port, and every consumer must read [port] after [start].
  static const int defaultPort = 41731;

  final PairingStore _pairing;
  final MeshSender _mesh;
  final Governor _governor;
  final InternetAddress _address;
  final int _port;
  final Duration _preAuthTimeout;
  final AirtimeEstimator _estimator;
  final BindSocket _bindSocket;

  ServerSocket? _server;
  GatewaySession? _active;
  Uint8List? _boundPeer;
  int? _boundPort;

  /// The port actually bound. Equals [_port] unless that was 0.
  int get port => _server?.port ?? _boundPort ?? _port;

  /// The peer bound by the current (or last) session.
  Uint8List? get boundPeer => _boundPeer;

  bool get isRunning => _server != null;

  /// Whether a client currently holds the single session slot. The slot is
  /// released when the read loop observes the disconnect, so a client that
  /// reconnects immediately after closing can briefly see [false] here after
  /// its own close has returned.
  bool get hasSession => _active != null;

  /// Whether the current session has authenticated. False while a connection
  /// is still in the pre-auth window, or when there is no session.
  bool get hasAuthenticatedSession {
    final GatewaySession? session = _active;
    if (session == null) return false;
    return session.state == GatewaySessionState.paired ||
        session.state == GatewaySessionState.bound;
  }

  Future<void> start() async {
    if (_server != null) throw StateError('gateway server already started');
    final ServerSocket server = await _bind();
    _server = server;
    _boundPort = server.port;
    server.listen(_onSocket);
  }

  /// The preferred port if the OS will give it to us, otherwise an ephemeral
  /// one. A reserved port answers EPERM and a taken one EADDRINUSE; both mean
  /// "not this one", and neither is a reason for the gateway to refuse to run.
  /// Anything else is a real failure and is rethrown.
  Future<ServerSocket> _bind() async {
    if (_port == 0) return _bindSocket(_address, 0);
    try {
      return await _bindSocket(_address, _port);
    } on SocketException catch (e) {
      if (e.osError?.errorCode != 1 && e.osError?.errorCode != 98) rethrow;
      return _bindSocket(_address, 0);
    }
  }

  static Future<ServerSocket> _defaultBind(InternetAddress a, int p) =>
      ServerSocket.bind(a, p, shared: false);

  Future<void> stop() async {
    final GatewaySession? session = _active;
    _active = null;
    _boundPeer = null;
    session?.shutdown();
    final ServerSocket? server = _server;
    _server = null;
    await server?.close();
  }

  void _onSocket(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    final GatewaySession? current = _active;
    if (current != null) {
      final bool authenticated = current.state == GatewaySessionState.paired ||
          current.state == GatewaySessionState.bound;
      if (authenticated) {
        unawaited(_rejectBusy(socket));
        return;
      }
      // An unpaired connection has proved nothing and holds no state, so it
      // must not be able to deny the single session slot by squatting on it
      // for one pre-auth window after another. Evict it and take the slot.
      // `_run`'s finally only clears `_active` when it is still this session,
      // so the evicted loop cannot disturb the replacement.
      current.shutdown();
      _active = null;
    }
    final GatewaySession session = GatewaySession(
      pairing: _pairing,
      mesh: _mesh,
      governor: _governor,
      send: (Frame frame) => socket.add(frame.encode()),
      onClosed: () => unawaited(_closeQuietly(socket)),
      onBound: (Uint8List peer) => _boundPeer = peer,
      preAuthTimeout: _preAuthTimeout,
      estimator: _estimator,
    );
    _active = session;
    unawaited(_run(socket, session));
  }

  Future<void> _run(Socket socket, GatewaySession session) async {
    session.start();
    final FrameDecoder decoder = FrameDecoder();
    try {
      await for (final List<int> chunk in socket) {
        // Awaited in order: a BIND awaiting the radio must not interleave
        // with the RECORD that follows it.
        for (final Frame frame in decoder.add(chunk)) {
          await session.handleFrame(frame);
        }
        if (decoder.error != null) {
          session.protocolError();
          break;
        }
      }
    } catch (_) {
      // A socket error ends the session; the finally block cleans up.
    } finally {
      session.dispose();
      if (identical(_active, session)) {
        _active = null;
        _boundPeer = null;
      }
      await _closeQuietly(socket);
    }
  }

  Future<void> _rejectBusy(Socket socket) async {
    try {
      socket.add(GatewayMessages.close(CloseReason.busy).encode());
      await socket.flush();
    } catch (_) {
      // Peer already gone.
    }
    await _closeQuietly(socket);
  }

  Future<void> _closeQuietly(Socket socket) async {
    try {
      await socket.close();
    } catch (_) {
      // Already closed.
    }
  }
}
