// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'constants.dart';

/// Why a channel datagram was refused before it reached the radio.
///
/// Every one of these is a refusal the radio would also make, but with a
/// poorer answer: an over-long blob comes back as `ERR_CODE_TABLE_FULL`,
/// which reads as "no free packet" and sends the caller looking at the
/// queue instead of the payload. Refusing here keeps the reason.
enum ChannelDataRefusal {
  /// `DATA_TYPE_RESERVED` (0x0000) — the firmware answers
  /// `ERR_CODE_ILLEGAL_ARG` (`MyMesh.cpp:1180`).
  reservedType,

  /// The blob is larger than the datagram can carry at all
  /// ([ChannelDataLimits.maxBlob]).
  blobTooLongForDatagram,

  /// The blob fits the datagram but not once this send's path bytes are
  /// added to the same frame.
  blobTooLongForFrame,

  /// The `path_len` byte is one the firmware refuses: a reserved hash size
  /// or a path longer than `MAX_PATH_SIZE` (`Packet.cpp:17-22`).
  invalidPathLen,

  /// The `path_len` byte and the path bytes disagree about the hop count
  /// or hash size, so the radio would read the data type from the middle
  /// of the path.
  pathLengthMismatch,

  /// Channel index does not fit one byte.
  channelOutOfRange,

  /// Data type does not fit the 2-byte field.
  dataTypeOutOfRange,
}

/// A channel datagram that was built with arguments the radio would refuse.
///
/// Carries the numbers so a caller can show what it tried: the refusal, the
/// offending value and the maximum the budget allows.
class ChannelDataException implements Exception {
  const ChannelDataException(
    this.refusal, {
    required this.field,
    required this.actual,
    required this.maximum,
  });

  final ChannelDataRefusal refusal;
  final String field;
  final int actual;
  final int maximum;

  @override
  String toString() => 'ChannelDataException(${refusal.name}: '
      '$field is $actual, maximum $maximum)';
}
