// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// A `RESP_CODE_DEFAULT_FLOOD_SCOPE` (0x1C) reply: opcode, a 31-byte
/// NUL-padded name and the 16-byte scope key (`MyMesh.cpp` writes both).
Uint8List scopeReply(String name) {
  final Uint8List frame = Uint8List(1 + 31 + 16);
  frame[0] = 0x1C;
  final List<int> bytes = name.codeUnits;
  for (int i = 0; i < bytes.length && i < 31; i++) {
    frame[1 + i] = bytes[i];
  }
  for (int i = 0; i < 16; i++) {
    frame[1 + 31 + i] = i + 1;
  }
  return frame;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('connect asks for the radio\'s default flood scope (D8.1)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    await mc.connect();
    fake.emit(selfInfoFrame());
    for (int i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(fake.sent.any((Uint8List f) => f.isNotEmpty && f[0] == 0x40), isTrue,
        reason: 'CMD_GET_DEFAULT_FLOOD_SCOPE is how the app learns the reach');
    mc.dispose();
  });

  test('the reply becomes a scope name, and an empty reply means none is set',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);
    expect(mc.floodScopeName, isNull,
        reason: 'unknown until the radio answers, not "none"');
    fake.emit(scopeReply('north-denver'));
    await Future<void>.delayed(Duration.zero);
    expect(mc.floodScopeName, 'north-denver');
    fake.emit(scopeReply(''));
    await Future<void>.delayed(Duration.zero);
    expect(mc.floodScopeName, '',
        reason: 'an empty reply is a stated absence, not an unknown');
    mc.dispose();
  });
}
