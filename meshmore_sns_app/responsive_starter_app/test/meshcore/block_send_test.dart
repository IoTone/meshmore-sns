// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// A block is the app's filter, and the send path used to ignore it.
///
/// `BlockStore` was read by the timeline, the roster, the map, search, speech
/// and the notifier, and by nothing on the way out: a blocked peer could be
/// messaged from the very thread the block was meant to close, and the reply
/// that came back was hidden with no sign that it would be. The composer now
/// refuses and says why, and the controller refuses for every caller that is
/// not a composer.
const String _blocked =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
const String _open =
    'b1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

Future<MeshcoreController> _ready(
  FakeMeshcoreTransport fake,
  BlockStore blocks,
) async {
  final MeshcoreController c = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    isBlocked: blocks.isBlocked,
  );
  await c.connect();
  fake.emit(selfInfoFrame());
  await Future<void>.delayed(Duration.zero);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a DM to a blocked key is refused, and no row is written', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final BlockStore blocks = BlockStore(seed: <String, BlockedKey>{
      _blocked: BlockedKey(pubKeyHex: _blocked, sinceMs: 1),
    });
    final MeshcoreController c = await _ready(fake, blocks);
    // The link's own housekeeping (clock, device info, channel probe) is
    // already on the wire, so the assertion is about what the send adds.
    final int before = fake.sent.length;

    final ChatMessage? m = await c.sendDirectText(_blocked, 'hello');
    expect(m, isNull, reason: 'a refused send has nothing to show or retry');
    expect(c.dmHistoryFor(_blocked), isEmpty,
        reason: 'a row would claim a message the reader asked not to carry');
    expect(fake.sent.length, before,
        reason: 'and nothing reached the radio');
    c.dispose();
  });

  test('the same text to an unblocked key still goes', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final BlockStore blocks = BlockStore(seed: <String, BlockedKey>{
      _blocked: BlockedKey(pubKeyHex: _blocked, sinceMs: 1),
    });
    final MeshcoreController c = await _ready(fake, blocks);
    final int before = fake.sent.length;

    final ChatMessage? m = await c.sendDirectText(_open, 'hello');
    expect(m, isNotNull);
    expect(fake.sent.length, greaterThan(before));
    c.dispose();
  });

  test('unblocking restores sending', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final BlockStore blocks = BlockStore(seed: <String, BlockedKey>{
      _blocked: BlockedKey(pubKeyHex: _blocked, sinceMs: 1),
    });
    final MeshcoreController c = await _ready(fake, blocks);
    expect(await c.sendDirectText(_blocked, 'first'), isNull);

    await blocks.unblock(_blocked);
    final ChatMessage? m = await c.sendDirectText(_blocked, 'second');
    expect(m, isNotNull, reason: 'the block was the only thing refusing it');
    c.dispose();
  });

  test('an urgent send outranks a block, the way an SOS outranks a mute',
      () async {
    // The alarm path is `urgent: true`. A block is a reading preference, and a
    // distress call is not a message the reader chose to stop hearing.
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final BlockStore blocks = BlockStore(seed: <String, BlockedKey>{
      _blocked: BlockedKey(pubKeyHex: _blocked, sinceMs: 1),
    });
    final MeshcoreController c = await _ready(fake, blocks);
    final int before = fake.sent.length;

    final ChatMessage? m =
        await c.sendDirectText(_blocked, 'SOS', urgent: true);
    expect(m, isNotNull);
    expect(fake.sent.length, greaterThan(before));
    c.dispose();
  });

  test('a retry of a row addressed to a blocked key is refused', () async {
    // The row can predate the block: it was sent, it timed out, and the reader
    // blocked the peer before tapping Retry.
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final BlockStore blocks = BlockStore();
    final MeshcoreController c = await _ready(fake, blocks);
    fake.setConnected(false);
    final ChatMessage? m = await c.sendDirectText(_open, 'hello');
    expect(m, isNotNull);
    expect(m!.delivery, MessageDelivery.unknown);
    fake.setConnected(true);

    await blocks.block(BlockedKey(pubKeyHex: _open, sinceMs: 2));
    expect(await c.retryMessageOutcome(m.id), RetryOutcome.refused);
    c.dispose();
  });

  test('a controller with no block list attached sends as before', () async {
    // The seam is optional so a test that does not care about blocks does not
    // have to build a store.
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController c = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await c.connect();
    fake.emit(selfInfoFrame());
    await Future<void>.delayed(Duration.zero);
    expect(c.isPeerBlocked(_blocked), isFalse);
    expect(await c.sendDirectText(_blocked, 'hello'), isNotNull);
    c.dispose();
  });
}
