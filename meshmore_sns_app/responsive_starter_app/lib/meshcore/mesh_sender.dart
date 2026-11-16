// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';

import 'meshcore_controller.dart';

/// What the radio did with a record sent as a direct raw-data packet.
///
/// This is **not** delivery. The firmware answers a raw-data send with a bare
/// OK or ERR and carries no acknowledgement from the peer, so the outcome says
/// only what the radio itself did with the bytes.
///
/// A refusal keeps the firmware's own code, because the codes mean different
/// things to the person reading it (`ERR_CODE_TABLE_FULL` is capacity and
/// clears, `ERR_CODE_NOT_FOUND` is a route the radio does not have). The one
/// case with no code is the app's own: a contact it cannot address never
/// reaches the radio at all.
enum SendOutcomeKind {
  /// The radio accepted the record and routed it over the contact's path.
  accepted,

  /// Refused here, before the radio saw it: the app does not hold the contact,
  /// or the contact has no direct route, and a raw record cannot be flooded.
  noRoute,

  /// The radio answered `RESP_CODE_ERR`; [SendOutcome.firmwareCode] says why.
  refusedByRadio,

  /// Refused here, before the radio saw it: the record does not fit the
  /// contact's path (`MeshCarryLimits.rawDataPayloadMax`), or is under the
  /// 4-byte raw-data minimum.
  tooLong,

  /// Written to the radio, no answer inside the deadline. The radio may have
  /// transmitted, so it must be charged for.
  noAnswer,
}

final class SendOutcome {
  const SendOutcome(this.kind, {this.firmwareCode});

  /// A refusal the radio itself reported.
  const SendOutcome.refused(int this.firmwareCode)
      : kind = SendOutcomeKind.refusedByRadio;

  final SendOutcomeKind kind;

  /// The `RESP_CODE_ERR` code when the radio answered; null otherwise.
  final int? firmwareCode;

  static const SendOutcome sentDirect = SendOutcome(SendOutcomeKind.accepted);
  static const SendOutcome errNotFound = SendOutcome(SendOutcomeKind.noRoute);
  static const SendOutcome errTooLong = SendOutcome(SendOutcomeKind.tooLong);
  static const SendOutcome localTimeout = SendOutcome(SendOutcomeKind.noAnswer);

  /// `ERR_CODE_TABLE_FULL` (`MeshcoreErrorCode.tableFull`): no free packet.
  /// Capacity, not a lost record.
  static const SendOutcome errBusy = SendOutcome.refused(3);

  String get name => switch (kind) {
        SendOutcomeKind.accepted => 'sent_direct',
        SendOutcomeKind.noRoute => 'err_not_found',
        SendOutcomeKind.refusedByRadio =>
          'err_${firmwareCode ?? 'unknown'}',
        SendOutcomeKind.tooLong => 'err_too_long',
        SendOutcomeKind.noAnswer => 'local_timeout',
      };

  @override
  bool operator ==(Object other) =>
      other is SendOutcome &&
      other.kind == kind &&
      other.firmwareCode == firmwareCode;

  @override
  int get hashCode => Object.hash(kind, firmwareCode);

  @override
  String toString() => 'SendOutcome($name)';
}

/// Sends one opaque record to a contact as a direct raw-data packet
/// (`CMD_SEND_RAW_DATA`, `0x19`).
///
/// This is the app's own send path for bytes the chat layer does not compose:
/// the caller supplies the record and the contact it is addressed to, and gets
/// back what the radio did with it. The frame is
/// `[0x19][path_len][path][payload]`, so the record's budget depends on that
/// contact's path ([recordMaxFor]) — the firmware refuses the whole frame
/// otherwise.
///
/// Facts that shape this class, all from the firmware's handler:
///  * The firmware answers with a bare **OK** or **ERR**, never
///    `RESP_CODE_SENT`, so the outcome is read from those two frames. They are
///    registered through [MeshcoreController.sendRawCommand] so an OK cannot be
///    credited to a chat message waiting for its own.
///  * `path_len` is a byte count. [Contact.directPath] is that count, not the
///    raw `out_path_len` byte, which packs the hash size in its top two bits
///    (`Packet.cpp:20-30`); 0xFF means "no route".
///  * Raw data heard by the radio is pushed as `PUSH_CODE_RAW_DATA` while an app
///    is connected and carries no sender (`MyMesh.cpp:801-818`); the controller
///    already dispatches those frames, so nothing is read here.
///
/// Sends are serialised: the firmware's OK/ERR carries no correlation tag, so
/// two in flight could not be told apart.
class MeshcoreMeshSender {
  MeshcoreMeshSender(
    this._mc, {
    this.answerTimeout = const Duration(seconds: 5),
  });

  final MeshcoreController _mc;

  /// How long to wait for the radio's OK/ERR before reporting
  /// [SendOutcome.localTimeout].
  final Duration answerTimeout;

  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  /// The largest record a radio will **report upward**: 171.
  ///
  /// The firmware's receive-log push refuses a frame it cannot fit in
  /// `MAX_FRAME_SIZE` 176 — it needs three bytes of push header on top of the
  /// received packet (`MyMesh.cpp`, `logRxRaw`) — so a 172-byte record is
  /// transmitted, received, and never reported to either side. That is silent
  /// and repeats on every full record. The other radio project found it first
  /// and made it a constant (`ldmux`, `crates/mesh/src/constants.rs`,
  /// `RECORD_RECEIVED_MAX`): the sender's own ceiling is per path, because the
  /// packet it builds carries the path, but it is capped by the receiver's.
  static const int recordReceivedMax = 171;

  /// The largest record [to]'s path leaves room for: `174 - path_len`, the
  /// frame ceiling minus the opcode, the length byte and the path — capped at
  /// [recordReceivedMax], the most a radio will hand up the other end.
  static int recordMaxFor(Contact to) {
    final int byPath = MeshCarryLimits.rawDataPayloadMax(
        (to.directPath ?? Uint8List(0)).length);
    return byPath < recordReceivedMax ? byPath : recordReceivedMax;
  }

  /// Bytes the radio puts on air around the record: the MeshCore packet header
  /// and the path, which are not part of [record]. A meter that counts only
  /// the record under-counts every transmission.
  static int airtimeOverheadFor(Contact to) =>
      2 + (to.directPath ?? Uint8List(0)).length;

  /// Send [record] to [to] as one direct raw-data packet.
  ///
  /// Returns [SendOutcome.errNotFound] when the contact has no direct route:
  /// a raw-data packet cannot be flooded, only addressed.
  Future<SendOutcome> sendRecord(Uint8List record, {required Contact to}) {
    final Future<SendOutcome> result = _tail.then((_) => _send(record, to));
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<SendOutcome> _send(Uint8List record, Contact to) async {
    // Re-read the path per send: the radio may have learned a route since the
    // caller read the contact.
    final Uint8List? path = _mc.contactRecordFor(_hex(to.publicKey))?.directPath;
    if (path == null) return SendOutcome.errNotFound;
    final Uint8List frame;
    try {
      frame = MeshCarryCodec.sendRawData(path: path, payload: record);
    } on MeshCarryLengthError {
      return SendOutcome.errTooLong;
    } on ArgumentError {
      return SendOutcome.errTooLong; // under the 4-byte raw-data minimum
    }
    try {
      final MeshcoreInbound reply =
          await _mc.sendRawCommand(frame).timeout(answerTimeout);
      if (reply is OkFrame) return SendOutcome.sentDirect;
      final int? code = (reply as ErrorFrame).code;
      // The radio's own code travels: table_full is capacity and clears,
      // not_found is a route the radio does not have, and the rest are the
      // firmware's enum. The caller decides how to say it.
      return code == null
          ? const SendOutcome(SendOutcomeKind.refusedByRadio)
          : SendOutcome.refused(code);
    } on TimeoutException {
      _mc.abandonRawSend();
      // The frame was written, so the radio may have transmitted. The caller
      // charges localTimeout for that reason.
      return SendOutcome.localTimeout;
    }
  }

  static String _hex(List<int> b) =>
      b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

  /// Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

  }
}
