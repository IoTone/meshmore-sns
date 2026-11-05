// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';

/// Field diagnostics that have to reach `flutter logs` on a device.
///
/// These are `print` rather than `developer.log` because `developer.log` was
/// silent in an earlier device capture, and the lines exist to explain a radio
/// that is not behaving. They are compiled out of a release build: two of them
/// carry a key prefix or a position, and a release log is readable by anything
/// with logcat access. A debug build, which is how field reports are captured,
/// keeps every line.
const bool _fieldLog = kDebugMode;

void meshLog(String tag, String message) {
  if (!_fieldLog) return;
  // ignore: avoid_print
  print('[$tag] $message');
}
