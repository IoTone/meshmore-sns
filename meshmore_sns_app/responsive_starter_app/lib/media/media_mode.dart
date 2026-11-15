// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:shared_preferences/shared_preferences.dart';

import 'aeic_codec_service.dart' show kAeicWireAvailable;

import '../util/prefs.dart';

/// What this app does with a photograph.
///
/// A mesh has one budget and a picture is the most expensive thing on it, so the
/// reader chooses where the pixels go. Three answers, in the order they cost:
///
/// - [preview] — one 0xFF50 datagram of an MP1 palette preview (about 100–200
///   bytes). Every client that speaks MP1 draws it, the pixels are discarded.
/// - [onRequest] — the same preview, and the full picture is *held* for fifteen
///   minutes: someone who taps the preview gets the pixels over a direct record
///   (0x19 chunks), because a flood of a full picture is everyone's airtime on
///   something most of them did not ask for.
/// - [neural] — MeshCore Open's AEIC bitstream (data type `0xAE1C`): the whole
///   512×512 picture in a few kilobytes, flooded on the channel. It needs the
///   codec's model bundle installed (about 1 GB, MIT, downloaded on demand) and
///   it is the only mode this app cannot run without that bundle.
///
/// The default is [onRequest]: a preview costs one datagram and the upgrade is
/// only paid by the one reader who wants the picture.
enum MediaMode {
  preview(
    'preview',
    /// Roughly one datagram.
    bytes: '~150 B',
    quality: 'Palette preview',
  ),
  onRequest(
    'onRequest',
    bytes: '~4 KB on request',
    quality: 'Full picture, direct only',
  ),
  neural(
    'neural',
    bytes: '~3 KB',
    quality: '512×512, every reading client',
  );

  const MediaMode(this.id, {required this.bytes, required this.quality});

  /// Stable id for storage. Not the enum index: a mode added in the middle must
  /// not silently reinterpret a stored choice.
  final String id;

  /// What one picture costs, as the setting states it.
  final String bytes;

  /// What the reader gets for it.
  final String quality;

  static MediaMode fromId(String? id) => MediaMode.values.firstWhere(
        (MediaMode m) => m.id == id,
        orElse: () => MediaMode.onRequest,
      );
}

/// Whether this build can run the neural codec.
///
/// True: the rANS coder, the entropy layer and the ONNX sessions are all in the
/// build. What remains is a *device* question, not a build one — the model
/// bundle has to be installed — so the settings row offers the mode only once
/// the installer reports [AeicState.ready].
const bool kAeicEncodeAvailable = kAeicWireAvailable;

/// The stored choice, and the colour switch beside it.
///
/// Both are preferences rather than policy: the public-channel gate and the
/// airtime meter are policy and live in `media_send_policy.dart`, which no
/// preference can loosen.
abstract final class MediaModePrefs {
  static const String _kMode = 'mm.media.photoMode';

  static Future<MediaMode> photoMode() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return MediaMode.fromId(Prefs.readString(p, _kMode));
  }

  static Future<void> setPhotoMode(MediaMode v) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await Prefs.setString(p, _kMode, v.id);
  }
}
