// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/geofence/geofence_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/tools/soak_tool.dart';
import 'package:meshmore_sns_app/tools/tools_controller.dart';
import 'package:meshmore_sns_app/util/safe_notifier.dart';

import '../meshcore/fake_transport.dart';

class _Notifier extends ChangeNotifier with SafeNotifier {}

/// Four notifiers notify from a continuation that can land after the widget
/// tree is gone: a store write finishing, a geofence timer firing, a tool run
/// releasing the radio. `ChangeNotifier` asserts in debug on a notification
/// after disposal, so the sequence that is a harmless no-op in release threw out
/// of the framework in a debug test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  MeshcoreController idleController() =>
      MeshcoreController(
          transportFactory: () async => FakeMeshcoreTransport());

  test('the mixin makes a late notification a no-op', () {
    final _Notifier n = _Notifier();
    int calls = 0;
    n.addListener(() => calls++);
    n.notifyListeners();
    n.dispose();
    expect(n.isDisposed, isTrue);
    expect(n.notifyListeners, returnsNormally);
    expect(calls, 1, reason: 'the late notification reached no listener');
  });

  test('PlaceStore survives a report that lands after disposal', () {
    final PlaceStore store = PlaceStore();
    store.dispose();
    expect(store.notifyListeners, returnsNormally);
  });

  test('GeofenceController survives a load that finishes after disposal',
      () async {
    final MeshcoreController mc = idleController();
    final GeofenceController gc =
        GeofenceController(mc: mc, autoTick: false);
    final Future<void> loading = gc.load();
    gc.dispose();
    await expectLater(loading, completes);
    expect(gc.notifyListeners, returnsNormally);
    mc.dispose();
  });

  test('ToolsController survives a release after disposal', () {
    final MeshcoreController mc = idleController();
    final ToolsController tools = ToolsController(mc);
    tools.dispose();
    expect(tools.notifyListeners, returnsNormally);
    mc.dispose();
  });

  test('SoakTool inherits the guard from MeshTool, so it needs no second one',
      () {
    // SoakTool extends MeshTool, which already dropped late notifications
    // before this mixin existed. Pinned so a future refactor of MeshTool
    // cannot quietly remove the guard from every tool at once.
    final MeshcoreController mc = idleController();
    final SoakTool soak = SoakTool(mc);
    soak.dispose();
    expect(soak.notifyListeners, returnsNormally);
    mc.dispose();
  });
}
