// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Handing a file the app wrote to something that can actually open it.
///
/// The Android documents directory is app-private, so a path shown in a
/// snackbar is not an export: the user has no way to reach it. One channel
/// serves every export (the places ledger, the field record, a conversation),
/// and the platform side wraps the file in a `content://` URI so the receiving
/// app gets read access without the file being world-readable.
abstract final class Share {
  /// Overridable so a test can answer without a platform.
  @visibleForTesting
  static MethodChannel channel = const MethodChannel('meshmore/share');

  /// True when a share sheet was opened for [path].
  ///
  /// False means there is no platform side (a widget test, or a build with no
  /// share handler) or the intent could not be built; the caller then says
  /// where the file is instead of claiming it was shared.
  static Future<bool> file(
    String path, {
    required String mime,
    String? subject,
  }) async {
    try {
      final bool? opened =
          await channel.invokeMethod<bool>('shareFile', <String, Object?>{
        'path': path,
        'mime': mime,
        'subject': subject,
      });
      return opened ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// True when a share sheet was opened for [text].
  ///
  /// The text counterpart of [file], for a thing that is a sentence rather than
  /// a document: a place is an address, so sharing it shares the address and a
  /// link, not a CSV of everything the mesh once said. Same channel, so there
  /// is still one place that knows what a share intent looks like.
  static Future<bool> text(String text, {String? subject}) async {
    try {
      final bool? opened =
          await channel.invokeMethod<bool>('shareText', <String, Object?>{
        'text': text,
        'subject': subject,
      });
      return opened ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
