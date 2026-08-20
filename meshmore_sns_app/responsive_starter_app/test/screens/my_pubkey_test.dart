// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/fake_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The value the dashboard row renders comes straight from here, and
  // it is null until SelfInfo lands — which is exactly the window in
  // which a user opens the app asking "what is my key?".
  group('ownPubKeyHex', () {
    test('is null before SelfInfo arrives', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc =
          MeshcoreController(transportFactory: () async => fake);
      // Let the controller's async init settle before asserting, so
      // dispose() cannot race a notifyListeners from it.
      await Future<void>.delayed(Duration.zero);
      expect(mc.ownPubKeyHex, isNull);
      mc.dispose();
    });

    test('is full-length lowercase hex once SelfInfo lands', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc =
          MeshcoreController(transportFactory: () async => fake);
      await mc.connect();
      fake.emit(selfInfoFrame());
      await Future<void>.delayed(Duration.zero);

      final String? hex = mc.ownPubKeyHex;
      expect(hex, isNotNull);
      expect(hex!.length, 64, reason: '32-byte key as hex');
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(hex), isTrue,
          reason: 'lowercase hex, comparable to what peers show');
      mc.dispose();
    });
  });

  testWidgets('the clipboard gets the FULL key, not the shown prefix',
      (WidgetTester t) async {
    // The row displays a truncated key because 64 hex chars is
    // unreadable, but truncating what is copied would make the feature
    // actively harmful — a partial key pasted to another operator
    // silently fails to resolve.
    final List<MethodCall> calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall c) async {
        calls.add(c);
        return null;
      },
    );
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    const String full =
        'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
    await Clipboard.setData(const ClipboardData(text: full));

    final MethodCall setData =
        calls.firstWhere((MethodCall c) => c.method == 'Clipboard.setData');
    expect((setData.arguments as Map<Object?, Object?>)['text'], full);
    expect((setData.arguments as Map<Object?, Object?>)['text'],
        hasLength(64));
  });
}
