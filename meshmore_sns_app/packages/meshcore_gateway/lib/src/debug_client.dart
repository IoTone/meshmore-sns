// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'constants.dart';
import 'frame.dart';
import 'messages.dart';

/// A decoded `STATUS` frame.
typedef GatewayStatus = ({
  RadioState radioState,
  int rssi,
  int batteryPercent,
  int txAirtimeTenthsThisHour,

  /// Records of the current size the gateway says still fit this hour, or null
  /// when it did not send the byte. 255 means "255 or more", which is what the
  /// uncapped airtime policy reports.
  int? opsLeftThisHour,
});

/// A client error, carrying the close reason when the gateway sent one.
class GatewayClientException implements Exception {
  GatewayClientException(this.message, {this.closeReason});

  final String message;
  final CloseReason? closeReason;

  @override
  String toString() =>
      'GatewayClientException: $message'
      '${closeReason == null ? '' : ' (${closeReason!.name})'}';
}

/// A minimal L2 client.
///
/// A development stand-in for LDMUX's KMP client and the driver for the
/// package's own tests. It is deliberately small: no retries, no queueing, one
/// request at a time.
class GatewayClient {
  Socket? _socket;
  final FrameDecoder _decoder = FrameDecoder();
  final List<Frame> _inbox = <Frame>[];
  Completer<Frame>? _pending;
  final StreamController<Uint8List> _records =
      StreamController<Uint8List>.broadcast();
  final StreamController<GatewayStatus> _statuses =
      StreamController<GatewayStatus>.broadcast();
  bool _open = false;
  CloseReason? _closeReason;

  /// Downlink records (`RECV`).
  Stream<Uint8List> get records => _records.stream;

  /// Pushed `STATUS` frames.
  Stream<GatewayStatus> get statuses => _statuses.stream;

  /// The reason the gateway closed the connection, once it has.
  CloseReason? get closeReason => _closeReason;

  /// The sixth `STATUS` byte from the most recent push, or null if none has
  /// carried it. Records of the current size left in this hour's budget.
  int? get lastOpsLeft => _lastOpsLeft;
  int? _lastOpsLeft;

  bool get isOpen => _open;

  Future<void> connect({
    String host = '127.0.0.1',
    required int port,
  }) async {
    final Socket socket = await Socket.connect(host, port);
    socket.setOption(SocketOption.tcpNoDelay, true);
    _socket = socket;
    _open = true;
    socket.listen(
      _onChunk,
      onError: (Object error) => _fail('socket error: $error'),
      onDone: () => _open = false,
      cancelOnError: false,
    );
  }

  /// `HELLO`. [versionOverride] exists only so a test can present the wrong
  /// version.
  Future<({int capabilities, RadioState radioState})> hello({
    int capabilities = 0,
    int? versionOverride,
  }) async {
    if (versionOverride == null) {
      _write(GatewayMessages.hello(capabilities: capabilities));
    } else {
      _write(Frame(
        type: FrameType.hello,
        payload: <int>[versionOverride, capabilities & 0xFF],
      ));
    }
    final Frame frame = await _next();
    final HelloError? error = GatewayMessages.readHelloErr(frame);
    if (error != null) {
      throw GatewayClientException('hello refused: ${error.name}');
    }
    final ({int version, int capabilities, RadioState radioState})? ok =
        GatewayMessages.readHelloOk(frame);
    if (ok == null) {
      throw GatewayClientException('expected HELLO_OK, got ${frame.type.name}');
    }
    return (capabilities: ok.capabilities, radioState: ok.radioState);
  }

  /// `PAIR`.
  Future<void> pair(List<int> token) async {
    _write(GatewayMessages.pair(token));
    final Frame frame = await _next();
    final PairError? error = GatewayMessages.readPairErr(frame);
    if (error != null) {
      throw GatewayClientException('pair refused: ${error.name}');
    }
    if (frame.type != FrameType.pairOk) {
      throw GatewayClientException('expected PAIR_OK, got ${frame.type.name}');
    }
  }

  /// `BIND`.
  Future<({int capabilities, int uplinkRecordMax})> bind(
    List<int> peerPubKey,
  ) async {
    _write(GatewayMessages.bind(peerPubKey));
    final Frame frame = await _next();
    final BindError? error = GatewayMessages.readBindErr(frame);
    if (error != null) {
      throw GatewayClientException('bind refused: ${error.name}');
    }
    final ({int capabilities, int uplinkRecordMax})? ok =
        GatewayMessages.readBindOk(frame);
    if (ok == null) {
      throw GatewayClientException('expected BIND_OK, got ${frame.type.name}');
    }
    return ok;
  }

  /// `RECORD`. Fire and forget; the answer arrives as `SEND_RESULT`.
  void sendRecord({required int seq, required List<int> record}) =>
      _write(GatewayMessages.record(seq: seq, opaqueRecord: record));

  /// The next `SEND_RESULT`.
  Future<({int seq, SendOutcome outcome})> nextSendResult() async {
    final Frame frame = await _next();
    final ({int seq, SendOutcome outcome})? result =
        GatewayMessages.readSendResult(frame);
    if (result == null) {
      throw GatewayClientException(
          'expected SEND_RESULT, got ${frame.type.name}');
    }
    return result;
  }

  /// Test hooks: an arbitrary frame or raw bytes.
  void sendRaw(Frame frame) => _write(frame);

  void sendBytes(List<int> bytes) {
    final Socket? socket = _socket;
    if (socket == null || !_open) {
      throw GatewayClientException('not connected');
    }
    socket.add(bytes);
  }

  /// Wait until [condition] holds, or fail after [timeout].
  Future<void> waitFor(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        throw GatewayClientException('condition not met within $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> close() async {
    _open = false;
    final Socket? socket = _socket;
    _socket = null;
    try {
      await socket?.close();
    } catch (_) {
      // Already closed.
    }
    if (!_records.isClosed) await _records.close();
    if (!_statuses.isClosed) await _statuses.close();
  }

  // ---------------------------------------------------------------------

  void _write(Frame frame) {
    final Socket? socket = _socket;
    if (socket == null || !_open) {
      throw GatewayClientException('not connected');
    }
    socket.add(frame.encode());
  }

  void _onChunk(List<int> chunk) {
    for (final Frame frame in _decoder.add(chunk)) {
      if (frame.type == FrameType.recv) {
        if (!_records.isClosed) {
          _records.add(Uint8List.fromList(frame.payload));
        }
        continue;
      }
      if (frame.type == FrameType.status) {
        final GatewayStatus? status = GatewayMessages.readStatus(frame);
        _lastOpsLeft = GatewayMessages.readOpsLeft(frame);
        if (status != null && !_statuses.isClosed) _statuses.add(status);
        continue;
      }
      if (frame.type == FrameType.close) {
        _closeReason = GatewayMessages.readClose(frame);
        _open = false;
        _fail('closed: ${_closeReason?.name ?? 'unknown'}');
        continue;
      }
      _deliver(frame);
    }
    if (_decoder.error != null) _fail('framing: ${_decoder.error}');
  }

  void _deliver(Frame frame) {
    final Completer<Frame>? pending = _pending;
    if (pending != null && !pending.isCompleted) {
      _pending = null;
      pending.complete(frame);
      return;
    }
    _inbox.add(frame);
  }

  Future<Frame> _next({Duration timeout = const Duration(seconds: 5)}) {
    if (_inbox.isNotEmpty) return Future<Frame>.value(_inbox.removeAt(0));
    final Completer<Frame> completer = Completer<Frame>();
    _pending = completer;
    return completer.future.timeout(timeout, onTimeout: () {
      _pending = null;
      throw GatewayClientException('timed out waiting for a frame');
    });
  }

  void _fail(String message) {
    final Completer<Frame>? pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        GatewayClientException(message, closeReason: _closeReason),
      );
    }
  }
}
