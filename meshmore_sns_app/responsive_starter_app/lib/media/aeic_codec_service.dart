// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import 'aeic/onnx_codec.dart';

/// Whether this build can encode and decode AEIC pictures.
///
/// True now that the coder, the entropy layer and the ONNX sessions are all
/// here. What still gates a *send* is the model bundle: without it this answers
/// "not installed" rather than failing mid-picture.
const bool kAeicWireAvailable = true;

/// The AEIC codec, wired to the bundle the installer fetched.
///
/// One instance for the process, one operation at a time. Everything that can
/// fail before a session exists (no bundle, an unreadable file) is answered as
/// [AeicUnavailable] with a sentence the UI can show, because a codec failure
/// that reaches the composer as an exception reads as a crash.
class AeicCodecService {
  AeicCodecService({Future<Directory> Function()? root})
      : _root = root ?? _defaultRoot;

  static Future<Directory> _defaultRoot() async {
    final Directory base = await getApplicationSupportDirectory();
    return Directory('${base.path}/aeic');
  }

  final Future<Directory> Function() _root;

  AeicOnnxCodec? _codec;
  Future<void> _tail = Future<void>.value();
  bool _busy = false;

  bool get busy => _busy;

  /// Whether the bundle on disk is complete enough to run.
  Future<bool> installed() async {
    final Directory dir = await _root();
    for (final String name in <String>[
      kAeicDecoderGraph,
      kAeicEntropyEncodeGraph,
      kAeicEntropyDecodeGraph,
      kAeicTablesFile,
    ]) {
      if (!await File('${dir.path}/$name').exists()) return false;
    }
    return true;
  }

  Future<AeicOnnxCodec> _ensure() async {
    final AeicOnnxCodec? existing = _codec;
    if (existing != null) return existing;
    final Directory dir = await _root();
    for (final String name in <String>[
      kAeicDecoderGraph,
      kAeicEntropyEncodeGraph,
      kAeicEntropyDecodeGraph,
      kAeicTablesFile,
    ]) {
      if (!await File('${dir.path}/$name').exists()) {
        throw const AeicUnavailable(
            'the image codec is not installed; install it in Settings → Chat & '
            'media');
      }
    }
    // The codec is compiled for a test that never touches the disk, so it reads
    // files through a hook; the app wires the real reader here.
    AeicOnnxCodec.readBytes = (String path) => File(path).readAsBytes();
    final AeicOnnxCodec built = AeicOnnxCodec(
      decoderGraphPath: '${dir.path}/$kAeicDecoderGraph',
      entropyEncodeGraphPath: '${dir.path}/$kAeicEntropyEncodeGraph',
      entropyDecodeGraphPath: '${dir.path}/$kAeicEntropyDecodeGraph',
      tablesPath: '${dir.path}/$kAeicTablesFile',
    );
    _codec = built;
    return built;
  }

  /// Run one operation, serialised: the sessions are gigabytes and two at once
  /// is how a phone runs out of memory.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final Completer<T> done = Completer<T>();
    _tail = _tail.then((_) async {
      _busy = true;
      try {
        done.complete(await action());
      } on Object catch (e, s) {
        done.completeError(e, s);
      } finally {
        _busy = false;
      }
    });
    return done.future;
  }

  /// Encode a picture at [width]×[height] into an AEIC bitstream.
  ///
  /// The picture is stretched into the codec's 512×512 square, which is why the
  /// chunk framing names the original aspect ratio: the receiver letterboxes it
  /// back. Nothing is cropped.
  Future<Uint8List> encodeRgb(
    Uint8List rgba,
    int width,
    int height, {
    void Function(double progress)? onProgress,
  }) =>
      _exclusive(() async {
        final AeicOnnxCodec codec = await _ensure();
        final Uint8List chw = await _toChw(rgba, width, height);
        return codec.encode(chw, onProgress: onProgress);
      });

  /// Decode a bitstream to packed 8-bit RGB of 512².
  Future<Uint8List> decode(Uint8List bitstream,
          {void Function(double progress)? onProgress}) =>
      _exclusive(() async {
        final AeicOnnxCodec codec = await _ensure();
        return codec.decode(bitstream, onProgress: onProgress);
      });

  /// Release the sessions. The platform calls this when it reports pressure.
  Future<void> releaseForMemoryPressure() async {
    await _codec?.releaseForMemoryPressure();
  }

  Future<void> dispose() async {
    await _codec?.dispose();
    _codec = null;
  }

  /// RGBA bytes to the codec's `[1, 3, 512, 512]` floats in [-1, 1].
  ///
  /// The stretch is a plain box resample: the encoder was trained on stretched
  /// frames, so an area average is closer to its input distribution than a
  /// nearest-neighbour pick would be, and it costs one pass.
  static Future<Uint8List> _toChw(Uint8List rgba, int width, int height) async {
    final ui.ImmutableBuffer buffer =
        await ui.ImmutableBuffer.fromUint8List(rgba);
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final ui.Codec decoder = await descriptor.instantiateCodec(
        targetWidth: kAeicSquareSize, targetHeight: kAeicSquareSize);
    final ui.FrameInfo frame = await decoder.getNextFrame();
    final ByteData? data =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    decoder.dispose();
    descriptor.dispose();
    buffer.dispose();
    if (data == null) {
      throw const AeicUnavailable('the picture could not be read');
    }
    final Uint8List src = data.buffer.asUint8List();
    const int pixels = kAeicSquareSize * kAeicSquareSize;
    final Float32List chw = Float32List(pixels * 3);
    for (int i = 0; i < pixels; i++) {
      final int o = i * 4;
      chw[i] = src[o] / 127.5 - 1.0;
      chw[pixels + i] = src[o + 1] / 127.5 - 1.0;
      chw[2 * pixels + i] = src[o + 2] / 127.5 - 1.0;
    }
    return chw.buffer.asUint8List();
  }
}
