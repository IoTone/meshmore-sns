// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/radio_identity_store.dart';

import 'fake_transport.dart';

/// A SELF_INFO frame whose 32-byte public key starts with [first].
Uint8List selfInfoFrameWithKey(int first) {
  final Uint8List f = selfInfoFrame();
  // opcode, advType, txPower, maxTxPower, then the key.
  for (int i = 0; i < 32; i++) {
    f[4 + i] = (first + i) & 0xFF;
  }
  return f;
}

Future<MeshcoreController> _readyWith(
    FakeMeshcoreTransport fake, Uint8List frame) async {
  final MeshcoreController c = MeshcoreController(
    transportFactory: () async => fake,
    connection: MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await c.connect();
  fake.emit(frame);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('the first radio it meets is recorded, with nothing to report',
      () async {
    final MeshcoreController c = await _readyWith(
        FakeMeshcoreTransport(connected: true), selfInfoFrameWithKey(0x10));

    expect(c.radioChanged, isFalse);
    expect(await RadioIdentityStore.read(), c.ownPubKeyHex);
  });

  test('the same radio again reports no change', () async {
    final MeshcoreController first = await _readyWith(
        FakeMeshcoreTransport(connected: true), selfInfoFrameWithKey(0x10));
    final String key = first.ownPubKeyHex!;
    await RadioIdentityStore.save(key);

    final MeshcoreController again = await _readyWith(
        FakeMeshcoreTransport(connected: true), selfInfoFrameWithKey(0x10));

    expect(again.radioChanged, isFalse);
  });

  test('a different key is reported, and accepting it settles the record',
      () async {
    final MeshcoreController first = await _readyWith(
        FakeMeshcoreTransport(connected: true), selfInfoFrameWithKey(0x10));
    final String oldKey = first.ownPubKeyHex!;

    final MeshcoreController second = await _readyWith(
        FakeMeshcoreTransport(connected: true), selfInfoFrameWithKey(0x80));

    expect(second.radioChanged, isTrue,
        reason: 'the radio behind the link is not the one on record');
    expect(second.previousRadioKey, oldKey);

    await second.acceptRadioIdentity();
    expect(second.radioChanged, isFalse);
    expect(await RadioIdentityStore.read(), second.ownPubKeyHex);
  });

  test('an unprovisioned all-zero key is not a change', () async {
    // A radio that has never been provisioned reports zeros; recording that
    // as an identity would make every later real key look like a swap.
    await RadioIdentityStore.save('11' * 32);
    final MeshcoreController c = await _readyWith(
        FakeMeshcoreTransport(connected: true), selfInfoFrame());

    expect(c.radioChanged, isFalse);
  });
}
