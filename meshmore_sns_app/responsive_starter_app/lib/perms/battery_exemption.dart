// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Whether Android is allowed to stop this app while it is in the background.
///
/// The keep-alive is a foreground service, and a foreground service is not a
/// guarantee: an OEM's battery management can stop one that is not on the
/// battery-optimisation exemption list. The app could not see that state, so
/// "I get no notifications" had no answer anywhere in the UI
/// (`docs/MISSING-WORK.md` §9).
enum BatteryExemption {
  /// The OS will not optimise this app, so the service is left alone.
  exempt,

  /// The OS may stop the app once the screen has been off for a while.
  optimised,

  /// The platform cannot answer. The app then says nothing rather than
  /// painting a warning that may be false, the same rule the notification
  /// health row follows for a channel it cannot read.
  unavailable,
}

/// The one place the app asks whether the OS will let it stay awake.
///
/// Behind an interface so a widget test never reaches the plugin, and so the
/// three states can be exercised without a handset.
abstract class BatteryExemptionService {
  Future<BatteryExemption> read();

  /// Opens the OS request. True means the OS accepted the request, not that
  /// the user granted it: the answer is whatever [read] says afterwards.
  Future<bool> request();
}

/// Android, through the `flutter_foreground_task` plugin the keep-alive
/// already depends on (9.2.2 exposes `isIgnoringBatteryOptimizations` and
/// `requestIgnoreBatteryOptimization`), so this costs no new native code and
/// no second permission.
class PlatformBatteryExemption implements BatteryExemptionService {
  const PlatformBatteryExemption();

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<BatteryExemption> read() async {
    if (!_isAndroid) return BatteryExemption.unavailable;
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations
          ? BatteryExemption.exempt
          : BatteryExemption.optimised;
    } catch (_) {
      // A plugin that cannot answer is not evidence of a problem.
      return BatteryExemption.unavailable;
    }
  }

  @override
  Future<bool> request() async {
    if (!_isAndroid) return false;
    try {
      return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {
      return false;
    }
  }
}
