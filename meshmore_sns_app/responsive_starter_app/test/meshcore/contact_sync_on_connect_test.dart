// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

Uint8List endOfContactsAt(int lastmod) => Uint8List.fromList(<int>[
      0x04,
      lastmod & 0xFF,
      (lastmod >> 8) & 0xFF,
      (lastmod >> 16) & 0xFF,
      (lastmod >> 24) & 0xFF,
    ]);

/// `CMD_GET_CONTACTS` (0x04) with an optional little-endian `since`.
List<int>? getContactsFrame(List<Uint8List> sent) {
  for (final Uint8List f in sent) {
    if (f.isNotEmpty && f[0] == 0x04) return f.toList();
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the contact table is asked for on connect', () {
    test('a fresh app asks for the whole table', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc =
          MeshcoreController(transportFactory: () async => fake);
      await mc.connect();
      fake.emit(selfInfoFrame());
      for (int i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final List<int>? frame = getContactsFrame(fake.sent);
      expect(frame, isNotNull,
          reason: 'the radio never pushes its table (MyMesh.cpp:2209)');
      expect(frame!.length, 1,
          reason: 'no `since` until the radio has told us its lastmod');
      mc.dispose();
    });

    test('the radio\'s lastmod is remembered and used as `since`', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc =
          MeshcoreController(transportFactory: () async => fake);
      await mc.connect();
      fake.emit(selfInfoFrame());
      for (int i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      fake.emit(endOfContactsAt(0x0A0B0C));
      for (int i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(mc.contactsSinceForTest, 0x0A0B0C);
      final SharedPreferences p = await SharedPreferences.getInstance();
      expect(p.getInt('mm.contacts.since'), 0x0A0B0C,
          reason: 'the token must survive the restart that follows a drive');

      // A fresh controller on the same preferences — the restart case — asks
      // only for what changed.
      final FakeMeshcoreTransport second =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc2 =
          MeshcoreController(transportFactory: () async => second);
      await mc2.connect();
      second.emit(selfInfoFrame());
      for (int i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final List<int>? frame = getContactsFrame(second.sent);
      expect(frame, isNotNull);
      expect(frame!.length, 5, reason: 'opcode plus a four-byte since');
      final int since = frame[1] |
          (frame[2] << 8) |
          (frame[3] << 16) |
          (frame[4] << 24);
      expect(since, 0x0A0B0C);
      mc.dispose();
      mc2.dispose();
    });
  });
}
