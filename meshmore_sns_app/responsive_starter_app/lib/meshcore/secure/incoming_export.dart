// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/services.dart';

/// An export file the user opened or shared into the app.
///
/// The sealed store's key cannot leave the phone, so a reinstall or a new
/// device has exactly one way back: the passphrase file the user still holds.
/// Android hands us that file as a `content://` stream, the platform side
/// stages it to a private path, and this is the one read of that path — the
/// staged copy is consumed so a second launch does not offer it again.
abstract final class IncomingExport {
  static const MethodChannel channel = MethodChannel('meshmore/share');

  /// The staged file, or null when nothing arrived. Never throws: a share
  /// that could not be read is the same as no share, and the restore surface
  /// already words that.
  static Future<String?> take() async {
    try {
      return await channel.invokeMethod<String>('takeIncomingFile');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
