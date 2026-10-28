// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';

import 'serial_framing.dart';

/// Writes one already-framed byte chunk to the port. Injected so the
/// transport is testable without a device and the TTY policy stays in the
/// binary, not in the library.
typedef SerialWrite = Future<void> Function(List<int> bytes);

/// A [MeshcoreTransport] over the firmware's USB-serial companion framing.
///
/// The link state is explicit ([setConnected]) because a serial port has no
/// connection event: the host decides when the port is open and usable.
/// A framing error closes the transport's `connected` stream with `false`
/// rather than silently dropping frames, so the L1 client can re-handshake.
class SerialFrameTransport implements MeshcoreTransport {
  SerialFrameTransport({
    required Stream<List<int>> inboundBytes,
    required SerialWrite write,
  })  : _write = write,
        _inboundBytes = inboundBytes;

  final SerialWrite _write;
  final Stream<List<int>> _inboundBytes;
  final SerialFrameDecoder _decoder = SerialFrameDecoder();
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  final StreamController<bool> _connected =
      StreamController<bool>.broadcast();
  StreamSubscription<List<int>>? _sub;
  bool _isConnected = false;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Stream<bool> get connected => _connected.stream;

  @override
  bool get isConnected => _isConnected;

  /// Start reading. Idempotent.
  void start() {
    _sub ??= _inboundBytes.listen(
      _onBytes,
      onError: (Object _) => setConnected(false),
      onDone: () => setConnected(false),
      cancelOnError: false,
    );
  }

  void _onBytes(List<int> bytes) {
    List<Uint8List> frames;
    try {
      frames = _decoder.add(bytes);
    } on SerialFramingError {
      setConnected(false);
      return;
    }
    for (final Uint8List frame in frames) {
      if (!_incoming.isClosed) _incoming.add(frame);
    }
  }

  /// Marks the link up or down. Serial has no such event, so the owner calls
  /// this when the port opens, closes, or a framing error occurs.
  void setConnected(bool value) {
    if (_isConnected == value) return;
    _isConnected = value;
    if (!_connected.isClosed) _connected.add(value);
  }

  @override
  Future<void> send(Uint8List frame) async {
    if (!_isConnected) {
      throw StateError('serial link is not connected');
    }
    await _write(encodeSerialFrame(frame));
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    _isConnected = false;
    await _incoming.close();
    await _connected.close();
  }
}
