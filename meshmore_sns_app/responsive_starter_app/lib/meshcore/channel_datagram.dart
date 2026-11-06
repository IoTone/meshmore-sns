// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';

/// One channel datagram as it arrived (`RESP_CODE_CHANNEL_DATA_RECV`,
/// `0x1B`).
///
/// This is the app's view of the frame: which channel slot it landed on,
/// what the sender typed it as, and the bytes. Nothing interprets the
/// blob here — that belongs to whatever layer owns the type — but the
/// type is kept even when this build has never heard of it, because the
/// firmware forwards unknown types rather than dropping them
/// (`MyMesh.cpp:592-625`).
class ChannelDatagram {
  const ChannelDatagram({
    required this.channelIndex,
    required this.dataType,
    required this.blob,
    required this.rxVia,
    required this.snrDb,
    required this.pathLen,
    required this.receivedAt,
  });

  final int channelIndex;
  final int dataType;
  final Uint8List blob;
  final RxVia rxVia;
  final double snrDb;

  /// Raw `path_len` byte as the radio reported it; `0xFF` means it was
  /// flooded (`MyMesh.cpp:608`).
  final int pathLen;

  final DateTime receivedAt;

  bool get isFlood => pathLen == kPathLenFlood;

  /// The blob's budget as the radio measures it: `MAX_FRAME_SIZE` minus the
  /// push header, `MyMesh.cpp:594`.
  static int get maxBlobBytes => ChannelDataLimits.firmwareFramePayloadMax;

  int get byteCount => blob.length;

  @override
  String toString() => 'ChannelDatagram(ch $channelIndex, type '
      '0x${dataType.toRadixString(16)}, ${blob.length} B, ${rxVia.name})';
}

/// What the radio did with a datagram the app handed it.
///
/// The radio answers `CMD_SEND_CHANNEL_DATA` with a bare OK or ERR
/// (`MyMesh.cpp:1158-1189`), never `RESP_CODE_SENT`, so this says what the
/// radio accepted — not what any peer received.
enum ChannelDataSendStatus {
  /// The radio took the datagram and put it on air.
  accepted,

  /// Refused here, before the radio saw it: the blob or the path did not
  /// fit. [ChannelDataSendResult.refusal] says which budget bound.
  refusedLocally,

  /// The radio refused it ([ChannelDataSendResult.errorCode] carries the
  /// firmware's code, e.g. `ERR_CODE_NOT_FOUND` for a bad channel slot).
  refusedByRadio,

  /// Written to the radio with no answer inside the deadline. The radio may
  /// have transmitted, so a caller that meters airtime must still charge it.
  noAnswer,

  /// Refused by this app's own duty-cycle meter before the radio saw it.
  /// Distinct from [notReady] because it is this app's budget, not the link:
  /// the caller can say "you are over this hour's allowance" and wait, rather
  /// than blaming the connection.
  refusedAirtime,

  /// The link is not ready; nothing was written.
  notReady,
}

/// The outcome of one channel-datagram send.
class ChannelDataSendResult {
  const ChannelDataSendResult(this.status, {this.refusal, this.errorCode});

  final ChannelDataSendStatus status;
  final ChannelDataRefusal? refusal;
  final int? errorCode;

  bool get accepted => status == ChannelDataSendStatus.accepted;

  @override
  String toString() => 'ChannelDataSendResult(${status.name}'
      '${refusal == null ? '' : ', ${refusal!.name}'}'
      '${errorCode == null ? '' : ', err $errorCode'})';
}
