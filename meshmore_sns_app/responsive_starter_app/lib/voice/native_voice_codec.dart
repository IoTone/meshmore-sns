// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'c2_bridge_bindings.dart';
import 'voice_codec.dart';
import 'voice_frame_packer.dart';

/// The native function the finalizer calls to free a handle.
///
/// A finalizer's callback takes a `void*`, which is the same ABI as the shim's
/// `struct c2_bridge *`: both are one pointer, so the symbol can be looked up
/// under that signature without a trampoline.
typedef _CloseNative = ffi.Void Function(ffi.Pointer<ffi.Void>);

/// The Codec 2 implementation behind [VoiceCodec], over the two shipped
/// libraries.
///
/// `libcodec2.so` is upstream Codec 2 1.2.0 unpatched and `libcodec2bridge.so`
/// is our MIT shim; they are separate on purpose — LGPL 2.1 §6(b) leans on the
/// codec staying a distinct, individually replaceable object — and this file is
/// the only place the app opens either of them.
///
/// Two load-time facts shape it:
///
/// * **Missing libraries are a condition, not a crash.** A host test has no
///   `libcodec2.so`, and an ABI the build did not cover has none either. So
///   [isAvailable] answers, every call refuses with
///   [VoiceFailure.codecUnavailable], and importing this file is safe
///   anywhere.
/// * **A handle owns native memory.** Codec 2 builds pitch and FFT tables in
///   `codec2_create`, so a dropped handle without a close would leak them. Each
///   [NativeVoiceHandle] attaches to a [ffi.NativeFinalizer] built from the
///   shim's own `c2_bridge_close`, and closing detaches first so it frees once.
final class NativeVoiceCodec implements VoiceCodec {
  /// [codecLibrary] exists for a test that has the libraries somewhere the
  /// loader does not look; production passes nothing.
  NativeVoiceCodec({ffi.DynamicLibrary? codecLibrary})
      : _bridge = _loadBridge(codecLibrary);

  final C2Bridge? _bridge;

  /// Built from the loaded shim, so it exists only where a codec does.
  late final ffi.NativeFinalizer? _finalizer = _makeFinalizer();

  @override
  bool get isAvailable => _bridge != null;

  /// Opens [mode], or throws when this build does not carry it.
  ///
  /// `c2_bridge_open` returns NULL for a mode that was not compiled in — the
  /// shim passes Codec 2's own refusal through rather than inventing one — and
  /// that is reported as [VoiceFailure.modeUnavailable], which is a different
  /// fact from the library being absent.
  NativeVoiceHandle open(VoiceMode mode) {
    final C2Bridge? b = _bridge;
    if (b == null) {
      throw const VoiceException(
          VoiceFailure.codecUnavailable, 'this build has no voice codec');
    }
    final ffi.Pointer<c2_bridge> handle = b.c2_bridge_open(mode.codec2Id);
    if (handle == ffi.nullptr) {
      throw VoiceException(VoiceFailure.modeUnavailable,
          'mode ${mode.label} is not compiled into this build');
    }
    return NativeVoiceHandle._(b, handle, mode, _finalizer);
  }

  @override
  PackedVoice encode(Uint8List pcm, {required VoiceMode mode}) {
    final NativeVoiceHandle h = open(mode);
    try {
      return h.encodeAll(pcm);
    } finally {
      h.close();
    }
  }

  @override
  Uint8List decode(Uint8List packed,
      {required VoiceMode mode, double ber = 0}) {
    final NativeVoiceHandle h = open(mode);
    try {
      return h.decodeAll(packed, ber: ber);
    } finally {
      h.close();
    }
  }

  /// The two libraries, in the order they must load.
  ///
  /// The shim links against the codec, so the codec is opened first: on Android
  /// the loader resolves the shim's dependency from what is already mapped. Any
  /// failure of either file means no codec, which is reported rather than
  /// thrown so a device without the library still runs the rest of the app.
  static C2Bridge? _loadBridge(ffi.DynamicLibrary? codecLibrary) {
    try {
      final ffi.DynamicLibrary codec =
          codecLibrary ?? ffi.DynamicLibrary.open('libcodec2.so');
      if (codec.handle == ffi.nullptr) return null;
      return C2Bridge(ffi.DynamicLibrary.open('libcodec2bridge.so'));
    } on ArgumentError {
      return null;
    }
  }

  ffi.NativeFinalizer? _makeFinalizer() {
    // The finalizer wants a bare function pointer, and the generated class
    // keeps its pointers private, so the symbol is looked up once here.
    try {
      final ffi.DynamicLibrary shim =
          ffi.DynamicLibrary.open('libcodec2bridge.so');
      return ffi.NativeFinalizer(
          shim.lookup<ffi.NativeFunction<_CloseNative>>('c2_bridge_close'));
    } on ArgumentError {
      return null;
    }
  }
}

/// A Codec 2 handle for one mode, closed explicitly or by the finalizer.
///
/// Public because a caller encoding a whole recording wants one open handle for
/// the loop: `codec2_create` builds tables, and the per-frame work is
/// microseconds, so reopening per frame would invert that ratio.
final class NativeVoiceHandle implements ffi.Finalizable {
  NativeVoiceHandle._(
      this._bridge, this._handle, this.mode, ffi.NativeFinalizer? finalizer)
      : samplesPerFrame = _bridge.c2_bridge_samples_per_frame(_handle),
        bytesPerFrame = _bridge.c2_bridge_bytes_per_frame(_handle),
        bitsPerFrame = _bridge.c2_bridge_bits_per_frame(_handle),
        usesBer = _bridge.c2_bridge_uses_ber(_handle) == 1 {
    _finalizer = finalizer;
    _finalizer?.attach(this, _handle.cast(), detach: this);
  }

  final C2Bridge _bridge;
  final ffi.Pointer<c2_bridge> _handle;
  final VoiceMode mode;
  ffi.NativeFinalizer? _finalizer;

  /// What the library reports, which must agree with [VoiceMode]: a mismatch
  /// means the vendored source and the Dart table have drifted, and the packer
  /// would then lay frames out at the wrong width.
  final int samplesPerFrame;
  final int bytesPerFrame;
  final int bitsPerFrame;

  /// True for the mode where a bit-error estimate changes the decode.
  final bool usesBer;

  bool _closed = false;

  bool get isOpen => !_closed;

  /// Bytes of 8 kHz 16-bit PCM one frame decodes to.
  int get pcmBytesPerFrame => samplesPerFrame * 2;

  /// Encodes [pcm] (16-bit mono, 8 kHz) into packed frames.
  PackedVoice encodeAll(Uint8List pcm) {
    if (pcm.isEmpty) {
      return PackedVoice(
          mode: mode, bytes: Uint8List(0), frames: 0, samples: 0);
    }
    if (pcm.length % pcmBytesPerFrame != 0) {
      throw VoiceException(
          VoiceFailure.badFrame,
          'PCM is ${pcm.length} bytes, not a whole number of '
              '$pcmBytesPerFrame-byte frames');
    }
    final int frames = pcm.length ~/ pcmBytesPerFrame;
    final List<Uint8List> encoded = <Uint8List>[];
    final ffi.Pointer<ffi.Int16> speech = calloc<ffi.Int16>(samplesPerFrame);
    final ffi.Pointer<ffi.Uint8> out = calloc<ffi.Uint8>(bytesPerFrame);
    try {
      for (int f = 0; f < frames; f++) {
        // The recorder writes host-order samples and every shipped Android ABI
        // is little-endian, so reading them as `Endian.host` is exact rather
        // than a conversion.
        final ByteData view = ByteData.sublistView(
            pcm, f * pcmBytesPerFrame, (f + 1) * pcmBytesPerFrame);
        for (int i = 0; i < samplesPerFrame; i++) {
          speech[i] = view.getInt16(i * 2, Endian.host);
        }
        final int written = _bridge.c2_bridge_encode(_handle, speech, out);
        if (written < 0) {
          throw const VoiceException(
              VoiceFailure.badFrame, 'the codec refused a frame');
        }
        // Copied out of native memory before the arena is freed.
        encoded.add(Uint8List.fromList(out.asTypedList(bytesPerFrame)));
      }
    } finally {
      calloc.free(speech);
      calloc.free(out);
    }
    return PackedVoice(
      mode: mode,
      bytes: VoiceFramePacker.pack(encoded,
          bitsPerFrame: bitsPerFrame, bytesPerFrame: bytesPerFrame),
      frames: frames,
      samples: frames * samplesPerFrame,
    );
  }

  /// Decodes packed [packed] back to 16-bit mono PCM at 8 kHz.
  Uint8List decodeAll(Uint8List packed, {double ber = 0}) {
    final List<Uint8List> frames = VoiceFramePacker.unpack(packed,
        bitsPerFrame: bitsPerFrame, bytesPerFrame: bytesPerFrame);
    final Uint8List pcm = Uint8List(frames.length * pcmBytesPerFrame);
    if (frames.isEmpty) return pcm;
    final ByteData out = ByteData.sublistView(pcm);
    final ffi.Pointer<ffi.Uint8> bytes = calloc<ffi.Uint8>(bytesPerFrame);
    final ffi.Pointer<ffi.Int16> speech = calloc<ffi.Int16>(samplesPerFrame);
    try {
      for (int f = 0; f < frames.length; f++) {
        bytes.asTypedList(bytesPerFrame).setAll(0, frames[f]);
        final int produced = usesBer
            ? _bridge.c2_bridge_decode_ber(_handle, bytes, speech, ber)
            : _bridge.c2_bridge_decode(_handle, bytes, speech);
        if (produced < 0) {
          throw const VoiceException(
              VoiceFailure.badFrame, 'the codec refused a frame');
        }
        for (int i = 0; i < samplesPerFrame; i++) {
          out.setInt16((f * samplesPerFrame + i) * 2, speech[i], Endian.host);
        }
      }
    } finally {
      calloc.free(bytes);
      calloc.free(speech);
    }
    return pcm;
  }

  /// Releases the codec now. Idempotent, and detaches the finalizer first so
  /// the free cannot happen twice.
  void close() {
    if (_closed) return;
    _closed = true;
    _finalizer?.detach(this);
    _bridge.c2_bridge_close(_handle);
  }

  /// What the shim reports it carries, for logs and the licence notice.
  String version() => _bridge.c2_bridge_version().cast<Utf8>().toDartString();
}
