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
