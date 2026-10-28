// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';
import 'package:meshcore/meshcore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `MeshcoreController`'s constructor kicks off unawaited
  // `_meshbook.load()` and `_dmReadStore.load()` chains that call
  // `notifyListeners()` when they land. Anything that constructs a
  // controller and disposes it before those land — a widget test, or a
  // flow that re-creates the controller — used to get
  // "A MeshcoreController was used after being disposed" thrown out of
  // `ChangeNotifier` while the pending notification was delivered.
  test('disposing before the constructor\'s pref loads land does not throw',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    // Dispose immediately, with no settle — this is the race.
    ctrl.dispose();

    // Now let the constructor's unawaited loads land. Without the
    // `_disposed` guard this flush delivers `notifyListeners()` to a
    // disposed notifier and the test framework reports the async throw.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  });
}