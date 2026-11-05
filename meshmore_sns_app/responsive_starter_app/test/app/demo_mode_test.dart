// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/app/demo_mode.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('the mode is off until it is chosen', () async {
    final DemoMode d = DemoMode();
    await d.load();
    expect(d.enabled, isFalse);
  });

  test('choosing it survives a launch', () async {
    final DemoMode d = DemoMode();
    await d.load();
    await d.setEnabled(true);

    final DemoMode next = DemoMode();
    await next.load();
    expect(next.enabled, isTrue,
        reason: 'a demo launch must not reach for a radio on the next start');
  });

  test('leaving it calls back so the radio can reconnect without a relaunch',
      () async {
    final DemoMode d = DemoMode();
    await d.load();
    await d.setEnabled(true);

    int calls = 0;
    await d.setEnabled(false, onDisabled: () => calls++);
    expect(d.enabled, isFalse);
    expect(calls, 1);
  });

  test('setting the same value twice does nothing', () async {
    final DemoMode d = DemoMode.preloaded(enabled: true);
    int calls = 0;
    await d.setEnabled(true, onDisabled: () => calls++);
    expect(calls, 0);
  });
}
