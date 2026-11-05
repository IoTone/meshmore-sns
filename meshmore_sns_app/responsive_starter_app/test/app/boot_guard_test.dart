// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/app/boot_guard.dart';

/// L1 — the boot chain is guarded, so a throw or a hung platform channel can
/// no longer leave the branded splash on screen with no message.
void main() {
  test('a successful boot leaves the splash to the first frame', () async {
    int exits = 0;
    Object? failed;

    await runBoot(
      boot: () async {},
      onFailed: (Object error) => failed = error,
      leaveSplash: () => exits++,
    );

    expect(failed, isNull);
    expect(exits, 0,
        reason: 'MyApp removes the splash after its first frame; a guard that '
            'also removed it would flash the panel underneath');
  });

  test('a throwing boot exits the splash once and reports the error', () async {
    int exits = 0;
    Object? failed;

    await runBoot(
      boot: () async => throw StateError('prefs unavailable'),
      onFailed: (Object error) => failed = error,
      leaveSplash: () => exits++,
    );

    expect(failed, isA<StateError>());
    expect(exits, 1);
  });

  test('a boot that never finishes is caught by the watchdog', () async {
    int exits = 0;
    Object? failed;
    final Completer<void> hung = Completer<void>();

    await runBoot(
      boot: () => hung.future,
      onFailed: (Object error) => failed = error,
      leaveSplash: () => exits++,
      watchdog: const Duration(milliseconds: 5),
    );

    expect(failed, isA<TimeoutException>());
    expect(exits, 1);

    // The boot finishing later must not repaint the panel or double-report.
    hung.complete();
    await Future<void>.delayed(Duration.zero);
    expect(exits, 1);
  });

  test('a late failure after the watchdog fired does not report twice',
      () async {
    int reports = 0;
    final Completer<void> slowFailure = Completer<void>();

    await runBoot(
      boot: () => slowFailure.future,
      onFailed: (Object _) => reports++,
      leaveSplash: () {},
      watchdog: const Duration(milliseconds: 5),
    );
    slowFailure.completeError(StateError('too late'));
    await Future<void>.delayed(Duration.zero);

    expect(reports, 1);
  });

  testWidgets('the failure panel names the reason and retries on demand',
      (WidgetTester tester) async {
    int retries = 0;
    await tester.pumpWidget(BootFailureApp(
      message: 'SharedPreferences platform failure',
      onRetry: () => retries++,
    ));

    expect(find.text('Meshmore SNS could not start.'), findsOneWidget);
    expect(find.text('SharedPreferences platform failure'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(retries, 1);
  });
}
