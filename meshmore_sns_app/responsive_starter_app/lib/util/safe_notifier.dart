// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';

/// A [ChangeNotifier] that survives its own disposal.
///
/// Four classes already carried this guard written out by hand
/// (`MeshcoreController`, `MapsController`, `MeshTool`, `SosController`),
/// because each of them notifies from a continuation that can land after the
/// widget tree is gone: a store write finishing, a tool run releasing the radio,
/// a geofence timer firing. `ChangeNotifier` asserts in debug on a notification
/// after disposal, so the same sequence that is a no-op in release used to throw
/// out of the framework in a widget test.
///
/// `notifyListeners()` is overridden rather than every call site, so a subclass
/// cannot forget; a subclass that overrides [dispose] must call `super.dispose()`
/// to arm it.
mixin SafeNotifier on ChangeNotifier {
  bool _disposed = false;

  /// True once [dispose] has run.
  bool get isDisposed => _disposed;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
