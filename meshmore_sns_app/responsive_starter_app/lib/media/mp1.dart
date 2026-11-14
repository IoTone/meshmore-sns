// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
/// MP1 — a picture small enough to be one channel datagram.
///
/// The format is MeshPix's (`~/Documents/mesh-research/Meshpix/lib/codec/`), and
/// it is implemented here byte for byte so a MeshPix user can read our preview
/// and we can read theirs. It is not a neural codec and it is not AVIF: it is a
/// 24x24 (or 16x16) square quantised onto a 4- or 16-colour palette, dithered,
/// and packed at 2 or 4 bits per pixel. That is what fits in 163 bytes.
///
/// Why it exists at all, next to AVIF: a channel datagram is 163 bytes and an
/// AVIF container spends 200-350 bytes before the first pixel, so AVIF can never
/// be a one-packet image. A preview that costs one datagram (about 0.35 s of
/// channel time) is the difference between "there is a picture here, tap to
/// load" and "somebody spent twenty datagrams on a photo you did not ask for".
///
/// Wire format, exactly:
///
/// ```text
/// [0] 'M' 0x4D
/// [1] 'P' 0x50
/// [2] version 1
/// [3] flags: kind(0=preview) | encoding<<3 | (bpp==4 ? 1<<5 : 0) | (dithered ? 1<<6 : 0)
/// [4] transfer id, low byte
/// [5] transfer id, high byte
/// [6] width
/// [7] height
/// [8] palette id (0 = mesh4, 1 = mesh16)
/// [9] upgrade chunks (how many datagrams the full picture would take)
/// [10..] body: packed indices, 2 or 4 bits per pixel
/// ```
///
/// The body encoding byte is MeshPix's `BodyEncoding`: 0 raw, 1 zlib, 2 RLE,
/// 3 JPEG. This encoder writes raw, which every decoder must accept, and the
/// decoder reads raw and RLE. A zlib body is refused with a named error rather
/// than mis-decoded, because this app does not ship a zlib decoder for a
/// 163-byte payload and a wrong picture is worse than a missing one.
library;
import 'dart:typed_data';

import 'media_photo.dart';



/// The largest body a channel datagram can carry (`MAX_CHANNEL_DATA_LENGTH`).
const int kMp1MaxPayload = 163;

/// MeshPix's application data type for an image datagram.
const int kMp1DataType = 0xFF50;

/// MeshPix's data type for its channel catch-up and receipts.
const int kMp1CatchUpDataType = 0xFF51;

const int _kMagic0 = 0x4D; // 'M'
const int _kMagic1 = 0x50; // 'P'
const int _kVersion = 1;
const int _kHeaderBytes = 10;

/// One palette colour.
final class Mp1Colour {
  const Mp1Colour(this.r, this.g, this.b);
  final int r;
  final int g;
  final int b;

  int get argb => 0xFF000000 | (r << 16) | (g << 8) | b;

  int distanceSquared(int rr, int gg, int bb) {
    final int dr = r - rr;
    final int dg = g - gg;
    final int db = b - bb;
    return dr * dr + dg * dg + db * db;
  }
}

/// A palette, with the id that travels on the wire.
final class Mp1Palette {
  const Mp1Palette({required this.id, required this.name, required this.colours});

  final int id;
  final String name;
  final List<Mp1Colour> colours;

  int get bitsPerPixel => colours.length <= 4 ? 2 : 4;

  int nearestIndex(int r, int g, int b) {
    int best = 0;
    int bestD = 1 << 30;
    for (int i = 0; i < colours.length; i++) {
      final int d = colours[i].distanceSquared(r, g, b);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }
}

/// MeshPix's four-colour mesh palette: near-black, paper, amber, teal.
const Mp1Palette kMp1Mesh4 = Mp1Palette(id: 0, name: 'mesh4', colours: <Mp1Colour>[
  Mp1Colour(0x14, 0x14, 0x18),
  Mp1Colour(0xF4, 0xF1, 0xDE),
  Mp1Colour(0xE8, 0xA8, 0x38),
  Mp1Colour(0x2A, 0x9D, 0x8F),
]);

/// MeshPix's sixteen-colour palette, which dithers a photo into something
/// recognisable.
const Mp1Palette kMp1Mesh16 =
    Mp1Palette(id: 1, name: 'mesh16', colours: <Mp1Colour>[
  Mp1Colour(0x00, 0x00, 0x00),
  Mp1Colour(0x7F, 0x00, 0x00),
  Mp1Colour(0x00, 0x7F, 0x00),
  Mp1Colour(0x7F, 0x7F, 0x00),
  Mp1Colour(0x00, 0x00, 0x7F),
  Mp1Colour(0x7F, 0x00, 0x7F),
  Mp1Colour(0x00, 0x7F, 0x7F),
  Mp1Colour(0xBF, 0xBF, 0xBF),
  Mp1Colour(0x7F, 0x7F, 0x7F),
  Mp1Colour(0xFF, 0x00, 0x00),
  Mp1Colour(0x00, 0xFF, 0x00),
  Mp1Colour(0xFF, 0xFF, 0x00),
  Mp1Colour(0x00, 0x00, 0xFF),
  Mp1Colour(0xFF, 0x00, 0xFF),
  Mp1Colour(0x00, 0xFF, 0xFF),
  Mp1Colour(0xFF, 0xFF, 0xFF),
]);

Mp1Palette mp1PaletteById(int id) => id == kMp1Mesh16.id ? kMp1Mesh16 : kMp1Mesh4;

/// A decoded preview: the palette indices and the palette they index.
final class Mp1Image {
  const Mp1Image({
    required this.width,
    required this.height,
    required this.palette,
    required this.indices,
    required this.dithered,
    required this.transferId,
    required this.upgradeChunks,
  });

  final int width;
  final int height;
  final Mp1Palette palette;
  final List<int> indices;
  final bool dithered;
  final int transferId;

  /// How many datagrams the sender says the full picture would take. Zero means
  /// the sender has no full picture to offer.
  final int upgradeChunks;

  /// The preview as straight RGBA, which is what the rest of the app draws.
  MediaPhoto toPhoto() {
    final Uint8List rgba = Uint8List(width * height * 4);
    for (int i = 0; i < indices.length; i++) {
      final Mp1Colour c = palette.colours[indices[i].clamp(0, palette.colours.length - 1)];
      rgba[i * 4] = c.r;
      rgba[i * 4 + 1] = c.g;
      rgba[i * 4 + 2] = c.b;
      rgba[i * 4 + 3] = 0xFF;
    }
    return MediaPhoto(width: width, height: height, rgba: rgba);
  }
}

/// Why a datagram was not an MP1 preview.
enum Mp1Problem { notMp1, unsupportedVersion, unsupportedEncoding, truncated }

/// The result of trying to read a datagram as a preview.
final class Mp1DecodeResult {
  const Mp1DecodeResult.image(Mp1Image this.image) : problem = null;
  const Mp1DecodeResult.failed(Mp1Problem this.problem) : image = null;

  final Mp1Image? image;
  final Mp1Problem? problem;

  bool get ok => image != null;
}

/// Encodes [photo] as an MP1 preview that fits one datagram.
///
/// The ladder is MeshPix's, largest first: 24x24 at four colours (144 bytes of
/// indices), then 16x16 at sixteen (128), then 16x16 at four (64). The first
/// that fits 163 bytes wins, and a picture that cannot fit at all returns null
/// rather than a truncated datagram.
///
/// [upgradeChunks] is what the sender would need to send the full picture, so
/// the receiver can say "load (12 packets)" before spending anything.
Uint8List? encodeMp1Preview(
  MediaPhoto photo, {
  required int transferId,
  int upgradeChunks = 0,
  bool dither = true,
}) {
  // 24x24 at 16 colours is 288 bytes of indices, which cannot fit 163, so it is
  // not on the ladder at all. The order is MeshPix's: the biggest picture first
  // (24x24 at four colours is 144 bytes), then the smaller one with more colour
  // (16x16 at sixteen is 128), then the smallest.
  const List<(int size, Mp1Palette palette)> ladder =
      <(int, Mp1Palette)>[
    (24, kMp1Mesh4),
    (16, kMp1Mesh16),
    (16, kMp1Mesh4),
  ];
  for (final (int size, Mp1Palette palette) in ladder) {
    final Uint8List? bytes = _tryEncode(
      photo,
      size: size,
      palette: palette,
      transferId: transferId,
      upgradeChunks: upgradeChunks,
      dither: dither,
    );
    if (bytes != null) return bytes;
  }
  return null;
}

Uint8List? _tryEncode(
  MediaPhoto photo, {
  required int size,
  required Mp1Palette palette,
  required int transferId,
  required int upgradeChunks,
  required bool dither,
}) {
  final MediaPhoto square = _square(photo, size);
  final List<int> indices = _quantise(square, palette, dither: dither);
  final Uint8List body = _packIndices(indices, palette.bitsPerPixel);
  final int flags = 0 /* preview */ |
      (0 << 3) /* raw */ |
      (palette.bitsPerPixel == 4 ? 1 << 5 : 0) |
      (dither ? 1 << 6 : 0);
  final Uint8List out = Uint8List(_kHeaderBytes + body.length);
  out[0] = _kMagic0;
  out[1] = _kMagic1;
  out[2] = _kVersion;
  out[3] = flags;
  out[4] = transferId & 0xFF;
  out[5] = (transferId >> 8) & 0xFF;
  out[6] = size;
  out[7] = size;
  out[8] = palette.id;
  out[9] = upgradeChunks & 0xFF;
  out.setRange(_kHeaderBytes, out.length, body);
  if (out.length > kMp1MaxPayload) return null;
  return out;
}

/// Centre-crops to a square and box-filters down to [size].
MediaPhoto _square(MediaPhoto photo, int size) {
  final int side = photo.width < photo.height ? photo.width : photo.height;
  final int x0 = (photo.width - side) ~/ 2;
  final int y0 = (photo.height - side) ~/ 2;
  final Uint8List out = Uint8List(size * size * 4);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      // Box filter over the source pixels this destination pixel covers.
      final int sx0 = x0 + (x * side) ~/ size;
      final int sx1 = x0 + ((x + 1) * side) ~/ size;
      final int sy0 = y0 + (y * side) ~/ size;
      final int sy1 = y0 + ((y + 1) * side) ~/ size;
      int r = 0, g = 0, b = 0, n = 0;
      for (int sy = sy0; sy < sy1; sy++) {
        for (int sx = sx0; sx < sx1; sx++) {
          final int i = (sy * photo.width + sx) * 4;
          r += photo.rgba[i];
          g += photo.rgba[i + 1];
          b += photo.rgba[i + 2];
          n++;
        }
      }
      final int o = (y * size + x) * 4;
      out[o] = n == 0 ? 0 : r ~/ n;
      out[o + 1] = n == 0 ? 0 : g ~/ n;
      out[o + 2] = n == 0 ? 0 : b ~/ n;
      out[o + 3] = 0xFF;
    }
  }
  return MediaPhoto(width: size, height: size, rgba: out);
}

/// Floyd–Steinberg dithering onto [palette], which is what makes a 16-colour
/// photo read as a photo rather than as a poster.
List<int> _quantise(MediaPhoto photo, Mp1Palette palette, {required bool dither}) {
  final int w = photo.width;
  final int h = photo.height;
  final List<int> indices = List<int>.filled(w * h, 0);
  if (!dither) {
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int i = (y * w + x) * 4;
        indices[y * w + x] =
            palette.nearestIndex(photo.rgba[i], photo.rgba[i + 1], photo.rgba[i + 2]);
      }
    }
    return indices;
  }
  // Error diffusion needs signed accumulators, so the picture is copied into
  // three int planes first.
  final List<int> r = List<int>.filled(w * h, 0);
  final List<int> g = List<int>.filled(w * h, 0);
  final List<int> b = List<int>.filled(w * h, 0);
  for (int i = 0; i < w * h; i++) {
    r[i] = photo.rgba[i * 4];
    g[i] = photo.rgba[i * 4 + 1];
    b[i] = photo.rgba[i * 4 + 2];
  }
  int clamp8(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final int i = y * w + x;
      final int idx = palette.nearestIndex(r[i], g[i], b[i]);
      indices[i] = idx;
      final Mp1Colour c = palette.colours[idx];
      final int er = r[i] - c.r;
      final int eg = g[i] - c.g;
      final int eb = b[i] - c.b;
      void spread(int dx, int dy, int num, int den) {
        final int nx = x + dx;
        final int ny = y + dy;
        if (nx < 0 || nx >= w || ny >= h) return;
        final int j = ny * w + nx;
        r[j] = clamp8(r[j] + er * num ~/ den);
        g[j] = clamp8(g[j] + eg * num ~/ den);
        b[j] = clamp8(b[j] + eb * num ~/ den);
      }

      spread(1, 0, 7, 16);
      spread(-1, 1, 3, 16);
      spread(0, 1, 5, 16);
      spread(1, 1, 1, 16);
    }
  }
  return indices;
}

Uint8List _packIndices(List<int> indices, int bitsPerPixel) {
  if (bitsPerPixel == 4) {
    final Uint8List out = Uint8List((indices.length + 1) >> 1);
    for (int i = 0; i < indices.length; i++) {
      final int v = indices[i] & 0x0F;
      if ((i & 1) == 0) {
        out[i >> 1] = v << 4;
      } else {
        out[i >> 1] |= v;
      }
    }
    return out;
  }
  final Uint8List out = Uint8List((indices.length + 3) >> 2);
  for (int i = 0; i < indices.length; i++) {
    final int v = indices[i] & 0x03;
    final int shift = 6 - 2 * (i & 3);
    out[i >> 2] |= v << shift;
  }
  return out;
}

List<int> _unpackIndices(Uint8List packed, int count, int bitsPerPixel) {
  final List<int> indices = List<int>.filled(count, 0);
  if (bitsPerPixel == 4) {
    for (int i = 0; i < count; i++) {
      final int b = packed[i >> 1];
      indices[i] = (i & 1) == 0 ? (b >> 4) & 0x0F : b & 0x0F;
    }
    return indices;
  }
  for (int i = 0; i < count; i++) {
    final int b = packed[i >> 2];
    final int shift = 6 - 2 * (i & 3);
    indices[i] = (b >> shift) & 0x03;
  }
  return indices;
}

List<int> _rleDecode(Uint8List data, int count) {
  final List<int> indices = List<int>.filled(count, 0);
  int o = 0;
  int i = 0;
  while (i + 1 < data.length && o < count) {
    final int run = data[i];
    final int v = data[i + 1];
    i += 2;
    for (int k = 0; k < run && o < count; k++) {
      indices[o++] = v;
    }
  }
  if (o != count) throw const FormatException('RLE length mismatch');
  return indices;
}

/// Reads a datagram as an MP1 preview.
///
/// A datagram that is not MP1 is [Mp1Problem.notMp1] rather than an exception:
/// the channel carries other application data types and a receiver must be able
/// to say "not mine" without a stack trace.
Mp1DecodeResult decodeMp1Preview(Uint8List bytes) {
  if (bytes.length < _kHeaderBytes) {
    return const Mp1DecodeResult.failed(Mp1Problem.truncated);
  }
  if (bytes[0] != _kMagic0 || bytes[1] != _kMagic1) {
    return const Mp1DecodeResult.failed(Mp1Problem.notMp1);
  }
  if (bytes[2] != _kVersion) {
    return const Mp1DecodeResult.failed(Mp1Problem.unsupportedVersion);
  }
  final int flags = bytes[3];
  final int kind = flags & 0x07;
  if (kind != 0) {
    // Chunk, pull, nack and abort are the upgrade protocol, not a preview.
    return const Mp1DecodeResult.failed(Mp1Problem.notMp1);
  }
  final int encoding = (flags >> 3) & 0x03;
  final bool fourBit = (flags & (1 << 5)) != 0;
  final bool dithered = (flags & (1 << 6)) != 0;
  final int transferId = bytes[4] | (bytes[5] << 8);
  final int width = bytes[6];
  final int height = bytes[7];
  final Mp1Palette palette = mp1PaletteById(bytes[8]);
  final int upgradeChunks = bytes[9];
  if (width == 0 || height == 0 || width > 64 || height > 64) {
    return const Mp1DecodeResult.failed(Mp1Problem.truncated);
  }
  final Uint8List body = Uint8List.sublistView(bytes, _kHeaderBytes);
  final int count = width * height;
  final int bpp = fourBit ? 4 : 2;
  try {
    final List<int> indices = switch (encoding) {
      0 => _unpackIndices(body, count, bpp),
      2 => _rleDecode(body, count),
      // zlib (1) and JPEG (3) bodies are refused by name: this app ships no
      // zlib decoder for a 163-byte payload, and a wrong picture is worse than
      // a missing one.
      _ => throw const FormatException('unsupported body encoding'),
    };
    return Mp1DecodeResult.image(Mp1Image(
      width: width,
      height: height,
      palette: palette,
      indices: indices,
      dithered: dithered,
      transferId: transferId,
      upgradeChunks: upgradeChunks,
    ));
  } on FormatException {
    return const Mp1DecodeResult.failed(Mp1Problem.unsupportedEncoding);
  } on RangeError {
    return const Mp1DecodeResult.failed(Mp1Problem.truncated);
  }
}
