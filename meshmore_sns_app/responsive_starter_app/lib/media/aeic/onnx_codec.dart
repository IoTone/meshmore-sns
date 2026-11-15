// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
//
// The ONNX half of the AEIC codec, ported from MeshCore Open
// (`lib/services/image_codec_backend.dart`, MIT, Copyright (c) 2025 zjs81).
// The tensor names, shapes and the session-lifecycle rule are that export's
// contract; the rANS coder and the entropy arithmetic are ours (see
// `rans_coder.dart` and `entropy_layer.dart`).
//
// Why the lifecycle rule exists: the two entropy graphs are ~0.35 GiB each and
// the synthesis session peaks at 2.16 GiB. A phone that holds the entropy graph
// and the synthesis session at the same time is a phone that gets killed. So the
// rule is load-what-you-need, drop-it-before-loading-the-other, and never both.
library;

import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'entropy_layer.dart';
import 'entropy_tables.dart';

/// Shape of the decoder's only input: `y_hat`, float32, `[1, 256, 16, 16]`.
/// Static: the export has no dynamic axes and no batching.
const List<int> kAeicLatentShape = <int>[1, 256, 16, 16];

/// Element count implied by [kAeicLatentShape].
const int kAeicLatentElements = 256 * 16 * 16;

/// The decoder graph's input and output names in the promoted export.
const String kAeicDecoderInputName = 'y_hat';
const String kAeicDecoderOutputName = 'image';

/// The square the codec encodes, in pixels.
const int kAeicSquareSize = 512;

/// The file names of the bundle, as the installer fetches them.
const String kAeicDecoderGraph = 'aeic_decoder_qdq_conv_pct.onnx';
const String kAeicEntropyEncodeGraph = 'aeic_entropy_side_fp32_op17.onnx';
const String kAeicEntropyDecodeGraph = 'aeic_entropy_decode_fp32_op17.onnx';
const String kAeicTablesFile = 'aeic_cdf_ft32.bin';

/// Thrown when the bundle on disk is not one this build can run.
class AeicUnavailable implements Exception {
  const AeicUnavailable(this.message);
  final String message;
  @override
  String toString() => 'AeicUnavailable: $message';
}

/// The entropy graphs as tensors.
///
/// Implements the ported entropy layer's network interface, so the arithmetic
/// stays testable against a fake and this class stays the only place that knows
/// the export's tensor names.
class AeicOnnxEntropyNetwork implements AeicEntropyNetwork {
  AeicOnnxEntropyNetwork({this.encodeSession, this.decodeSession});

  static const String kImageInput = 'image';
  static const String kZqInput = 'z_q';
  static const String kBaseInput = 'base';
  static const String kStageInput = 'stage';
  static const String kBase0Output = 'base0';
  static const String kMeansOutput = 'means';
  static const String kScalesOutput = 'scales';

  /// The `stage` value that selects the hyper-synthesis branch. Any negative
  /// value works; -1 is the documented one.
  static const int kHyperStage = -1;

  static const List<int> kZqShape = <int>[1, 128, 4, 4];
  static const List<int> kBaseShape = <int>[1, 256, 16, 16];
  static const int kZqElements = 128 * 4 * 4;
  static const int kBaseElements = 256 * 16 * 16;

  final OrtSession? encodeSession;
  final OrtSession? decodeSession;

  @override
  bool get supportsDecodeSide {
    final OrtSession? session = decodeSession;
    if (session == null) return false;
    final List<String> inputs = session.inputNames;
    final List<String> outputs = session.outputNames;
    return inputs.contains(kZqInput) &&
        inputs.contains(kBaseInput) &&
        inputs.contains(kStageInput) &&
        outputs.contains(kBase0Output) &&
        outputs.contains(kMeansOutput) &&
        outputs.contains(kScalesOutput);
  }

  @override
  Future<AeicEncodeSideTensors> runEncodeSide(Float32List imageChw) async {
    final OrtSession? session = encodeSession;
    if (session == null) {
      throw const AeicEntropyUnavailable(
          'this network has no send-side entropy session, so it cannot encode');
    }
    if (!session.inputNames.contains(kImageInput)) {
      throw const AeicEntropyUnavailable(
          'the entropy graph has no "image" input, so it cannot encode');
    }
    final int side = imageChw.length ~/ 3;
    final int resolution = _isqrt(side);
    final Map<String, OrtValue> inputs = <String, OrtValue>{
      kImageInput: await OrtValue.fromList(
          imageChw, <int>[1, 3, resolution, resolution]),
    };
    final Map<String, OrtValue> result = await _run(session, inputs);
    try {
      return AeicEncodeSideTensors(
        zQ: await _floats(result, 'z_q'),
        yQ: <Float32List>[
          for (int i = 0; i < 4; i++) await _floats(result, 'yq$i'),
        ],
        scales: <Float32List>[
          for (int i = 0; i < 4; i++) await _floats(result, 'sc$i'),
        ],
      );
    } finally {
      await _disposeAll(result);
    }
  }

  @override
  Future<Float32List> runHyperSynthesis(Float32List zQ) async {
    final OrtSession session = _requireDecodeSide();
    if (zQ.length != kZqElements) {
      throw ArgumentError.value(zQ.length, 'zQ',
          'expected $kZqElements float32 values (shape $kZqShape)');
    }
    // `base` is not read on this branch, but ORT requires every declared input
    // to be fed. Zeros, not a stale tensor: a stale one would be silently wrong
    // the day the export starts reading it.
    final Map<String, OrtValue> result = await _run(session, <String, OrtValue>{
      kZqInput: await OrtValue.fromList(zQ, kZqShape),
      kBaseInput:
          await OrtValue.fromList(Float32List(kBaseElements), kBaseShape),
      kStageInput:
          await OrtValue.fromList(Int32List.fromList(<int>[kHyperStage]), <int>[1]),
    });
    try {
      return await _floats(result, kBase0Output);
    } finally {
      await _disposeAll(result);
    }
  }

  @override
  Future<AeicStageParams> runStage(int stage, Float32List base) async {
    final OrtSession session = _requireDecodeSide();
    if (stage < 0 || stage > 3) {
      // The graph does not validate `stage`: anything >= 4 falls into the
      // stage-3 branch and anything < 0 runs hyper synthesis, either of which
      // desynchronises rANS with no error at all.
      throw ArgumentError.value(stage, 'stage', 'must be 0..3');
    }
    if (base.length != kBaseElements) {
      throw ArgumentError.value(base.length, 'base',
          'expected $kBaseElements float32 values (shape $kBaseShape)');
    }
    final Map<String, OrtValue> result = await _run(session, <String, OrtValue>{
      kZqInput: await OrtValue.fromList(Float32List(kZqElements), kZqShape),
      kBaseInput: await OrtValue.fromList(base, kBaseShape),
      kStageInput:
          await OrtValue.fromList(Int32List.fromList(<int>[stage]), <int>[1]),
    });
    try {
      return AeicStageParams(
        meansSupp: await _floats(result, kMeansOutput),
        scalesSupp: await _floats(result, kScalesOutput),
      );
    } finally {
      await _disposeAll(result);
    }
  }

  OrtSession _requireDecodeSide() {
    final OrtSession? session = decodeSession;
    if (session == null || !supportsDecodeSide) {
      throw const AeicUnavailable(
          'this install has no decode-side entropy graph; decoding a bitstream '
          'needs $kAeicEntropyDecodeGraph');
    }
    return session;
  }

  static Future<Map<String, OrtValue>> _run(
      OrtSession session, Map<String, OrtValue> inputs) async {
    try {
      return await session.run(inputs);
    } on Object catch (e) {
      // Serialise the failure with the input shapes: an ORT shape mismatch is
      // reported as a bare "invalid argument" otherwise.
      final StringBuffer b = StringBuffer('AEIC entropy graph failed: $e');
      inputs.forEach((String name, OrtValue value) {
        b.write('\n  $name ${value.shape}');
      });
      throw AeicUnavailable(b.toString());
    }
  }

  static Future<Float32List> _floats(
      Map<String, OrtValue> result, String name) async {
    final OrtValue? value = result[name];
    if (value == null) {
      throw AeicUnavailable(
          'the graph returned no "$name"; it returned ${result.keys.toList()}');
    }
    final List<dynamic> flat = await value.asFlattenedList();
    final Float32List out = Float32List(flat.length);
    for (int i = 0; i < flat.length; i++) {
      out[i] = (flat[i] as num).toDouble();
    }
    return out;
  }

  static Future<void> _disposeAll(Map<String, OrtValue> result) async {
    for (final OrtValue v in result.values) {
      await v.dispose();
    }
  }

  static int _isqrt(int n) {
    int r = 0;
    while ((r + 1) * (r + 1) <= n) {
      r++;
    }
    return r;
  }
}

/// Encode and decode AEIC bitstreams with the bundle installed on this phone.
///
/// One instance per app, called one operation at a time: the sessions are
/// gigabytes and the two halves must never be resident together.
class AeicOnnxCodec {
  AeicOnnxCodec({
    required this.decoderGraphPath,
    required this.entropyEncodeGraphPath,
    required this.entropyDecodeGraphPath,
    required this.tablesPath,
  });

  final String decoderGraphPath;
  final String entropyEncodeGraphPath;
  final String entropyDecodeGraphPath;
  final String tablesPath;

  final OnnxRuntime _runtime = OnnxRuntime();

  OrtSession? _decoder;
  String _decoderInput = kAeicDecoderInputName;
  String _decoderOutput = kAeicDecoderOutputName;
  OrtSession? _entropyEncode;
  OrtSession? _entropyDecode;
  AeicRansCoderFactory? _coders;

  bool _disposed = false;

  /// The rANS tables, read once.
  Future<AeicRansCoderFactory> _rans() async {
    final existing = _coders;
    if (existing != null) return existing;
    final Uint8List bytes = await _readBytes(tablesPath);
    final AeicRansCoderFactory built = AeicRansCoders(EntropyTables.parse(bytes));
    _coders = built;
    return built;
  }

  /// Read through a hook so this file stays free of `dart:io` and can be
  /// compiled for a test that never touches the disk.
  static Future<Uint8List> Function(String path) readBytes = _defaultRead;

  static Future<Uint8List> _defaultRead(String path) async =>
      throw AeicUnavailable('no file reader is wired in');

  Future<Uint8List> _readBytes(String path) => readBytes(path);

  Future<OrtSession> _ensureDecoder() async {
    final existing = _decoder;
    if (existing != null) return existing;
    // No `providers:` on purpose. Naming an execution provider the platform
    // does not recognise throws, and the int8 QDQ partitioning has never been
    // measured on a device: the default CPU provider is the only behaviour
    // anyone has traced.
    final OrtSession session =
        await _runtime.createSession(decoderGraphPath);
    _decoder = session;
    _decoderInput = _pick(session.inputNames, kAeicDecoderInputName, 'input');
    _decoderOutput =
        _pick(session.outputNames, kAeicDecoderOutputName, 'output');
    return session;
  }

  static String _pick(List<String> names, String preferred, String role) {
    if (names.contains(preferred)) return preferred;
    if (names.length == 1) return names.first;
    throw AeicUnavailable(
        'decoder graph has no $role named "$preferred"; found $names');
  }

  Future<AeicEntropyCodec> _entropy({required bool forDecode}) async {
    OrtSession? encodeSession;
    OrtSession? decodeSession;
    if (forDecode) {
      decodeSession = _entropyDecode ??= await _runtime
          .createSession(entropyDecodeGraphPath);
      // Falling through to the send-side graph would run a graph with no `base`
      // input and desynchronise rANS: a sharp, plausible, wrong picture.
      if (!AeicOnnxEntropyNetwork(decodeSession: decodeSession)
          .supportsDecodeSide) {
        throw const AeicUnavailable(
            'the decode-side entropy graph does not expose z_q/base/stage -> '
            'base0/means/scales');
      }
    } else {
      encodeSession =
          _entropyEncode ??= await _runtime.createSession(entropyEncodeGraphPath);
    }
    return AeicEntropyCodec(
      geometry: AeicEntropyGeometry.forResolution(kAeicSquareSize),
      network: AeicOnnxEntropyNetwork(
          encodeSession: encodeSession, decodeSession: decodeSession),
      coders: await _rans(),
    );
  }

  /// RGB, `[1, 3, 512, 512]` in [-1, 1] as floats, `512 * 512 * 3` bytes.
  ///
  /// Drops the synthesis session first: a decode leaves 2.16 GiB resident and
  /// the entropy graph must never be created on top of it.
  Future<Uint8List> encode(
    Uint8List rgb, {
    void Function(double progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    _checkAlive();
    await releaseDecoder();
    final AeicEntropyCodec codec = await _entropy(forDecode: false);
    try {
      return await codec.encode(rgb,
          onProgress: onProgress, shouldCancel: shouldCancel);
    } on AeicEntropyCancelled {
      throw const AeicUnavailable('cancelled');
    }
  }

  /// A bitstream to packed 8-bit RGB of [kAeicSquareSize]².
  ///
  /// The entropy graph is dropped before the synthesis session is created, for
  /// the same reason as above.
  Future<Uint8List> decode(
    Uint8List bitstream, {
    void Function(double progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    _checkAlive();
    await releaseDecoder();
    final AeicEntropyCodec codec = await _entropy(forDecode: true);
    final Float32List yHat;
    try {
      yHat = await codec.decodeToLatent(bitstream,
          onProgress: (double v) => onProgress?.call(v * 0.5),
          shouldCancel: shouldCancel);
    } on AeicEntropyCancelled {
      throw const AeicUnavailable('cancelled');
    }
    await releaseEntropy();
    return decodeLatent(yHat,
        onProgress: (double v) => onProgress?.call(0.5 + v * 0.5),
        shouldCancel: shouldCancel);
  }

  /// The synthesis step alone, for a caller that already has `y_hat`.
  Future<Uint8List> decodeLatent(
    Float32List yHat, {
    void Function(double progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    _checkAlive();
    if (yHat.length != kAeicLatentElements) {
      throw ArgumentError.value(yHat.length, 'yHat',
          'expected $kAeicLatentElements float32 latents (shape $kAeicLatentShape)');
    }
    if (shouldCancel?.call() == true) throw const AeicUnavailable('cancelled');
    onProgress?.call(0.02);
    final OrtSession session = await _ensureDecoder();
    OrtValue? input;
    final List<OrtValue> outputs = <OrtValue>[];
    try {
      input = await OrtValue.fromList(yHat, kAeicLatentShape);
      onProgress?.call(0.05);
      final Map<String, OrtValue> result =
          await session.run(<String, OrtValue>{_decoderInput: input});
      outputs.addAll(result.values);
      onProgress?.call(0.85);
      final OrtValue output = result[_decoderOutput] ?? result.values.first;
      final List<dynamic> flat = await output.asFlattenedList();
      onProgress?.call(0.95);
      final Uint8List rgb = _chwToRgb(flat, output.shape);
      onProgress?.call(1.0);
      return rgb;
    } finally {
      await input?.dispose();
      for (final OrtValue v in outputs) {
        await v.dispose();
      }
    }
  }

  /// `[1, 3, H, W]` floats in [-1, 1] to packed 8-bit RGB.
  static Uint8List _chwToRgb(List<dynamic> flat, List<int> shape) {
    const int pixels = kAeicSquareSize * kAeicSquareSize;
    const int expected = pixels * 3;
    if (flat.length != expected) {
      throw AeicUnavailable(
          'the decoder returned ${flat.length} values for shape $shape; '
          'expected $expected (${kAeicSquareSize}x$kAeicSquareSize RGB). The '
          'export is static, so a different shape means the wrong model file.');
    }
    final Uint8List rgb = Uint8List(expected);
    for (int channel = 0; channel < 3; channel++) {
      final int plane = channel * pixels;
      int out = channel;
      for (int i = 0; i < pixels; i++, out += 3) {
        // The output range is [-1, 1]; the last conv is unbounded, so values
        // outside it must be clamped rather than wrapped.
        final double scaled = ((flat[plane + i] as num).toDouble() + 1.0) * 127.5;
        rgb[out] = scaled <= 0
            ? 0
            : scaled >= 255
                ? 255
                : scaled.round();
      }
    }
    return rgb;
  }

  Future<void> releaseDecoder() async {
    final OrtSession? session = _decoder;
    _decoder = null;
    await session?.close();
  }

  /// Drops both entropy graphs. Callers ask for "the entropy half"; which
  /// direction is resident is an implementation detail, and a decode that is
  /// about to create the synthesis session must not leave the send-side graph
  /// behind because it never used it.
  Future<void> releaseEntropy() async {
    final OrtSession? a = _entropyEncode;
    final OrtSession? b = _entropyDecode;
    _entropyEncode = null;
    _entropyDecode = null;
    await a?.close();
    await b?.close();
  }

  /// Called when the platform reports memory pressure.
  Future<void> releaseForMemoryPressure() async {
    await releaseDecoder();
    await releaseEntropy();
  }

  Future<void> dispose() async {
    _disposed = true;
    await releaseDecoder();
    await releaseEntropy();
    _coders = null;
  }

  void _checkAlive() {
    if (_disposed) throw const AeicUnavailable('the codec has been disposed');
  }
}
