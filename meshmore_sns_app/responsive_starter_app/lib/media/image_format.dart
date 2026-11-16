// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

/// The containers a phone picture can arrive in.
///
/// Sniffing is what makes a refusal honest. The engine's decoder reports every
/// unreadable file as the same exception, so without this a HEIC from a
/// Samsung camera and a truncated JPEG would produce one message: "could not be
/// read". They are different problems with different answers, and the copy
/// says which one happened.
enum MediaImageFormat {
  jpeg,
  png,
  webp,
  gif,
  bmp,
  /// HEIF/HEIC, which the engine cannot decode: Apple's camera format and an
  /// opt-in on recent Android. Named so the copy can tell the user to pick a
  /// JPEG instead of implying the file is broken.
  heic,
  /// AV1 image. The wire format, but not a camera format, and the engine has no
  /// AV1 decoder here either.
  avif,
  unknown,
}

/// The container these bytes start with, by magic number rather than by
/// extension, because the extension is whatever the picker felt like.
MediaImageFormat sniffImageFormat(Uint8List bytes) {
  if (bytes.length < 12) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return MediaImageFormat.jpeg;
    }
    return MediaImageFormat.unknown;
  }
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return MediaImageFormat.jpeg;
  }
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return MediaImageFormat.png;
  }
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return MediaImageFormat.gif;
  }
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return MediaImageFormat.bmp;
  }
  if (_ascii(bytes, 0, 4) == 'RIFF' && _ascii(bytes, 8, 4) == 'WEBP') {
    return MediaImageFormat.webp;
  }
  if (_ascii(bytes, 4, 4) == 'ftyp') {
    // ISO base media: the major brand at 8, the compatible brands after.
    switch (_ascii(bytes, 8, 4)) {
      case 'heic':
      case 'heix':
      case 'heim':
      case 'heis':
      case 'mif1':
      case 'msf1':
        return MediaImageFormat.heic;
      case 'avif':
      case 'avis':
        return MediaImageFormat.avif;
    }
    for (int at = 16; at + 4 <= bytes.length && at < 64; at += 4) {
      final String brand = _ascii(bytes, at, 4);
      if (brand == 'heic' || brand == 'mif1' || brand == 'msf1') {
        return MediaImageFormat.heic;
      }
      if (brand == 'avif') return MediaImageFormat.avif;
    }
  }
  return MediaImageFormat.unknown;
}

/// True when the engine's own decoders can read this container, which is what
/// makes JPEG, PNG, GIF, BMP and WebP work without a second native library.
bool engineDecodes(MediaImageFormat format) => switch (format) {
      MediaImageFormat.jpeg ||
      MediaImageFormat.png ||
      MediaImageFormat.webp ||
      MediaImageFormat.gif ||
      MediaImageFormat.bmp =>
        true,
      MediaImageFormat.heic ||
      MediaImageFormat.avif ||
      MediaImageFormat.unknown =>
        false,
    };

String _ascii(Uint8List b, int start, int length) {
  if (start + length > b.length) return '';
  final StringBuffer out = StringBuffer();
  for (int i = start; i < start + length; i++) {
    out.writeCharCode(b[i]);
  }
  return out.toString();
}
