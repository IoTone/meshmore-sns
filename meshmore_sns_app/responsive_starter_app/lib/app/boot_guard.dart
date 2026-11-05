// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

/// Runs the boot chain and guarantees the splash comes down either way.
///
/// The native splash is removed only after the first frame, so a throw between
/// [FlutterNativeSplash.preserve] and `runApp` used to leave the branded splash
/// on screen forever: no message, no action, indistinguishable from a hang.
/// This is the one place that promise is kept. The watchdog covers the case
/// where the chain neither finishes nor throws, which is a platform channel
/// that never answers.
///
/// [leaveSplash] and [watchdog] exist so a test can drive a throwing or a
/// hanging boot without a platform channel and without waiting seconds.
Future<void> runBoot({
  required Future<void> Function() boot,
  required void Function(Object error) onFailed,
  void Function()? leaveSplash,
  Duration watchdog = const Duration(seconds: 8),
}) async {
  final void Function() exitSplash = leaveSplash ?? FlutterNativeSplash.remove;
  bool settled = false;
  final Completer<void> done = Completer<void>();
  late final Timer timer;
  void settle(Object? error) {
    if (settled) return;
    settled = true;
    timer.cancel();
    if (error != null) {
      exitSplash();
      onFailed(error);
    }
    done.complete();
  }

  timer = Timer(watchdog, () {
    settle(TimeoutException('the app did not reach its first frame'));
  });
  // The boot's own future keeps running after a timeout, so its late failure
  // is captured here rather than escaping as an unhandled error.
  boot().then<void>((_) => settle(null),
      onError: (Object error, StackTrace _) => settle(error));
  await done.future;
}

/// What the user sees when the boot chain itself fails.
///
/// Theme-free on purpose: `ThemeController` is one of the things that can
/// fail, so the panel must not depend on the code that failed. The reason is
/// one line, and the one action is a retry, because the common cause is
/// transient.
class BootFailureApp extends StatelessWidget {
  const BootFailureApp({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Meshmore SNS could not start.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
