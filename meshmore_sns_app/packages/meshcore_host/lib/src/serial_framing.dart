// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

/// The USB-serial companion framing from the firmware's
/// `ArduinoSerialInterface` (`src/helpers/ArduinoSerialInterface.cpp`):
///
///  * host -> radio: `'<' len_lo len_hi payload`
///  * radio -> host: `'>' len_lo len_hi payload`
///
/// The direction of the two header bytes is counter-intuitive and is stated by
/// the firmware both ways: `writeFrame` writes `'>'` for frames leaving the
/// radio, and `checkRecvFrame` accepts only `'<'` from the app
/// (`ArduinoSerialInterface.cpp:31,46`). `SerialWifiInterface.cpp:143` spells it
/// out: "'<' is 0x3c which indicates a frame sent from app to radio".
///
/// The length is little-endian and excludes the three header bytes. The
/// firmware's `MAX_FRAME_SIZE` is 176 (`src/helpers/BaseSerialInterface.h`).
///
/// This is a *stream* framing: unlike BLE, where one notification is one
/// frame, serial can split a frame across reads and coalesce several frames
/// into one read. The decoder is therefore incremental and keeps its state.
abstract final class SerialFraming {
  /// Host-to-radio header: what the firmware's receive path accepts.
  static const int hostHeader = 0x3C; // '<'

  /// Radio-to-host header: what the firmware's write path emits.
  static const int radioHeader = 0x3E; // '>'

  /// Firmware ceiling per frame.
  static const int maxFrame = 176;
}

/// Thrown when a length field cannot be trusted or a frame exceeds the
/// firmware ceiling. Sticky on the decoder: after this, the stream must be
/// re-synchronised before any further frame is emitted, because continuing
/// on a guessed boundary would deliver corrupted companion frames.
class SerialFramingError implements Exception {
  SerialFramingError(this.message);
  final String message;
  @override
  String toString() => 'SerialFramingError: $message';
}

/// Encodes one companion frame for the radio.
Uint8List encodeSerialFrame(List<int> payload) {
  if (payload.isEmpty) {
    throw ArgumentError.value(payload, 'payload', 'a frame cannot be empty');
  }
  if (payload.length > SerialFraming.maxFrame) {
    throw ArgumentError.value(
      payload.length,
      'payload',
      'exceeds the firmware ceiling of ${SerialFraming.maxFrame} bytes',
    );
  }
  final Uint8List out = Uint8List(3 + payload.length);
  out[0] = SerialFraming.hostHeader;
  out[1] = payload.length & 0xFF;
  out[2] = (payload.length >> 8) & 0xFF;
  out.setRange(3, out.length, payload);
  return out;
}

/// Incremental decoder for `'>' len_lo len_hi payload` frames.
///
/// Error policy: a length above [SerialFraming.maxFrame] is fatal and sticky.
/// Bytes before a header are discarded (a device that was already running
/// when the port opened may have flushed partial output). A frame that ends
/// exactly at the buffer boundary is emitted immediately and the decoder
/// returns to searching for a header, so back-to-back frames work.
class SerialFrameDecoder {
  /// [header] is the byte that starts a frame. Defaults to the radio-to-host
  /// header; a radio-side fake (or a host-to-radio reader) passes
  /// [SerialFraming.hostHeader].
  SerialFrameDecoder({this.header = SerialFraming.radioHeader});

  final int header;
  final List<int> _buffer = <int>[];
  bool _failed = false;

  /// True once a framing error has occurred. The link should be reopened.
  bool get hasFailed => _failed;

  /// Feeds bytes and returns every complete frame now available.
  List<Uint8List> add(List<int> bytes) {
    if (_failed) return const <Uint8List>[];
    _buffer.addAll(bytes);
    final List<Uint8List> frames = <Uint8List>[];
    while (true) {
      final int start = _buffer.indexOf(header);
      if (start < 0) {
        // Keep a trailing byte that could be the start of nothing useful;
        // discard everything else.
        _buffer.clear();
        break;
      }
      if (start > 0) _buffer.removeRange(0, start);
      if (_buffer.length < 3) break;
      final int length = _buffer[1] | (_buffer[2] << 8);
      if (length == 0) {
        // The firmware never sends an empty frame. Treat as a false header:
        // drop it and resynchronise on the next byte.
        _buffer.removeAt(0);
        continue;
      }
      if (length > SerialFraming.maxFrame) {
        _failed = true;
        _buffer.clear();
        throw SerialFramingError(
          'length $length exceeds ${SerialFraming.maxFrame}',
        );
      }
      if (_buffer.length < 3 + length) break;
      frames.add(Uint8List.fromList(_buffer.sublist(3, 3 + length)));
      _buffer.removeRange(0, 3 + length);
    }
    return frames;
  }
}
