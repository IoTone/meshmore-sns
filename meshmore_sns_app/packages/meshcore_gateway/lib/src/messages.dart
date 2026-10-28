// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'constants.dart';
import 'frame.dart';

/// Typed access to the frame set. Each builder produces a [Frame]; each
/// reader takes a [Frame] and returns a typed value or null.
///
/// Readers are total: a frame of the wrong type, or one too short for its
/// fields, yields null rather than throwing. A caller that receives null
/// for a frame it expected should close the connection with
/// [CloseReason.protocol].
abstract final class GatewayMessages {
  // ---------------------------------------------------------------------
  // Handshake: HELLO before PAIR, so a version mismatch is reportable
  // rather than fatal.
  // ---------------------------------------------------------------------

  /// `HELLO`: version (1) + capability bits (1).
  static Frame hello({int capabilities = 0}) => Frame(
        type: FrameType.hello,
        payload: <int>[GatewayLimits.version, capabilities & 0xFF],
      );

  /// `HELLO_OK`: version (1) + capability bits (1) + radio state (1).
  static Frame helloOk({
    required RadioState radioState,
    int capabilities = 0,
  }) =>
      Frame(
        type: FrameType.helloOk,
        payload: <int>[GatewayLimits.version, capabilities & 0xFF, radioState.code],
      );

  /// `HELLO_ERR`: one reason byte.
  static Frame helloErr(HelloError reason) =>
      Frame(type: FrameType.helloErr, payload: <int>[reason.code]);

  // ---------------------------------------------------------------------
  // Pairing
  // ---------------------------------------------------------------------

  /// `PAIR`: the pairing token, exactly [GatewayLimits.pairingTokenBytes].
  static Frame pair(List<int> token) {
    if (token.length != GatewayLimits.pairingTokenBytes) {
      throw FrameLengthError(
        'pairing token',
        token.length,
        GatewayLimits.pairingTokenBytes,
      );
    }
    return Frame(type: FrameType.pair, payload: token);
  }

  static Frame pairOk() => Frame(type: FrameType.pairOk);

  static Frame pairErr(PairError reason) =>
      Frame(type: FrameType.pairErr, payload: <int>[reason.code]);

  // ---------------------------------------------------------------------
  // Binding a mesh peer
  // ---------------------------------------------------------------------

  /// `BIND`: the peer's 32-byte public key.
  static Frame bind(List<int> peerPubKey) {
    if (peerPubKey.length != 32) {
      throw FrameLengthError('peer public key', peerPubKey.length, 32);
    }
    return Frame(type: FrameType.bind, payload: peerPubKey);
  }

  /// `BIND_OK`: capability bits (1) + the largest uplink record this peer's
  /// path actually allows (1, bytes).
  ///
  /// The capacity has to be advertised rather than assumed. Raw data accepts
  /// `174 - path_len`, so a long path silently shrinks the record, and a
  /// session that sized to the absolute ceiling would burn airtime on sends
  /// the radio refuses. The receiver sizes to this number.
  static Frame bindOk({
    int capabilities = 0,
    int uplinkRecordMax = GatewayLimits.recordFloor,
  }) {
    if (uplinkRecordMax < 1 || uplinkRecordMax > GatewayLimits.recordMax) {
      throw ArgumentError.value(
        uplinkRecordMax,
        'uplinkRecordMax',
        'must be in 1..${GatewayLimits.recordMax}',
      );
    }
    return Frame(
      type: FrameType.bindOk,
      payload: <int>[capabilities & 0xFF, uplinkRecordMax],
    );
  }

  static Frame bindErr(BindError reason) =>
      Frame(type: FrameType.bindErr, payload: <int>[reason.code]);

  // ---------------------------------------------------------------------
  // Data plane: opaque records, never parsed
  // ---------------------------------------------------------------------

  /// `RECORD`: one uplink record, at most [GatewayLimits.recordMax].
  ///
  /// The record is opaque. In the established state the gateway hands it to
  /// `cmd_send_raw_data`, which copies bytes verbatim, so the record length
  /// on the wire is exactly this length. During discovery the gateway
  /// prefixes a one-byte length instead, because the binary carrier
  /// zero-pads a datagram to 16 bytes and the receiver does not strip the
  /// padding.
  static Frame record({
    required int seq,
    required List<int> opaqueRecord,
  }) {
    if (seq < 0 || seq > 0xFF) {
      throw ArgumentError.value(seq, 'seq', 'must fit in one byte');
    }
    if (opaqueRecord.length > GatewayLimits.recordMax) {
      throw FrameLengthError(
        'record',
        opaqueRecord.length,
        GatewayLimits.recordMax,
      );
    }
    return Frame(
      type: FrameType.record,
      payload: <int>[seq, ...opaqueRecord],
    );
  }

  /// `RECV`: one downlink record, at most [GatewayLimits.recordMax].
  static Frame recv(List<int> opaqueRecord) {
    if (opaqueRecord.length > GatewayLimits.recordMax) {
      throw FrameLengthError(
        'record',
        opaqueRecord.length,
        GatewayLimits.recordMax,
      );
    }
    return Frame(type: FrameType.recv, payload: opaqueRecord);
  }

  /// `SEND_RESULT`: what the radio did with the record carrying [seq].
  ///
  /// The sequence number is carried back because a gateway queue can hold
  /// several records while one is in flight, and a refused record must be
  /// attributable. Without it a client cannot tell which of its records
  /// failed, and would either retry the wrong one or drop the right one.
  static Frame sendResult({
    required int seq,
    required SendOutcome outcome,
  }) {
    if (seq < 0 || seq > 0xFF) {
      throw ArgumentError.value(seq, 'seq', 'must fit in one byte');
    }
    return Frame(
      type: FrameType.sendResult,
      payload: <int>[seq, outcome.code],
    );
  }

  /// `STATUS`: radio state, rssi, battery, and the gateway's own transmit
  /// airtime used this hour in 0.1 s units (little-endian).
  ///
  /// [rssi] is written as a signed byte, so [GatewayLimits.unknownRssi]
  /// (-128) round-trips. [batteryPercent] uses
  /// [GatewayLimits.unknownBattery] when the radio reports nothing.
  ///
  /// The airtime figure is an **estimate** the gateway accumulates from the
  /// firmware's timeout estimate; it cannot see repeater retransmissions or
  /// collisions. It is reported for display, not enforced on the peer: an
  /// airtime budget belongs to the transmitter that spends it.
  static Frame status({
    required RadioState radioState,
    required int rssi,
    required int batteryPercent,
    required int txAirtimeTenthsThisHour,
    int? opsLeftThisHour,
  }) {
    if (opsLeftThisHour != null && (opsLeftThisHour < 0 || opsLeftThisHour > 255)) {
      throw ArgumentError.value(
        opsLeftThisHour,
        'opsLeftThisHour',
        'must fit in one byte',
      );
    }
    if (txAirtimeTenthsThisHour < 0 || txAirtimeTenthsThisHour > 0xFFFF) {
      throw ArgumentError.value(
        txAirtimeTenthsThisHour,
        'txAirtimeTenthsThisHour',
        'must fit in 16 bits',
      );
    }
    return Frame(
      type: FrameType.status,
      payload: Uint8List.fromList(<int>[
        radioState.code,
        rssi & 0xFF,
        batteryPercent & 0xFF,
        txAirtimeTenthsThisHour & 0xFF,
        (txAirtimeTenthsThisHour >> 8) & 0xFF,
        // Appended in v1.1: readers that stop at five bytes still work.
        if (opsLeftThisHour != null) opsLeftThisHour,
      ]),
    );
  }

  /// `CLOSE`: one reason byte, then a clean shutdown.
  static Frame close(CloseReason reason) =>
      Frame(type: FrameType.close, payload: <int>[reason.code]);

  // ---------------------------------------------------------------------
  // Readers
  // ---------------------------------------------------------------------

  /// Reads `HELLO`.
  static ({int version, int capabilities})? readHello(Frame f) {
    if (f.type != FrameType.hello || f.payload.length < 2) return null;
    return (version: f.payload[0], capabilities: f.payload[1]);
  }

  /// Reads `HELLO_OK`.
  static ({int version, int capabilities, RadioState radioState})? readHelloOk(
    Frame f,
  ) {
    if (f.type != FrameType.helloOk || f.payload.length < 3) return null;
    return (
      version: f.payload[0],
      capabilities: f.payload[1],
      radioState: RadioState(f.payload[2]),
    );
  }

  /// Reads `HELLO_ERR`.
  static HelloError? readHelloErr(Frame f) {
    if (f.type != FrameType.helloErr || f.payload.isEmpty) return null;
    return HelloError(f.payload[0]);
  }

  /// Reads `PAIR`. The token is returned as a copy so a caller cannot
  /// accidentally retain a view into the buffer.
  static Uint8List? readPair(Frame f) {
    if (f.type != FrameType.pair ||
        f.payload.length != GatewayLimits.pairingTokenBytes) {
      return null;
    }
    return Uint8List.fromList(f.payload);
  }

  /// Reads `PAIR_ERR`.
  static PairError? readPairErr(Frame f) {
    if (f.type != FrameType.pairErr || f.payload.isEmpty) return null;
    return PairError(f.payload[0]);
  }

  /// Reads `BIND`.
  static Uint8List? readBind(Frame f) {
    if (f.type != FrameType.bind || f.payload.length != 32) return null;
    return Uint8List.fromList(f.payload);
  }

  /// Reads `BIND_ERR`.
  static BindError? readBindErr(Frame f) {
    if (f.type != FrameType.bindErr || f.payload.isEmpty) return null;
    return BindError(f.payload[0]);
  }

  /// Reads `BIND_OK`.
  static ({int capabilities, int uplinkRecordMax})? readBindOk(Frame f) {
    if (f.type != FrameType.bindOk || f.payload.length < 2) return null;
    return (
      capabilities: f.payload[0],
      uplinkRecordMax: f.payload[1],
    );
  }

  /// Reads `RECORD`: the sequence number and the opaque record.
  static ({int seq, Uint8List record})? readRecord(Frame f) {
    if (f.type != FrameType.record || f.payload.length < 2) return null;
    return (
      seq: f.payload[0],
      record: Uint8List.fromList(f.payload.sublist(1)),
    );
  }

  /// Reads `SEND_RESULT`: the sequence number and the outcome.
  static ({int seq, SendOutcome outcome})? readSendResult(Frame f) {
    if (f.type != FrameType.sendResult || f.payload.length < 2) return null;
    return (seq: f.payload[0], outcome: SendOutcome(f.payload[1]));
  }

  /// Reads `STATUS`.
  static ({
    RadioState radioState,
    int rssi,
    int batteryPercent,
    int txAirtimeTenthsThisHour,
  })? readStatus(Frame f) {
    if (f.type != FrameType.status || f.payload.length < 5) return null;
    return (
      radioState: RadioState(f.payload[0]),
      rssi: f.payload[1] < 128 ? f.payload[1] : f.payload[1] - 256,
      batteryPercent: f.payload[2],
      txAirtimeTenthsThisHour: f.payload[3] | (f.payload[4] << 8),
    );
  }

  /// Reads the optional sixth `STATUS` byte: records of the current uplink
  /// size that still fit this hour's airtime budget (0..255, 255 = "255 or
  /// more"). Null when the gateway did not send it (older gateway) or the
  /// frame is not a well-formed `STATUS`.
  ///
  /// The gateway computes it from its own preset-derived airtime estimate, so
  /// a client never needs radio parameters to show "records left". It counts
  /// only records this end may still transmit: a reply is the peer's airtime,
  /// not ours, so it is not an "operation" count.
  static int? readOpsLeft(Frame f) {
    if (f.type != FrameType.status || f.payload.length < 6) return null;
    return f.payload[5];
  }

  /// Reads `CLOSE`.
  static CloseReason? readClose(Frame f) {
    if (f.type != FrameType.close || f.payload.isEmpty) return null;
    return CloseReason(f.payload[0]);
  }
}

/// Compares a presented pairing token with the stored one in constant time.
///
/// A length mismatch is still reported after a comparison that does not
/// short-circuit on content, so the timing of a near-miss is not a signal
/// about how many leading bytes were right.
bool pairingTokenMatches({
  required List<int> presented,
  required List<int> stored,
}) {
  if (stored.length != GatewayLimits.pairingTokenBytes) {
    throw ArgumentError.value(
      stored.length,
      'stored',
      'a stored token must be ${GatewayLimits.pairingTokenBytes} bytes',
    );
  }
  int diff = presented.length ^ stored.length;
  for (int i = 0; i < GatewayLimits.pairingTokenBytes; i++) {
    final int a = i < presented.length ? presented[i] : 0;
    diff |= a ^ stored[i];
  }
  return diff == 0;
}
