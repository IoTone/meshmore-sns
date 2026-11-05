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
extension type const SendOutcome(int code) {
  /// The radio accepted the record and routed it over the contact's path.
  static const SendOutcome sentDirect = SendOutcome(1);

  /// The radio refused it: the contact is unknown to it, or has no direct
  /// route, so there was nowhere to send ([MeshcoreErrorCode.notFound]).
  static const SendOutcome errNotFound = SendOutcome(2);

  /// The radio had no free packet, or refused for any other reason. Every
  /// other ERR is also "the radio did not transmit".
  static const SendOutcome errBusy = SendOutcome(3);

  /// Refused here, before the radio saw it: the record does not fit the
  /// contact's path (`MeshCarryLimits.rawDataPayloadMax`), or is under the
  /// 4-byte raw-data minimum.
  static const SendOutcome errTooLong = SendOutcome(4);

  /// Written to the radio, no answer inside the deadline. The radio may have
  /// transmitted, so it must be charged for.
  static const SendOutcome localTimeout = SendOutcome(5);

  String get name => switch (code) {
        1 => 'sent_direct',
        2 => 'err_not_found',
        3 => 'err_busy',
        4 => 'err_too_long',
        5 => 'local_timeout',
        _ => 'unknown_$code',
      };
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
  }) {
    _frames = _mc.inboundFrames.listen(_onFrame);
  }

  final MeshcoreController _mc;

  /// How long to wait for the radio's OK/ERR before reporting
  /// [SendOutcome.localTimeout].
  final Duration answerTimeout;

  late final StreamSubscription<MeshcoreInbound> _frames;
  Future<void> _tail = Future<void>.value();
  Completer<MeshcoreInbound>? _awaiting;
  bool _disposed = false;

  /// The largest record [to]'s path leaves room for: `174 - path_len`, the
  /// frame ceiling minus the opcode, the length byte and the path.
  static int recordMaxFor(Contact to) =>
      MeshCarryLimits.rawDataPayloadMax((to.directPath ?? Uint8List(0)).length);

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
    final Completer<MeshcoreInbound> answer = Completer<MeshcoreInbound>();
    _awaiting = answer;
    try {
      await _mc.sendRawCommand(frame);
      final MeshcoreInbound reply = await answer.future.timeout(answerTimeout);
      if (reply is OkFrame) return SendOutcome.sentDirect;
      final int? code = (reply as ErrorFrame).code;
      if (code == MeshcoreErrorCode.notFound.code) {
        return SendOutcome.errNotFound;
      }
      // table_full is "no free packet". Every other refusal is also
      // "the radio did not transmit"; errBusy is the closest outcome.
      return SendOutcome.errBusy;
    } on TimeoutException {
      _mc.abandonRawSend();
      // The frame was written, so the radio may have transmitted. The caller
      // charges localTimeout for that reason.
      return SendOutcome.localTimeout;
    } finally {
      if (identical(_awaiting, answer)) _awaiting = null;
    }
  }

  void _onFrame(MeshcoreInbound f) {
    if (f is OkFrame || f is ErrorFrame) {
      final Completer<MeshcoreInbound>? a = _awaiting;
      if (a != null && !a.isCompleted) a.complete(f);
    }
  }

  static String _hex(List<int> b) =>
      b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

  /// Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _frames.cancel();
  }
}
