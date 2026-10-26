// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'constants.dart';

/// A framed L2 message: type, flags, and an opaque payload.
///
/// Construction is checked. Use [Frame.encode] to produce bytes and
/// [FrameDecoder] to consume a byte stream.
class Frame {
  Frame({required this.type, List<int> payload = const <int>[], this.flags = 0})
      : payload = Uint8List.fromList(payload) {
    if (flags != 0) {
      throw ArgumentError.value(flags, 'flags', 'must be 0 in v1');
    }
    if (this.payload.length > GatewayLimits.maxPayload) {
      throw FrameLengthError(
        'payload',
        this.payload.length,
        GatewayLimits.maxPayload,
      );
    }
  }

  final FrameType type;
  final Uint8List payload;

  /// Reserved. Must be 0; a non-zero value in a future version is a signal,
  /// not noise, so this codec refuses to guess.
  final int flags;

  /// The complete wire form: `MG | version | type | flags | length LE | payload`.
  Uint8List encode() {
    final int length = payload.length;
    final Uint8List out = Uint8List(GatewayLimits.headerBytes + length);
    out[0] = GatewayLimits.magic[0];
    out[1] = GatewayLimits.magic[1];
    out[2] = GatewayLimits.version;
    out[3] = type.code;
    out[4] = flags;
    // Little-endian, matching the rest of the MeshCore ecosystem so the
    // codebase keeps one byte-order convention.
    out[5] = length & 0xFF;
    out[6] = (length >> 8) & 0xFF;
    out.setRange(GatewayLimits.headerBytes, out.length, payload);
    return out;
  }

  @override
  String toString() =>
      'Frame(${type.name}, ${payload.length} B)';
}

/// A payload longer than the contract allows. Refused at construction: a
/// truncated frame is indistinguishable from a corrupted one.
class FrameLengthError implements Exception {
  const FrameLengthError(this.field, this.actual, this.maximum);

  final String field;
  final int actual;
  final int maximum;

  @override
  String toString() =>
      'FrameLengthError: $field is $actual byte(s), maximum $maximum';
}

/// What went wrong while decoding a frame.
enum FrameDecodeError {
  /// The leading bytes are not the magic. The peer is not speaking this
  /// protocol, or the stream is desynchronised.
  badMagic,

  /// A version this codec does not implement. Reported before the rest of
  /// the frame is interpreted, which is why the version byte precedes the
  /// length.
  badVersion,

  /// A length field larger than [GatewayLimits.maxPayload]. Refused rather
  /// than used as an allocation size.
  lengthTooLarge,

  /// Non-zero flags. Reserved in v1.
  badFlags,

  /// The frame ended before its payload did.
  truncated,
}

/// A decoded frame, or the reason there isn't one.
class FrameDecodeResult {
  const FrameDecodeResult.ok(Frame this.frame) : error = null;
  const FrameDecodeResult.failed(FrameDecodeError this.error) : frame = null;

  final Frame? frame;
  final FrameDecodeError? error;

  bool get isOk => frame != null;
}

/// Incremental decoder over a TCP byte stream.
///
/// TCP delivers arbitrary chunk boundaries, so a frame may arrive in pieces
/// and several frames may arrive at once. This class buffers and yields
/// whole frames. It never throws and never allocates from an unvalidated
/// length field.
class FrameDecoder {
  final BytesBuilder _buffer = BytesBuilder(copy: true);

  /// Feed bytes and take the frames they complete.
  ///
  /// Returns the frames decoded so far. On a fatal framing error the
  /// internal buffer is cleared and the error is reported once through
  /// [takeError]; the caller should close the connection.
  List<Frame> add(List<int> chunk) {
    _buffer.add(chunk);
    return _drain();
  }

  /// The error that stopped decoding, if any. Sticky until [reset].
  FrameDecodeError? get error => _error;
  FrameDecodeError? _error;

  void reset() {
    _buffer.clear();
    _error = null;
  }

  List<Frame> _drain() {
    final List<Frame> out = <Frame>[];
    while (true) {
      final Uint8List bytes = _buffer.toBytes();
      if (bytes.length < GatewayLimits.headerBytes) return out;

      for (int i = 0; i < GatewayLimits.magic.length; i++) {
        if (bytes[i] != GatewayLimits.magic[i]) {
          _fail(FrameDecodeError.badMagic);
          return out;
        }
      }
      if (bytes[2] != GatewayLimits.version) {
        _fail(FrameDecodeError.badVersion);
        return out;
      }
      if (bytes[4] != 0) {
        _fail(FrameDecodeError.badFlags);
        return out;
      }
      final int length = bytes[5] | (bytes[6] << 8);
      if (length > GatewayLimits.maxPayload) {
        _fail(FrameDecodeError.lengthTooLarge);
        return out;
      }
      final int total = GatewayLimits.headerBytes + length;
      if (bytes.length < total) return out;

      out.add(Frame(
        type: FrameType(bytes[3]),
        payload: bytes.sublist(GatewayLimits.headerBytes, total),
      ));

      // Rebuffer only the remainder. BytesBuilder has no consume-from-front,
      // so this copies the tail; frames are at most 519 B, so it is cheap.
      final Uint8List rest = bytes.sublist(total);
      _buffer.clear();
      if (rest.isNotEmpty) _buffer.add(rest);
      if (rest.length < GatewayLimits.headerBytes) return out;
    }
  }

  void _fail(FrameDecodeError error) {
    _error = error;
    _buffer.clear();
  }
}
