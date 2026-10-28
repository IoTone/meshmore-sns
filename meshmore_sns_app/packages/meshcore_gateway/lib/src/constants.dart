// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
/// Wire constants for the MeshMore gateway contract (L2).
///
/// The authority is `meshmore-sns-architecture.md` §5.5. This file is the
/// transcription; if the two disagree, the document is right and this file
/// is the bug.
abstract final class GatewayLimits {
  /// Frame magic, ASCII "MG". Present so a wrong-version or wrong-service
  /// peer is identifiable before any field is interpreted.
  static const List<int> magic = <int>[0x4D, 0x47];

  /// Contract version this codec implements.
  static const int version = 1;

  /// Bytes before the payload: magic 2 + version 1 + type 1 + flags 1 +
  /// length 2.
  static const int headerBytes = 7;

  /// Largest payload. Bounded well above the largest record (160 B) so the
  /// control frames and any future bulk frame fit without a renegotiation,
  /// and low enough that a desynchronised length cannot make the reader
  /// allocate wildly.
  static const int maxPayload = 512;

  /// Largest complete frame.
  static const int maxFrame = headerBytes + maxPayload;

  /// A connection that has not reached [FrameType.pairOk] within this
  /// window is closed, so a local socket cannot hold the single session
  /// slot forever.
  static const Duration preAuthTimeout = Duration(seconds: 5);

  /// Records the gateway will hold while the radio is unavailable. Also the
  /// credit window: a client may have this many unacked records in flight.
  static const int creditWindow = 8;

  /// Largest opaque record the L2 data plane will carry, as an absolute
  /// ceiling. The *actual* limit is advertised by the gateway in
  /// [FrameType.bindOk] as [GatewayLimits.uplinkRecordMax], because
  /// `cmd_send_raw_data` is `[25][path_len][path][payload]` inside a
  /// 176-byte companion frame and therefore accepts only `174 - path_len`.
  /// A session must size records to the advertised number, not to this
  /// one, or it spends airtime on a send the radio refuses.
  ///
  /// Raw custom carries bytes verbatim: no cipher, no padding, exact
  /// length. That is why the established state needs no delimiter.
  static const int recordMax = 172;

  /// The conservative floor: a 14-hop path still fits a record this size.
  /// A gateway whose path is longer than that cannot carry the profile.
  static const int recordFloor = 160;

  // What a record *contains* is not the carrier's business. A client session
  // layer may reserve a header and a tag inside a record; that arithmetic
  // belongs to that layer, and to no other package. The carrier's only promise
  // is that a record of `recordMax` bytes arrives intact.

  /// Largest opaque record on the flooded discovery path, which uses a
  /// companion binary request (`[0x32][pub_key 32][1 B length][record]`).
  /// Used only until both ends know a path.
  static const int discoveryRecordMax = 142;

  /// Pairing token size in bytes.
  static const int pairingTokenBytes = 16;

  /// `rssi` value meaning "no signal reading available". Signed byte.
  static const int unknownRssi = -128;

  /// `batteryPercent` value meaning "battery level not reported".
  static const int unknownBattery = 0xFF;
}

/// L2 frame types. Values are frozen once shipped; new types are additive
/// and an unknown type is ignored rather than fatal.
extension type const FrameType(int code) {
  static const FrameType hello = FrameType(0x01);
  static const FrameType helloOk = FrameType(0x02);
  static const FrameType helloErr = FrameType(0x03);
  static const FrameType pair = FrameType(0x10);
  static const FrameType pairOk = FrameType(0x11);
  static const FrameType pairErr = FrameType(0x12);
  static const FrameType bind = FrameType(0x20);
  static const FrameType bindOk = FrameType(0x21);
  static const FrameType bindErr = FrameType(0x22);
  static const FrameType record = FrameType(0x30);
  static const FrameType recv = FrameType(0x31);
  static const FrameType sendResult = FrameType(0x32);
  static const FrameType status = FrameType(0x40);
  static const FrameType close = FrameType(0x60);

  /// A short stable name for diagnostics.
  String get name => switch (code) {
        0x01 => 'hello',
        0x02 => 'hello_ok',
        0x03 => 'hello_err',
        0x10 => 'pair',
        0x11 => 'pair_ok',
        0x12 => 'pair_err',
        0x20 => 'bind',
        0x21 => 'bind_ok',
        0x22 => 'bind_err',
        0x30 => 'record',
        0x31 => 'recv',
        0x32 => 'send_result',
        0x40 => 'status',
        0x60 => 'close',
        _ => 'unknown_0x${code.toRadixString(16).padLeft(2, '0')}',
      };
}

/// Gateway capability bits, negotiated in HELLO/HELLO_OK.
///
/// Only capabilities of the *gateway* appear here. Crypto capabilities of the
/// far end are not knowable by a blind carrier and belong inside the session.
extension type const GatewayCapability(int bit) {
  /// The gateway enforces the [GatewayLimits.creditWindow] record window.
  static const GatewayCapability recvCredit = GatewayCapability(0);

  /// The gateway pushes STATUS when the radio state changes.
  static const GatewayCapability statusPush = GatewayCapability(1);

  int get mask => 1 << bit;
}

/// Why a HELLO was refused.
extension type const HelloError(int code) {
  static const HelloError versionMismatch = HelloError(1);
  static const HelloError busy = HelloError(2);

  String get name => switch (code) {
        1 => 'version_mismatch',
        2 => 'busy',
        _ => 'unknown_$code',
      };
}

/// Why a PAIR was refused.
extension type const PairError(int code) {
  static const PairError badToken = PairError(1);
  static const PairError alreadyPaired = PairError(2);
  static const PairError revoked = PairError(3);

  String get name => switch (code) {
        1 => 'bad_token',
        2 => 'already_paired',
        3 => 'revoked',
        _ => 'unknown_$code',
      };
}

/// Why a BIND was refused.
extension type const BindError(int code) {
  /// The peer is not a MeshCore contact on the phone's radio. The remedy is
  /// a user-visible "add contact" action in Settings, not a gateway write.
  static const BindError notAContact = BindError(1);

  static const BindError noPath = BindError(2);

  String get name => switch (code) {
        1 => 'not_a_contact',
        2 => 'no_path',
        _ => 'unknown_$code',
      };
}

/// What the radio did with a record. This is **not** delivery.
///
/// A blind carrier cannot know whether the peer received a record, and must
/// not claim to. These are the firmware's own send outcomes.
extension type const SendOutcome(int code) {
  /// The radio routed the record over a known direct path.
  static const SendOutcome sentDirect = SendOutcome(1);

  /// The radio flooded the record.
  static const SendOutcome sentFlood = SendOutcome(2);

  /// The peer is not a contact (`ERR_CODE_NOT_FOUND`).
  static const SendOutcome errNotFound = SendOutcome(3);

  /// The radio had no free packet (`ERR_CODE_TABLE_FULL`).
  static const SendOutcome errBusy = SendOutcome(4);

  /// The record exceeded the carrier's budget (refused before sending).
  static const SendOutcome errTooLong = SendOutcome(5);

  /// No answer arrived in time. For a raw-data send the firmware replies
  /// only OK or ERR (no `est_timeout`), so the deadline is the sender's own.
  /// The firmware's estimate elapsed with no response (binary request). Not proof of loss:
  /// the estimate is airtime plus hops, and cannot see collisions.
  static const SendOutcome localTimeout = SendOutcome(6);

  String get name => switch (code) {
        1 => 'sent_direct',
        2 => 'sent_flood',
        3 => 'err_not_found',
        4 => 'err_busy',
        5 => 'err_too_long',
        6 => 'local_timeout',
        _ => 'unknown_$code',
      };
}

/// Radio state reported in STATUS.
///
/// A `STATUS` frame cannot omit a field, so a value the gateway cannot read
/// yet is sent as an explicit sentinel rather than a plausible-looking zero:
/// `rssi == -128` (the wire byte `0x80`) means "no reading", and
/// `batteryPercent == 0xFF` means "unknown". A client must not render either
/// as a measurement. Both round-trip through [GatewayMessages.status] and
/// [GatewayMessages.readStatus], which treat rssi as a signed byte.
extension type const RadioState(int code) {
  static const RadioState connected = RadioState(0);
  static const RadioState disconnected = RadioState(1);
  static const RadioState radioLost = RadioState(2);
  static const RadioState noContact = RadioState(3);

  String get name => switch (code) {
        0 => 'connected',
        1 => 'disconnected',
        2 => 'radio_lost',
        3 => 'no_contact',
        _ => 'unknown_$code',
      };
}

/// Why a connection is being closed.
extension type const CloseReason(int code) {
  static const CloseReason protocol = CloseReason(1);
  static const CloseReason version = CloseReason(2);
  static const CloseReason busy = CloseReason(3);
  static const CloseReason preAuthTimeout = CloseReason(4);
  static const CloseReason shutdown = CloseReason(5);

  String get name => switch (code) {
        1 => 'protocol',
        2 => 'version',
        3 => 'busy',
        4 => 'preauth_timeout',
        5 => 'shutdown',
        _ => 'unknown_$code',
      };
}
