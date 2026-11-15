// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
//
// The AEIC on-air framing, ported from MeshCore Open
// (`lib/services/image_chunk_transport.dart`, MIT, Copyright (c) 2025 zjs81).
// The constants and the metadata-byte layout are that project's and are not ours
// to change: a client that disagrees by one bit shows a picture stretched the
// wrong way or refuses the stream outright.
//
// What it is: a MeshCore Open client sends an AEIC bitstream on a channel as
// `CMD_SEND_CHANNEL_DATA` (0x3E) with data type `0xAE1C`, split into blobs of at
// most 163 bytes. Each blob carries a 4-byte header (2 bytes of the sender's key,
// an 8-bit image id, and one byte holding the index and the total), then a body.
// Chunk 0's body opens with one metadata byte, so it carries 157 bytes of
// picture; every later chunk carries 158. One XOR parity blob may follow, which
// recovers exactly one lost chunk — GRP_DATA is unacknowledged, so this is the
// only repair available without a request round trip.
//
// The numbers, measured on a 26-image corpus at the shipping rate point (ft32):
// 155.8 bytes mean, 110 minimum, 209 maximum. That is one or two data chunks, so
// two or three packets on the air for a 512x512 photograph.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The data type that names an AEIC picture stream.
const int kAeicImageDataType = 0xAE1C;

/// The largest blob that fits every transport: 172-byte frame minus the 9-byte
/// response header, which is the smallest of the five binding limits.
const int kAeicChunkBlobBytes = 163;

/// Per-chunk header: sender prefix (2) + image id (1) + index/total (1).
const int kAeicChunkHeaderBytes = 4;

/// The parity blob spends one body byte on the XOR of the data body lengths.
const int kAeicParityLengthBytes = 1;

/// Body bytes in any blob.
const int kAeicChunkBodyBytes =
    kAeicChunkBlobBytes - kAeicChunkHeaderBytes - kAeicParityLengthBytes;

/// Picture bytes carried by chunk 0 (its body minus the metadata byte).
const int kAeicFirstChunkCapacity = kAeicChunkBodyBytes - 1;

/// Picture bytes carried by every chunk after chunk 0.
const int kAeicChunkCapacity = kAeicChunkBodyBytes;

/// `total` is four bits and must be at least one.
const int kAeicMaxDataChunks = 15;

/// The largest bitstream this framing can carry.
const int kAeicMaxPayloadBytes =
    kAeicFirstChunkCapacity + (kAeicMaxDataChunks - 1) * kAeicChunkCapacity;

/// How long a partially received picture is kept before it is abandoned.
const Duration kAeicReassemblyTtl = Duration(seconds: 60);

/// The quality point this build encodes and decodes.
///
/// ft32 is the shipping point: a 512x512 picture in about 156 bytes. The wire
/// code is deliberately *not* an enum ordinal — see [AeicRatePoint].
enum AeicRate { standard, high }

/// Wire code for ft32 in the low two bits of the metadata byte.
const int kAeicRateWireStandard = 0;

/// Wire code for ft16, reserved and not shipping.
///
/// Kept allocated so a build that decodes ft16 and a build that only sends ft32
/// agree on the nibble instead of disagreeing silently.
const int kAeicRateWireHigh = 1;

int aeicRateWireCode(AeicRate rate) => switch (rate) {
      AeicRate.standard => kAeicRateWireStandard,
      AeicRate.high => kAeicRateWireHigh,
    };

/// The inverse of [aeicRateWireCode], or null for a code this build cannot name.
AeicRate? aeicRateFromWireCode(int code) => switch (code) {
      kAeicRateWireStandard => AeicRate.standard,
      kAeicRateWireHigh => AeicRate.high,
      _ => null,
    };

/// Square sizes addressable by the 2-bit resolution code. Index is the code.
const List<int> kAeicResolutionCodes = <int>[512, 256, 768, 1024];

/// Source aspect ratios addressable by the 4-bit aspect code, as `w:h`.
///
/// The codec encodes a 512x512 *square*: the whole frame is stretched to fit, so
/// nothing is cropped, and the stretch cannot be inverted from the pixels alone.
/// The sender names the original shape here and the receiver letterboxes back to
/// it. Code 0 is 1:1, code 15 is "unknown" and is rendered square.
const List<List<int>> kAeicAspectCodes = <List<int>>[
  <int>[1, 1], // 0
  <int>[5, 4], // 1
  <int>[4, 3], // 2
  <int>[3, 2], // 3
  <int>[16, 10], // 4
  <int>[16, 9], // 5
  <int>[2, 1], // 6
  <int>[21, 9], // 7
  <int>[4, 5], // 8
  <int>[3, 4], // 9
  <int>[2, 3], // 10
  <int>[10, 16], // 11
  <int>[9, 16], // 12
  <int>[1, 2], // 13
  <int>[9, 21], // 14
  <int>[1, 1], // 15, unknown
];

/// The code that means "no shape was named"; the receiver draws it square.
const int kAeicAspectUnknown = 15;

/// The [kAeicAspectCodes] entry closest to `width / height` in log space, so
/// 4:3 and 3:4 are equally far from square.
///
/// Returns [kAeicAspectUnknown] outside roughly 21:9..9:21 rather than snapping a
/// panorama onto 21:9 and letterboxing it wrongly — a square render is honest
/// about not knowing, a wrong one is not.
int aeicAspectCodeFor(int width, int height) {
  if (width <= 0 || height <= 0) return kAeicAspectUnknown;
  final double target = math.log(width / height);
  int best = kAeicAspectUnknown;
  double bestErr = double.infinity;
  for (int i = 0; i < kAeicAspectCodes.length; i++) {
    if (i == kAeicAspectUnknown) continue; // duplicate of 1:1
    final List<int> e = kAeicAspectCodes[i];
    final double err = (math.log(e[0] / e[1]) - target).abs();
    if (err < bestErr) {
      bestErr = err;
      best = i;
    }
  }
  return bestErr <= 0.18 ? best : kAeicAspectUnknown;
}

/// The chunk-0 metadata byte: `aspect(4) | resolution(2) | rate(2)`.
///
/// Repacked from a 4+4 layout that had two spare resolution bits, so the aspect
/// fitted without widening the byte. It must not widen: the measured mean sits
/// just under chunk 0's 157-byte capacity, and one more byte there turns half of
/// all pictures from two packets into three.
class AeicStreamMetadata {
  const AeicStreamMetadata({
    required this.rate,
    this.squareSize = 512,
    this.aspectCode = 0,
  });

  final AeicRate rate;
  final int squareSize;
  final int aspectCode;

  /// The original `width / height`, or 1.0 when the sender said "unknown".
  double get aspectRatio {
    final List<int> e = kAeicAspectCodes[aspectCode & 0x0F];
    return e[0] / e[1];
  }

  bool get isSquare => aspectCode == 0 || aspectCode == 15;

  int encode() {
    final int code = kAeicResolutionCodes.indexOf(squareSize);
    if (code < 0) {
      throw ArgumentError.value(squareSize, 'squareSize',
          'not representable; must be one of $kAeicResolutionCodes');
    }
    return ((aspectCode & 0x0F) << 4) |
        ((code & 0x03) << 2) |
        (aeicRateWireCode(rate) & 0x03);
  }

  /// Decodes the byte, or null when it names a rate or a size this build does
  /// not know.
  ///
  /// Never falls back to a default rate: an unknown code means the sender runs a
  /// format we cannot decode, and guessing `standard` would feed the wrong model
  /// a bitstream it will happily turn into garbage.
  static AeicStreamMetadata? decode(int byte) {
    final AeicRate? rate = aeicRateFromWireCode(byte & 0x03);
    final int resCode = (byte >> 2) & 0x03;
    if (rate == null || resCode >= kAeicResolutionCodes.length) return null;
    return AeicStreamMetadata(
      rate: rate,
      squareSize: kAeicResolutionCodes[resCode],
      aspectCode: (byte >> 4) & 0x0F,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AeicStreamMetadata &&
      other.rate == rate &&
      other.squareSize == squareSize &&
      other.aspectCode == aspectCode;

  @override
  int get hashCode => Object.hash(rate, squareSize, aspectCode);

  @override
  String toString() =>
      'AeicStreamMetadata(${rate.name}, $squareSize, aspect $aspectCode)';
}

/// One parsed chunk header.
class AeicChunkHeader {
  const AeicChunkHeader({
    required this.senderPrefix,
    required this.imageId,
    required this.index,
    required this.total,
  });

  final int senderPrefix;
  final int imageId;

  /// Data index, or [total] for the parity blob.
  final int index;
  final int total;

  bool get isParity => index == total;
  int get dataChunks => total;

  /// Parses four header bytes, or null when they cannot describe a chunk.
  static AeicChunkHeader? parse(Uint8List blob) {
    if (blob.length < kAeicChunkHeaderBytes) return null;
    final int total = blob[3] & 0x0F;
    final int index = (blob[3] >> 4) & 0x0F;
    if (total < 1 || total > kAeicMaxDataChunks) return null;
    if (index > total) return null;
    return AeicChunkHeader(
      senderPrefix: (blob[0] << 8) | blob[1],
      imageId: blob[2],
      index: index,
      total: total,
    );
  }

  Uint8List encode() => Uint8List.fromList(<int>[
        (senderPrefix >> 8) & 0xFF,
        senderPrefix & 0xFF,
        imageId & 0xFF,
        ((index & 0x0F) << 4) | (total & 0x0F),
      ]);
}

/// A picture ready to be put on the air, or one that has been taken apart.
class AeicChunkSet {
  const AeicChunkSet({
    required this.blobs,
    required this.dataChunkCount,
    required this.hasParity,
    required this.imageId,
    required this.senderPrefix,
  });

  final List<Uint8List> blobs;
  final int dataChunkCount;
  final bool hasParity;
  final int imageId;
  final int senderPrefix;

  int get totalBytes => blobs.fold<int>(0, (int a, Uint8List b) => a + b.length);
  int get packetCount => blobs.length;
}

/// How many data chunks a payload of [payloadBytes] needs.
int aeicDataChunkCount(int payloadBytes) {
  if (payloadBytes <= 0) return 1;
  if (payloadBytes <= kAeicFirstChunkCapacity) return 1;
  final int rest = payloadBytes - kAeicFirstChunkCapacity;
  return 1 + (rest + kAeicChunkCapacity - 1) ~/ kAeicChunkCapacity;
}

/// Two bytes of the sender's public key, repeated in every chunk so a receiver
/// can tell two senders' streams apart on one channel.
int aeicSenderPrefixFromKey(List<int> publicKey) {
  if (publicKey.length < 2) return 0;
  return (publicKey[0] << 8) | publicKey[1];
}

/// Splits a bitstream into the blobs the radio carries.
///
/// [parity] appends one XOR blob, which buys recovery of exactly one lost chunk.
///
/// Throws [ArgumentError] when [payload] exceeds [kAeicMaxPayloadBytes].
AeicChunkSet buildAeicChunks({
  required Uint8List payload,
  required AeicStreamMetadata metadata,
  required int senderPrefix,
  required int imageId,
  bool parity = true,
}) {
  if (payload.length > kAeicMaxPayloadBytes) {
    throw ArgumentError.value(payload.length, 'payload',
        'exceeds kAeicMaxPayloadBytes ($kAeicMaxPayloadBytes)');
  }
  final int total = aeicDataChunkCount(payload.length);

  // Bodies first: the parity blob is a pure function of them.
  final List<Uint8List> bodies = <Uint8List>[];
  int offset = 0;
  for (int i = 0; i < total; i++) {
    final int capacity =
        i == 0 ? kAeicFirstChunkCapacity : kAeicChunkCapacity;
    final int take = math.min(capacity, payload.length - offset);
    final BytesBuilder body = BytesBuilder();
    if (i == 0) body.addByte(metadata.encode());
    if (take > 0) body.add(Uint8List.sublistView(payload, offset, offset + take));
    offset += take;
    bodies.add(body.toBytes());
  }

  final List<Uint8List> blobs = <Uint8List>[];
  for (int i = 0; i < total; i++) {
    blobs.add((BytesBuilder()
          ..add(AeicChunkHeader(
                  senderPrefix: senderPrefix,
                  imageId: imageId,
                  index: i,
                  total: total)
              .encode())
          ..add(bodies[i]))
        .toBytes());
  }

  if (parity) {
    final Uint8List xor = Uint8List(kAeicChunkBodyBytes);
    int lenXor = 0;
    for (final Uint8List body in bodies) {
      lenXor ^= body.length;
      for (int j = 0; j < body.length; j++) {
        xor[j] ^= body[j];
      }
    }
    blobs.add((BytesBuilder()
          ..add(AeicChunkHeader(
                  senderPrefix: senderPrefix,
                  imageId: imageId,
                  index: total,
                  total: total)
              .encode())
          ..addByte(lenXor & 0xFF)
          ..add(xor))
        .toBytes());
  }

  return AeicChunkSet(
    blobs: blobs,
    dataChunkCount: total,
    hasParity: parity,
    imageId: imageId,
    senderPrefix: senderPrefix,
  );
}

/// What a received blob did.
enum AeicChunkStatus { incomplete, completed, parityMatched, refused }

/// One finished picture: its bitstream and what the sender said about it.
class AeicPicture {
  const AeicPicture({
    required this.bytes,
    required this.metadata,
    required this.senderPrefix,
    required this.imageId,
    required this.recovered,
  });

  final Uint8List bytes;
  final AeicStreamMetadata metadata;
  final int senderPrefix;
  final int imageId;

  /// True when a lost chunk was rebuilt from the parity blob.
  final bool recovered;
}

/// Collects chunks into pictures.
///
/// Keyed on sender prefix, image id and channel, because a channel can carry two
/// senders at once and the id is only eight bits. Entries expire after
/// [kAeicReassemblyTtl], which bounds the damage of an id wrap.
class AeicReassembler {
  AeicReassembler({this.ttl = kAeicReassemblyTtl});

  final Duration ttl;

  final Map<String, _Pending> _pending = <String, _Pending>{};

  int get pendingCount => _pending.length;

  /// Feed one received blob. Returns [AeicChunkStatus.completed] when this blob
  /// finished a picture, whose bytes are then discarded from memory.
  AeicChunkStatus accept({
    required Uint8List blob,
    required int channelIndex,
    required int ownSenderPrefix,
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    _evict(at);
    final AeicChunkHeader? header = AeicChunkHeader.parse(blob);
    if (header == null) return AeicChunkStatus.refused;
    // Our own transmission, echoed by a receiver: nothing to do.
    if (header.senderPrefix == ownSenderPrefix) return AeicChunkStatus.refused;

    final String key = '${header.senderPrefix}/${header.imageId}/$channelIndex';
    final _Pending entry = _pending.putIfAbsent(
        key,
        () => _Pending(total: header.total, at: at, channelIndex: channelIndex));
    if (entry.total != header.total) {
      // Same key, different shape: the id wrapped and this is a new picture.
      _pending[key] = _Pending(
          total: header.total, at: at, channelIndex: channelIndex);
      return AeicChunkStatus.refused;
    }
    entry.at = at;
    final Uint8List body =
        Uint8List.sublistView(blob, kAeicChunkHeaderBytes);
    if (header.isParity) {
      entry.parityBody = Uint8List.fromList(body);
      if (entry.isRecoverable) {
        final Uint8List? rebuilt = entry.rebuildFromParity();
        if (rebuilt != null) {
          entry.recovered = true;
        }
      }
    } else {
      entry.bodies[header.index] = Uint8List.fromList(body);
    }
    if (!entry.isComplete) return AeicChunkStatus.incomplete;

    final AeicPicture? picture = entry.assemble(header);
    _pending.remove(key);
    if (picture == null) return AeicChunkStatus.refused;
    lastPicture = picture;
    return entry.recovered
        ? AeicChunkStatus.parityMatched
        : AeicChunkStatus.completed;
  }

  /// The picture the last [accept] completed, if any.
  AeicPicture? lastPicture;

  void _evict(DateTime now) {
    _pending.removeWhere(
        (String _, _Pending p) => now.difference(p.at) > ttl);
  }

  void clear() => _pending.clear();
}

class _Pending {
  _Pending({required this.total, required this.at, required this.channelIndex});

  final int total;
  final int channelIndex;
  DateTime at;
  final Map<int, Uint8List> bodies = <int, Uint8List>{};
  Uint8List? parityBody;
  bool recovered = false;

  bool get isComplete => bodies.length == total;
  bool get isRecoverable => bodies.length == total - 1 && parityBody != null;

  /// XORs the chunks we have out of the parity body to recover the missing one.
  ///
  /// Parity is the XOR of every data body padded to the body size, with the XOR
  /// of their lengths in the leading byte. The length byte is what makes the
  /// recovered chunk's length exact instead of padded.
  Uint8List? rebuildFromParity() {
    final Uint8List parity = parityBody!;
    if (parity.isEmpty) return null;
    int missing = -1;
    for (int i = 0; i < total; i++) {
      if (!bodies.containsKey(i)) {
        missing = i;
        break;
      }
    }
    if (missing < 0) return null;
    int lenXor = parity[0];
    final Uint8List acc = Uint8List.fromList(parity.sublist(1));
    for (int i = 0; i < total; i++) {
      final Uint8List? body = bodies[i];
      if (body == null) continue;
      lenXor ^= body.length;
      for (int j = 0; j < body.length; j++) {
        acc[j] ^= body[j];
      }
    }
    if (lenXor < 0 || lenXor > acc.length) return null;
    bodies[missing] = Uint8List.fromList(acc.sublist(0, lenXor));
    return bodies[missing];
  }

  AeicPicture? assemble(AeicChunkHeader header) {
    final Uint8List first = bodies[0]!;
    if (first.isEmpty) return null;
    final AeicStreamMetadata? metadata = AeicStreamMetadata.decode(first[0]);
    if (metadata == null) return null;
    final BytesBuilder out = BytesBuilder();
    out.add(Uint8List.sublistView(first, 1));
    for (int i = 1; i < total; i++) {
      out.add(bodies[i]!);
    }
    return AeicPicture(
      bytes: out.toBytes(),
      metadata: metadata,
      senderPrefix: header.senderPrefix,
      imageId: header.imageId,
      recovered: recovered,
    );
  }
}
