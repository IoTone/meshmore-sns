// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'gf256.dart';

/// The media transfer's forward-error-correction block.
///
/// A block is 20 payload chunks plus parity, per the register's transport
/// ruling. The parity count is the loss the transfer is designed to absorb
/// without a round trip:
///
/// * images — 2 repair chunks over 20 data chunks (~10 %);
/// * voice — 3 over 20 (~15 %), because a recorded voice message that loses
///   one of twenty packets has lost the message.
///
/// This is an **erasure** code: the receiver knows which indexes are missing
/// from the reassembler's bitmap, so it repairs exactly those instead of
/// hunting for unknown error positions. That is why the decoder does not
/// carry a Berlekamp-Massey step — the price of it is that a chunk with the
/// wrong bytes is not repaired, it is rejected by its own CRC and treated as
/// an erasure.
///
/// Each byte offset of the block is a separate codeword: chunk *i* supplies
/// symbol *i* of every codeword, and parity chunk *j* carries the codewords'
/// j-th evaluation point. A codeword lives in GF(256) under polynomial 0x11D
/// with generator 2, and is evaluated at `alpha^i`, so a block cannot exceed
/// 255 chunks.
final class MediaFec {
  MediaFec({Gf256? field}) : _gf = field ?? Gf256();

  final Gf256 _gf;

  /// Data chunks in one block.
  static const int blockData = 20;

  static const int imageParity = 2;
  static const int voiceParity = 3;

  static int parityFor(MediaKindLike kind) => switch (kind) {
        MediaKindLike.image => imageParity,
        MediaKindLike.voice => voiceParity,
      };

  /// Parity chunks for [data], each the same length as its inputs. Refuses a
  /// block longer than [blockData] rather than silently repairing less than
  /// it claims.
  List<Uint8List> encode(List<Uint8List> data, {required int parity}) {
    if (data.isEmpty) {
      throw ArgumentError.value(data, 'data', 'needs at least one chunk');
    }
    if (data.length > blockData) {
      throw ArgumentError.value(
          data.length, 'data', 'a block holds at most $blockData chunks');
    }
    if (parity < 1 || parity > 16) {
      throw ArgumentError.value(parity, 'parity', 'must be 1..16');
    }
    final int len = data.first.length;
    for (final Uint8List d in data) {
      if (d.length != len) {
        throw ArgumentError('every chunk in a block must be the same length');
      }
    }
    final List<int> xs = <int>[
      for (int i = 0; i < data.length; i++) _gf.alpha(i),
    ];
    final List<Uint8List> out = <Uint8List>[
      for (int p = 0; p < parity; p++) Uint8List(len),
    ];
    for (int offset = 0; offset < len; offset++) {
      final List<int> ys = <int>[
        for (final Uint8List d in data) d[offset],
      ];
      for (int p = 0; p < parity; p++) {
        out[p][offset] = _gf.interpolate(
          xs: xs,
          ys: ys,
          at: _gf.alpha(data.length + p),
        );
      }
    }
    return out;
  }

  /// Repairs up to [parity] missing indexes in a block of
  /// `data.length + parity` slots. `slots` holds nulls where a chunk did not
  /// arrive; the returned block has every hole filled, or null when the
  /// holes outnumber the parity.
  List<Uint8List>? repair({
    required List<Uint8List?> slots,
    required int dataCount,
    required int parity,
  }) {
    final int total = dataCount + parity;
    if (slots.length != total) {
      throw ArgumentError.value(
          slots.length, 'slots', 'expected $total slots for this block');
    }
    final int holed = slots.where((Uint8List? s) => s == null).length;
    if (holed == 0) return <Uint8List>[for (final Uint8List? s in slots) s!];
    if (holed > parity) return null;
    final int len = slots.firstWhere((Uint8List? s) => s != null)!.length;
    final List<int> knownX = <int>[];
    final List<int> knownAt = <int>[];
    for (int i = 0; i < total; i++) {
      if (slots[i] != null) {
        knownX.add(i);
        knownAt.add(_gf.alpha(i));
      }
    }
    if (knownX.length < dataCount) return null;
    final List<Uint8List> out = <Uint8List>[
      for (int i = 0; i < total; i++) slots[i] ?? Uint8List(len),
    ];
    for (int i = 0; i < total; i++) {
      if (slots[i] != null) continue;
      final int at = _gf.alpha(i);
      for (int offset = 0; offset < len; offset++) {
        final List<int> ys = <int>[
          for (int k = 0; k < knownX.length; k++) slots[knownX[k]]![offset],
        ];
        out[i][offset] = _gf.interpolate(xs: knownAt, ys: ys, at: at);
      }
    }
    return out;
  }
}

/// The two payload classes the FEC block sizes are chosen for. Separate from
/// [MediaKind] so this file has no dependency on the wire layout.
enum MediaKindLike { image, voice }
