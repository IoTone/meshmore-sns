// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

/// The seam between an announcement and the pixels, for both ends.
///
/// One rule decides everything here: **pixels are never broadcast**. The
/// announcement is one 163-byte MP1 preview on the channel, and the pixels
/// travel as `CMD_SEND_RAW_DATA` records to one contact, over the path the radio
/// already knows. The firmware enforces it — a raw record with no path is
/// answered `ERR_CODE_UNSUPPORTED_CMD` (`MyMesh.cpp:1519-1533`) — so the app
/// cannot flood a picture even by accident.
///
/// Because a channel preview carries no sender (a channel datagram is
/// anonymous), the request names the requester rather than the sender:
///
/// ```text
/// [IMG1:<id>:<pubkey hex, first 8 bytes>]
/// ```
///
/// The requester knows its own key, so the sender can address the reply to it.
/// A reader who is not running this app sees one short channel line, and a
/// reader who is sees a request.
abstract final class MediaFetchRequest {
  static const String _prefix = '[IMG1:';

  static String encode(int id, String requesterPubKeyHex) =>
      '$_prefix$id:${_short(requesterPubKeyHex)}]';

  /// The id the preview carried, and the key to send the answer to.
  ///
  /// Null when the line is not a request, which is the common case: every
  /// channel message passes through this.
  static ({int id, String requesterHex})? decode(String text) {
    final String t = text.trim();
    if (!t.startsWith(_prefix) || !t.endsWith(']')) return null;
    final String body = t.substring(_prefix.length, t.length - 1);
    final List<String> parts = body.split(':');
    if (parts.length != 2) return null;
    final int? id = int.tryParse(parts[0]);
    if (id == null || id < 0 || id > 0xFFFF) return null;
    final String hex = parts[1].toLowerCase();
    if (hex.length != 16 || !RegExp(r'^[0-9a-f]+$').hasMatch(hex)) return null;
    return (id: id, requesterHex: hex);
  }

  /// The first eight bytes of a public key, which is what a request carries.
  ///
  /// Eight bytes rather than six: a channel message already spends a byte
  /// budget, and eight is what this app uses to address a direct message, so a
  /// requester's key identifies it the same way here as everywhere else.
  static String shortKey(String pubKeyHex) => _short(pubKeyHex);

  static String _short(String hex) {
    final String h = hex.toLowerCase();
    return h.length <= 16 ? h.padRight(16, '0') : h.substring(0, 16);
  }
}

/// One record of a picture in flight.
///
/// `0x19` is a frame rather than a data type, so each record carries its own
/// seven-byte header: `'M','F'`, version, the chunk index, the offer id (2
/// bytes) and how many chunks there are. That is enough for the receiver to place a chunk
/// without holding the rest, and enough to ask for the missing indices rather
/// than the whole picture again.
abstract final class MediaFetchCodec {
  static const int _magic0 = 0x4D; // 'M'
  static const int _magic1 = 0x46; // 'F'
  static const int _version = 1;
  static const int headerBytes = 7;

  /// The largest slice one raw record can carry, after its own header.
  ///
  /// `CMD_SEND_RAW_DATA` carries at most 184 bytes (`MAX_PACKET_PAYLOAD`), so a
  /// slice is 177.
  static const int sliceBytes = 184 - headerBytes;

  static Uint8List encode({
    required int id,
    required int index,
    required int total,
    required Uint8List slice,
  }) {
    if (slice.length > sliceBytes) {
      throw ArgumentError.value(
          slice.length, 'slice', 'a raw record carries at most $sliceBytes');
    }
    if (index < 0 || index > 0xFF || total < 1 || total > 0xFF) {
      throw ArgumentError('index/total out of range');
    }
    final Uint8List out = Uint8List(headerBytes + slice.length);
    out[0] = _magic0;
    out[1] = _magic1;
    out[2] = _version;
    out[3] = index;
    out[4] = id & 0xFF;
    out[5] = (id >> 8) & 0xFF;
    out[6] = total;
    out.setRange(headerBytes, out.length, slice);
    return out;
  }

  /// A record, or null when the bytes are not one.
  static ({int id, int index, int total, Uint8List slice})? decode(
      Uint8List bytes) {
    if (bytes.length <= headerBytes) return null;
    if (bytes[0] != _magic0 || bytes[1] != _magic1 || bytes[2] != _version) {
      return null;
    }
    final int index = bytes[3];
    final int id = bytes[4] | (bytes[5] << 8);
    final int total = bytes[6];
    if (total == 0 || index >= total) return null;
    return (
      id: id,
      index: index,
      total: total,
      slice: Uint8List.sublistView(bytes, headerBytes),
    );
  }

  /// Splits [payload] into records of at most [sliceBytes], with headers.
  static List<Uint8List> split({required int id, required Uint8List payload}) {
    final int total = (payload.length + sliceBytes - 1) ~/ sliceBytes;
    if (total == 0 || total > 0xFF) {
      throw ArgumentError.value(
          payload.length, 'payload', 'a record set is 1..255 chunks');
    }
    return <Uint8List>[
      for (int i = 0; i < total; i++)
        encode(
          id: id,
          index: i,
          total: total,
          slice: Uint8List.sublistView(
            payload,
            i * sliceBytes,
            (i + 1) * sliceBytes > payload.length
                ? payload.length
                : (i + 1) * sliceBytes,
          ),
        ),
    ];
  }
}

/// A picture being reassembled from records that arrived out of order.
final class MediaFetchInbox {
  MediaFetchInbox({required this.id, required this.total});

  final int id;
  final int total;
  final Map<int, Uint8List> _parts = <int, Uint8List>{};

  int get received => _parts.length;

  bool get complete => _parts.length == total;

  /// The indices still missing, ascending. What a re-request asks for.
  List<int> get missing {
    final List<int> out = <int>[];
    for (int i = 0; i < total; i++) {
      if (!_parts.containsKey(i)) out.add(i);
    }
    return out;
  }

  /// Takes one record. Returns true when it was new, so a duplicate costs
  /// nothing but the comparison.
  bool take(int index, Uint8List slice) {
    if (index < 0 || index >= total || _parts.containsKey(index)) return false;
    _parts[index] = slice;
    return true;
  }

  /// The payload, in order. Only valid when [complete].
  Uint8List assemble() {
    if (!complete) throw StateError('incomplete: ${missing.length} missing');
    final BytesBuilder b = BytesBuilder(copy: false);
    for (int i = 0; i < total; i++) {
      b.add(_parts[i]!);
    }
    return b.takeBytes();
  }
}
