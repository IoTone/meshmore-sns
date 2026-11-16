// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'mp1.dart';

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

/// One record of a picture in flight, in MeshPix's chunk framing.
///
/// A raw record has no data type, so the record carries its own header — and it
/// carries **MeshPix's**, not an app-private one: the same six bytes a preview
/// carries, with kind = chunk, then `seq` and `total`, then the slice. Their
/// reader can reassemble our picture and we can reassemble theirs, which is the
/// only reason to implement MP1 at all.
///
/// A slice is at most 155 bytes, which is what fits a 163-byte channel
/// datagram. A raw record has more room (184 bytes), and staying at 155 keeps
/// one record valid on either frame.
abstract final class MediaFetchCodec {
  /// The largest slice one record carries.
  static const int sliceBytes = kMp1ChunkMaxSlice;

  static List<Uint8List> split({
    required int id,
    required Uint8List payload,
  }) =>
      encodeMp1Chunks(transferId: id, payload: payload);

  static ({int id, int index, int total, Uint8List slice})? decode(
      Uint8List bytes) {
    final ({int transferId, int seq, int total, Uint8List slice})? c =
        decodeMp1Chunk(bytes);
    if (c == null) return null;
    return (id: c.transferId, index: c.seq, total: c.total, slice: c.slice);
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
