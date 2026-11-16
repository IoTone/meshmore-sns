// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'byte_cursor.dart';
import 'constants.dart';

/// Why a carry frame could not be built.
///
/// Encoders refuse an over-long payload instead of truncating it. A
/// truncated payload is a silent protocol violation, and on this link a
/// single lost byte is indistinguishable from a corrupted record, so the
/// failure is loud at build time.
class MeshCarryLengthError implements Exception {
  const MeshCarryLengthError(this.field, this.actual, this.maximum);

  final String field;
  final int actual;
  final int maximum;

  @override
  String toString() =>
      'MeshCarryLengthError: $field is $actual byte(s), maximum $maximum';
}

/// Byte budgets for the binary-request and raw carriers.
///
/// Derived from the firmware, not from arithmetic on the protocol
/// version: three caps stack on the phone's uplink and the smallest one
/// binds. See `meshmore-sns-architecture.md` §5.2.
abstract final class MeshCarryLimits {
  /// `MAX_FRAME_SIZE` — one companion frame, `BaseSerialInterface.h:5`.
  static const int maxFrameSize = 176;

  // --- CMD_SEND_BINARY_REQ (0x32) ---

  /// Bytes of a binary request consumed before the application payload:
  /// the opcode plus the 32-byte peer public key.
  static const int binaryReqHeaderBytes = 1 + kPubKeySize;

  /// Maximum application payload a binary request can carry:
  /// `176 - 1 - 32 = 143`.
  static const int binaryReqAppDataMax = maxFrameSize - binaryReqHeaderBytes;

  /// Bytes of the one-byte record length that precedes a record inside
  /// the application payload.
  static const int recordLengthPrefixBytes = 1;

  /// Maximum record a binary request can carry: `143 - 1 = 142`.
  static const int binaryReqRecordMax = binaryReqAppDataMax - recordLengthPrefixBytes;

  // --- CMD_SEND_RAW_DATA (0x19) ---

  /// The firmware requires at least a 4-byte payload
  /// (`i + path_len + 4 <= len`).
  static const int rawDataMinPayload = 4;

  /// Maximum raw-data payload for a given path length:
  /// `176 - 1 (opcode) - 1 (path_len) - pathLen`.
  static int rawDataPayloadMax(int pathLen) => maxFrameSize - 2 - pathLen;

  // --- CMD_SEND_RAW_PACKET (0x41) ---

  /// Maximum serialised packet: `176 - 1 (opcode) - 1 (priority)`.
  static const int rawPacketMax = maxFrameSize - 2;

  // --- PUSH_CODE_BINARY_RESPONSE (0x8C) ---

  /// Bytes the push consumes before the peer's payload: opcode, one
  /// reserved byte, and the 4-byte tag.
  static const int binaryResponseHeaderBytes = 1 + 1 + 4;

  /// Maximum payload a binary-response push can deliver.
  static const int binaryResponsePayloadMax =
      maxFrameSize - binaryResponseHeaderBytes;

  /// `RESP_CODE_SENT` frame size: opcode, flood flag, tag, est_timeout.
  static const int sendResultFrameBytes = 10;
}

/// The radio's report that it accepted a binary request for transmission.
///
/// This is **not** a delivery acknowledgement. It says the packet was
/// handed to the radio and how it was routed. Whether the peer received
/// it, and whether the peer answered, are separate questions that only an
/// end-to-end layer above this one can answer.
class MeshSendResult {
  const MeshSendResult({
    required this.flood,
    required this.tag,
    required this.estTimeoutMs,
  });

  /// True when the firmware routed the request as a flood
  /// (`MSG_SEND_SENT_FLOOD`). False means it used a known direct path.
  final bool flood;

  /// The firmware-chosen tag. The client does not choose it; it echoes
  /// this value back in `PUSH_CODE_BINARY_RESPONSE`. A tag of 0 cannot
  /// match, because 0 is the firmware's idle sentinel.
  final int tag;

  /// The firmware's **estimate** of the round trip, from
  /// `calcFloodTimeoutMillisFor` / `calcDirectTimeoutMillisFor`. It is
  /// not a measurement: it cannot account for repeater retransmissions
  /// or collisions.
  final int estTimeoutMs;

  bool get tagUsable => tag != 0;

  @override
  String toString() => 'MeshSendResult(flood: $flood, '
      'tag: 0x${tag.toRadixString(16).padLeft(8, '0')}, '
      'estTimeoutMs: $estTimeoutMs)';
}

/// A peer's reply, delivered as an asynchronous push.
class MeshBinaryResponse {
  const MeshBinaryResponse({required this.tag, required this.data});

  /// Echoes [MeshSendResult.tag] so the request can be matched.
  final int tag;

  /// The peer's application bytes. Length is frame-derived: the push is
  /// not padded, because the firmware hands the decrypted datagram
  /// straight through.
  final Uint8List data;

  @override
  String toString() => 'MeshBinaryResponse(tag: '
      '0x${tag.toRadixString(16).padLeft(8, '0')}, ${data.length} B)';
}

/// Encoders and decoders for the binary-request and raw carriers.
///
/// These are the L1 frames that move an opaque record over MeshCore: one
/// addressed packet, or a flooded binary request. Decoding is total in the same sense as
/// [MeshcoreFrameCodec.decode]: malformed input yields null rather than
/// throwing.
abstract final class MeshCarryCodec {
  // ---------------------------------------------------------------------
  // Encoders (App → Device)
  // ---------------------------------------------------------------------

  /// `CMD_SEND_BINARY_REQ` (0x32): `32 [pub_key 32] [app data]`.
  ///
  /// The radio requires the peer to already be a contact; it answers
  /// `ERR_CODE_NOT_FOUND` otherwise. Adding a contact is a separate,
  /// privileged command that this codec deliberately does not expose.
  static Uint8List sendBinaryReq({
    required List<int> pubKey,
    required List<int> appData,
  }) {
    _requireLength('pubKey', pubKey.length, kPubKeySize);
    _requireLength('appData', appData.length, MeshCarryLimits.binaryReqAppDataMax);
    final FrameBuilder b = FrameBuilder()
      ..u8(MeshcoreCommand.sendBinaryReq.code)
      ..raw(pubKey)
      ..raw(appData);
    return b.build();
  }

  /// Prefixes [record] with its one-byte length, producing the application
  /// payload for [sendBinaryReq].
  ///
  /// This exists because MeshCore's binary path encrypts with AES-ECB and
  /// zero-pads the final block to 16 bytes without stripping the padding
  /// on the receiving side. A record therefore cannot be delimited by
  /// length alone, and "the 16-byte tag guarantees a non-zero tail" is
  /// false one time in 256. The explicit length is the delimiter.
  static Uint8List lengthPrefixedRecord(List<int> record) {
    _requireLength(
      'record',
      record.length,
      MeshCarryLimits.binaryReqRecordMax,
    );
    final FrameBuilder b = FrameBuilder()
      ..u8(record.length)
      ..raw(record);
    return b.build();
  }

  /// `CMD_SEND_RAW_DATA` (0x19): `19 [path_len] [path] [payload]`.
  ///
  /// Direct-route only. The firmware rejects a negative `path_len` with
  /// `ERR_CODE_UNSUPPORTED_CMD` ("flood, not supported (yet)"), so a
  /// flooded send must go through [sendBinaryReq] instead. Raw data is
  /// copied verbatim: no cipher, no padding.
  static Uint8List sendRawData({
    required List<int> path,
    required List<int> payload,
  }) {
    if (path.length > 0x7F) {
      throw MeshCarryLengthError('path', path.length, 0x7F);
    }
    final int maximum = MeshCarryLimits.rawDataPayloadMax(path.length);
    if (payload.length < MeshCarryLimits.rawDataMinPayload) {
      throw ArgumentError.value(
        payload.length,
        'payload',
        'raw data needs at least ${MeshCarryLimits.rawDataMinPayload} bytes',
      );
    }
    _requireLength('payload', payload.length, maximum);
    final FrameBuilder b = FrameBuilder()
      ..u8(MeshcoreCommand.sendRawData.code)
      ..u8(path.length)
      ..raw(path)
      ..raw(payload);
    return b.build();
  }

  /// `CMD_SEND_RAW_PACKET` (0x41): `41 [priority] [packet]`.
  ///
  /// The caller supplies the whole serialised MeshCore packet. This is
  /// the only carrier with no padding and no cipher on the phone's uplink
  /// that also reaches the full packet ceiling, so it removes the
  /// delimitation problem entirely. Repeaters still will not forward a
  /// `PAYLOAD_TYPE_RAW_CUSTOM` flood, so first contact must use
  /// [sendBinaryReq].
  static Uint8List sendRawPacket({
    required int priority,
    required List<int> packet,
  }) {
    if (priority < 0 || priority > 0xFF) {
      throw ArgumentError.value(priority, 'priority', 'must fit in one byte');
    }
    _requireLength('packet', packet.length, MeshCarryLimits.rawPacketMax);
    final FrameBuilder b = FrameBuilder()
      ..u8(MeshcoreCommand.sendRawPacket.code)
      ..u8(priority)
      ..raw(packet);
    return b.build();
  }

  // ---------------------------------------------------------------------
  // Decoders (Device → App)
  // ---------------------------------------------------------------------

  /// `RESP_CODE_SENT` (0x06): `06 [flood] [tag 4B LE] [est_timeout 4B LE]`.
  ///
  /// Returns null when the frame is not a send result or is truncated.
  /// The hardware answer to a binary request is exactly this or a
  /// `RESP_CODE_ERR`.
  static MeshSendResult? decodeSendResult(Uint8List frame) {
    if (frame.length < MeshCarryLimits.sendResultFrameBytes) return null;
    if (frame[0] != MeshcoreResponse.msgSent.code) return null;
    final ByteCursor c = ByteCursor(frame.sublist(1));
    try {
      final int flood = c.u8('flood');
      final int tag = c.u32('tag');
      final int est = c.u32('est_timeout');
      return MeshSendResult(flood: flood != 0, tag: tag, estTimeoutMs: est);
    } on FrameTruncated {
      return null;
    }
  }

  /// `PUSH_CODE_BINARY_RESPONSE` (0x8C):
  /// `8C [reserved = 0] [tag 4B LE] [payload]`.
  ///
  /// Returns null when the frame is not a binary response, is truncated,
  /// or carries no payload (the firmware only pushes when
  /// `len > 4`).
  static MeshBinaryResponse? decodeBinaryResponse(Uint8List frame) {
    if (frame.length <= MeshCarryLimits.binaryResponseHeaderBytes) return null;
    if (frame[0] != MeshcoreResponse.binaryResponse.code) return null;
    final ByteCursor c = ByteCursor(frame.sublist(1));
    try {
      c.u8('reserved');
      final int tag = c.u32('tag');
      return MeshBinaryResponse(
        tag: tag,
        data: Uint8List.fromList(frame.sublist(MeshCarryLimits.binaryResponseHeaderBytes)),
      );
    } on FrameTruncated {
      return null;
    }
  }

  /// `RESP_CODE_ERR` (0x01): `01 [code]`.
  ///
  /// Returns null when the frame is not an error reply or is truncated.
  static MeshcoreErrorCode? decodeError(Uint8List frame) {
    if (frame.length < 2) return null;
    if (frame[0] != MeshcoreResponse.error.code) return null;
    return MeshcoreErrorCode(frame[1]);
  }

  static void _requireLength(String field, int actual, int maximum) {
    if (actual > maximum) {
      throw MeshCarryLengthError(field, actual, maximum);
    }
  }
}
