// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// The radio changes its own contact table, and the app has to follow.
///
/// Four pushes do it and all four were decoded by the codec and then ignored by
/// the controller: `PUSH_CODE_CONTACT_DELETED` (0x8F, the user removed a contact
/// or auto-add overwrote the oldest non-favourite), `PUSH_CODE_NEW_ADVERT`
/// (0x8A, the radio stored a newly advertised node by itself), `PUSH_CODE_PATH_UPDATED`
/// (0x81, it learned a new route) and `PUSH_CODE_CONTACTS_FULL` (0x90, it could
/// not store one at all). Ignoring them left the app showing contacts the radio
/// no longer has, hiding ones it does, addressing sends down a replaced route,
/// and failing to add anything with no explanation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A `PUSH_CODE_CONTACT_DELETED` (0x8F): opcode + the 32-byte key.
  Uint8List deletedFrame(int firstByte) => Uint8List.fromList(<int>[
        0x8F,
        for (int i = 0; i < kPubKeySize; i++) (firstByte + i) & 0xFF,
      ]);

  /// A `PUSH_CODE_PATH_UPDATED` (0x81): opcode + the 32-byte key.
  Uint8List pathUpdatedFrame(int firstByte) => Uint8List.fromList(<int>[
        0x81,
        for (int i = 0; i < kPubKeySize; i++) (firstByte + i) & 0xFF,
      ]);

  Future<void> settle() async {
    for (int i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<MeshcoreController> connected(FakeMeshcoreTransport fake) async {
    final MeshcoreController mc =
        MeshcoreController(transportFactory: () async => fake);
    await mc.connect();
    fake.emit(selfInfoFrame());
    await settle();
    return mc;
  }

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a contact the radio deleted stops being a contact', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(fake);
    fake.emit(contactFrame(name: 'Gone', firstPubByte: 0x20));
    await settle();
    final String hex =
        List<int>.generate(32, (int i) => (0x20 + i) & 0xFF)
            .map((int b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
    expect(mc.isSyncedContact(hex), isTrue);

    fake.emit(deletedFrame(0x20));
    await settle();
    expect(mc.isSyncedContact(hex), isFalse,
        reason: 'the radio no longer holds it, so it cannot be addressed');
    mc.dispose();
  });

  test('a newly advertised contact the radio stored is mirrored', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(fake);
    // 0x8A carries a full contact record, exactly as 0x03 does.
    final Uint8List stored = contactFrame(name: 'Auto', firstPubByte: 0x30);
    stored[0] = 0x8A;
    fake.emit(stored);
    await settle();
    final String hex =
        List<int>.generate(32, (int i) => (0x30 + i) & 0xFF)
            .map((int b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
    expect(mc.isSyncedContact(hex), isTrue,
        reason: 'auto-add stored it on the radio; the mirror must say so');
    expect(mc.nodes.any((dynamic n) => n.pubKeyHex == hex), isTrue);
    mc.dispose();
  });

  test('a changed route is re-read from the radio', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(fake);
    fake.emit(contactFrame(name: 'Moved', firstPubByte: 0x40));
    await settle();
    fake.sent.clear();
    fake.emit(pathUpdatedFrame(0x40));
    await settle();
    expect(
        fake.sent.any((Uint8List f) =>
            f.isNotEmpty && f[0] == MeshcoreCommand.getContactByKey.code),
        isTrue,
        reason: 'the app draws and addresses by the path, so it re-reads it');
    mc.dispose();
  });

  test('a full table is a state, not a log line', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(fake);
    expect(mc.contactsFull, isFalse);
    fake.emit(Uint8List.fromList(<int>[0x90]));
    await settle();
    expect(mc.contactsFull, isTrue);
    mc.dispose();
  });
}
