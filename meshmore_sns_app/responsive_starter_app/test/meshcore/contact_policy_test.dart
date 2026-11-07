// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// Three commands the codec has always been able to build and the app never
/// sent. Each is the only way to answer a question the app was guessing at:
///
/// * `CMD_GET_AUTOADD_CONFIG` (0x3B) — which node types the radio stores by
///   itself, whether it may overwrite the oldest non-favourite when the table
///   is full, and how far away a node may be. Without it the table fills under
///   a policy the user cannot see.
/// * `CMD_SET_AUTOADD_CONFIG` (0x3A) — the whole byte at once, so a partial
///   change has to carry the rest through, and writing from an unknown state
///   would switch auto-add off for every type.
/// * `CMD_GET_ADVERT_PATH` (0x2A) — the route the last advert took, which costs
///   no airtime and is the cheap answer to "which repeaters hear this node".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle() async {
    for (int i = 0; i < 8; i++) {
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

  /// `RESP_CODE_AUTOADD_CONFIG` (0x19): `[19][flags][max_hops]`.
  Uint8List autoAddFrame(int flags, int maxHops) =>
      Uint8List.fromList(<int>[0x19, flags, maxHops]);

  /// `RESP_CODE_ADVERT_PATH` (0x16):
  /// `[16][recv_ts u32 LE][path_len][path hashes]`.
  Uint8List advertPathFrame(int ts, List<int> path, {int hashSize = 1}) {
    final int pathLen = ((hashSize - 1) << 6) | (path.length ~/ hashSize);
    return Uint8List.fromList(<int>[
      0x16,
      ts & 0xFF,
      (ts >> 8) & 0xFF,
      (ts >> 16) & 0xFF,
      (ts >> 24) & 0xFF,
      pathLen,
      ...path,
    ]);
  }

  group('the radio\'s own add policy', () {
    test('the policy is read, and says what it means', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(fake);
      expect(mc.autoAddConfig, isNull, reason: 'nothing has been read yet');

      await mc.requestAutoAddConfig();
      expect(
          fake.sent.any((Uint8List f) =>
              f.isNotEmpty && f[0] == MeshcoreCommand.getAutoAddConfig.code),
          isTrue);

      fake.emit(autoAddFrame(0x01 | 0x02 | 0x04, 3));
      await settle();
      final AutoAddConfig? cfg = mc.autoAddConfig;
      expect(cfg, isNotNull);
      expect(cfg!.overwriteOldest, isTrue);
      expect(cfg.chat, isTrue);
      expect(cfg.repeater, isTrue);
      expect(cfg.roomServer, isFalse);
      expect(cfg.sensor, isFalse);
      expect(cfg.maxHops, 3);
      mc.dispose();
    });

    test('a change carries the other bits through and reads back', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(fake);
      await mc.requestAutoAddConfig();
      fake.emit(autoAddFrame(0x02, 5));
      await settle();

      fake.sent.clear();
      expect(await mc.setAutoAddConfig(sensor: true), isTrue);
      final Uint8List set = fake.sent.firstWhere((Uint8List f) =>
          f.isNotEmpty && f[0] == MeshcoreCommand.setAutoAddConfig.code);
      expect(set[1], 0x02 | 0x10,
          reason: 'chat stays on, sensor is added, nothing else moves');
      expect(set[2], 5, reason: 'the hop limit is carried, not reset to zero');
      expect(
          fake.sent.any((Uint8List f) =>
              f.isNotEmpty && f[0] == MeshcoreCommand.getAutoAddConfig.code),
          isTrue,
          reason: 'the radio clamps and may refuse, so its answer is the truth');
      mc.dispose();
    });

    test('a write from an unread policy is refused, not guessed', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(fake);
      fake.sent.clear();
      expect(await mc.setAutoAddConfig(chat: true), isFalse,
          reason: 'writing from zero would switch auto-add off entirely');
      expect(
          fake.sent.any((Uint8List f) =>
              f.isNotEmpty && f[0] == MeshcoreCommand.setAutoAddConfig.code),
          isFalse);
      mc.dispose();
    });
  });

  group('the route the last advert took', () {
    test('a reply becomes the path, at the width the reply states', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(fake);
      const String key =
          'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899';

      final Future<AdvertPath?> pending = mc.advertPathFor(key);
      await settle();
      fake.emit(advertPathFrame(1700000000, <int>[0x11, 0x22], hashSize: 1));
      final AdvertPath? p = await pending;
      expect(p, isNotNull);
      expect(p!.pathLen.hashSize, 1);
      expect(p.pathLen.hopCount, 2);
      expect(p.path, <int>[0x11, 0x22]);
      expect(p.receivedAt, 1700000000);
      mc.dispose();
    });

    test('a request with no answer is null, not a hang', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(fake);
      const String key =
          'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899';
      expect(
          await mc.advertPathFor(key,
              timeout: const Duration(milliseconds: 40)),
          isNull);
      mc.dispose();
    });

    test('only one request is in flight, because the reply carries no key',
        () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(fake);
      const String key =
          'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899';
      final Future<AdvertPath?> first =
          mc.advertPathFor(key, timeout: const Duration(milliseconds: 200));
      await settle();
      expect(await mc.advertPathFor(key), isNull,
          reason: 'a second answer could not be told apart from the first');
      fake.emit(advertPathFrame(1700000001, <int>[0x33]));
      await first;
      mc.dispose();
    });
  });

  group('a retry clears a dead direct route first', () {
    test('a direct DM that failed is retried over flood', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(fake);
      // A contact with a direct route: `out_path_len` 0 is "in radio range",
      // which is the state a retry has to invalidate when the neighbour moved.
      fake.emit(contactFrame(name: 'Near', firstPubByte: 0x55, outPathLen: 0));
      await settle();
      const String peer =
          '55565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f7071727374';
      expect(mc.isSyncedContact(peer), isTrue);

      final ChatMessage? m = await mc.sendDirectText(peer, 'hello');
      expect(m, isNotNull);
      // The radio refuses the send; the row becomes retryable.
      fake.emit(Uint8List.fromList(<int>[0x01, 6]));
      await settle();
      expect(m!.delivery, MessageDelivery.failed);

      fake.sent.clear();
      expect(await mc.retryMessageOutcome(m.id), RetryOutcome.sentAfterPathReset);
      expect(
          fake.sent.any((Uint8List f) =>
              f.isNotEmpty && f[0] == MeshcoreCommand.resetPath.code),
          isTrue,
          reason: 'a dead route stays dead until something clears it');
      expect(
          fake.sent.any((Uint8List f) =>
              f.isNotEmpty && f[0] == MeshcoreCommand.getContactByKey.code),
          isTrue,
          reason: 'the app re-reads the record it just invalidated');
      expect(fake.sent.any((Uint8List f) => f.isNotEmpty && f[0] == 0x02), isTrue,
          reason: 'the message itself is still sent');
      mc.dispose();
    });

    test('a flood-addressed retry clears nothing', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(fake);
      // `out_path_len` 0xFF is the flood sentinel: there is no route to clear.
      fake.emit(
          contactFrame(name: 'Far', firstPubByte: 0x66, outPathLen: 0xFF));
      await settle();
      const String peer =
          '666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485';
      final ChatMessage? m = await mc.sendDirectText(peer, 'hello');
      fake.emit(Uint8List.fromList(<int>[0x01, 6]));
      await settle();
      fake.sent.clear();
      expect(await mc.retryMessageOutcome(m!.id), RetryOutcome.sent,
          reason: 'nothing to reset, so the retry is reported plainly');
      expect(
          fake.sent.any((Uint8List f) =>
              f.isNotEmpty && f[0] == MeshcoreCommand.resetPath.code),
          isFalse);
      mc.dispose();
    });
  });

  group('an add that the radio refuses', () {
    test('a full table is state, not a silent success', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(fake);
      fake.emit(contactFrame(name: 'Near', firstPubByte: 0x77));
      await settle();
      const String peer =
          '7778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f90919293949596';
      expect(await mc.addNodeAsDeviceContact(peer, name: 'Near'), isTrue,
          reason: 'the frames were written; the radio answers separately');
      expect(mc.contactsFull, isFalse);
      // `ERR_CODE_TABLE_FULL` (3): the radio could not store it.
      fake.emit(Uint8List.fromList(<int>[0x01, kErrTableFull]));
      await settle();
      expect(mc.contactsFull, isTrue,
          reason: 'a full table drops every new advert, so it has to be shown');
      mc.dispose();
    });
  });

  group('asking the mesh for a route', () {
    /// `PUSH_CODE_PATH_DISCOVERY_RESPONSE` (0x8D):
    /// `[8D][reserved][prefix 6][out_len][out path][in_len][in path]`.
    Uint8List discoveryFrame(List<int> prefix, List<int> out, List<int> back) =>
        Uint8List.fromList(<int>[
          0x8D,
          0x00,
          ...prefix,
          (out.length & 0x3F),
          ...out,
          (back.length & 0x3F),
          ...back,
        ]);

    test('a reply for this prefix is the route', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(fake);
      const String key =
          'a1b2c3d4e5f600112233445566778899aabbccddeeff00112233445566778899';
      final Future<PathDiscoveryResult?> pending =
          mc.discoverPathFor(key, timeout: const Duration(milliseconds: 500));
      await settle();
      expect(
          fake.sent.any((Uint8List f) =>
              f.isNotEmpty && f[0] == MeshcoreCommand.sendPathDiscoveryReq.code),
          isTrue);
      fake.emit(discoveryFrame(<int>[0xa1, 0xb2, 0xc3, 0xd4, 0xe5, 0xf6],
          <int>[0x11, 0x22], <int>[0x22, 0x11]));
      final PathDiscoveryResult? r = await pending;
      expect(r, isNotNull);
      expect(r!.outPath, <int>[0x11, 0x22]);
      expect(r.inPath, <int>[0x22, 0x11]);
      expect(r.outPathLen.hopCount, 2);
      mc.dispose();
    });

    test('an answer for another node is not this request', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(fake);
      const String key =
          'a1b2c3d4e5f600112233445566778899aabbccddeeff00112233445566778899';
      final Future<PathDiscoveryResult?> pending =
          mc.discoverPathFor(key, timeout: const Duration(milliseconds: 40));
      await settle();
      fake.emit(discoveryFrame(<int>[0x99, 0x88, 0x77, 0x66, 0x55, 0x44],
          <int>[0x01], <int>[]));
      expect(await pending, isNull,
          reason: 'the reply names a different prefix, so it is not an answer');
      mc.dispose();
    });
  });
}
