// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_transport.dart';

/// The companion-protocol rules whose subject is a conversation rather than a
/// byte string.
///
/// The codec's own conformance suite (`packages/meshcore/test/conformance_test.dart`)
/// pins the wire: the byte ceilings, the packed path byte, the error vocabulary
/// and the frames that have more than one length. These cases pin the three
/// client rules, each from the published contract:
///
///  * every channel slot the radio reports is read, past empty ones, one
///    request at a time;
///  * a contact stream that stalls is re-requested, bounded, and a partial
///    table is kept and marked rather than waited on forever;
///  * a send the radio says will carry no acknowledgement does not later fail.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// `RESP_CODE_CONTACTS_START` (0x02): `[02][count u32]`.
  Uint8List contactsStart(int count) => Uint8List.fromList(<int>[
        0x02,
        count & 0xFF,
        (count >> 8) & 0xFF,
        (count >> 16) & 0xFF,
        (count >> 24) & 0xFF,
      ]);

  /// `RESP_CODE_END_OF_CONTACTS` (0x04): `[04][lastmod u32]`.
  Uint8List endOfContacts() => Uint8List.fromList(<int>[0x04, 0, 0, 0, 0]);

  /// `RESP_CODE_SENT` (0x06): `[06][flood][ack u32][timeout u32]`.
  Uint8List msgSentFrame({
    required int ack,
    bool flood = false,
    int timeoutMs = 1000,
  }) {
    final Uint8List f = Uint8List(10);
    f[0] = 0x06;
    f[1] = flood ? 1 : 0;
    final ByteData bd = ByteData.view(f.buffer);
    bd.setUint32(2, ack, Endian.little);
    bd.setUint32(6, timeoutMs, Endian.little);
    return f;
  }

  Future<void> settle([int turns = 6]) async {
    for (int i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  int asksFor(FakeMeshcoreTransport fake, int opcode) =>
      fake.sent.where((Uint8List b) => b.isNotEmpty && b[0] == opcode).length;

  Future<MeshcoreController> connected(
    FakeMeshcoreTransport fake, {
    Duration? contactIdle,
    Duration? channelProbeIdle,
    Duration? deliveryTimeout,
  }) async {
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      contactIdleOverride: contactIdle,
      channelProbeIdleOverride: channelProbeIdle,
      deliveryTimeoutOverride: deliveryTimeout,
    );
    await mc.connect();
    fake.emit(selfInfoFrame());
    await settle();
    return mc;
  }

  group('channel slots: every one the radio reports is read', () {
    test('the walk follows DEVICE_INFO and advances one answer at a time',
        () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      // The idle window is far longer than this test's real time, so nothing
      // advances except an answer: what is proved here is the reply walk.
      final MeshcoreController mc = await connected(
        fake,
        channelProbeIdle: const Duration(seconds: 30),
      );

      // The walk opens with slot 0 and nothing else, because the firmware keeps
      // one reply buffer and a burst would overtake itself.
      expect(asksFor(fake, 0x1F), 1);

      // The radio says it holds six slots; that arrives while slot 0 is still
      // unanswered, so it must not put a second request in flight.
      fake.emit(deviceInfoFrame(maxChannels: 6));
      await settle();
      expect(asksFor(fake, 0x1F), 1,
          reason: 'one slot may be in flight at a time');

      // Each answer releases exactly one more request.
      fake.emit(channelInfoFrame(idx: 0, name: 'Public'));
      await settle();
      expect(asksFor(fake, 0x1F), 2);
      fake.emit(channelInfoFrame(idx: 1, name: 'ops'));
      await settle();
      expect(asksFor(fake, 0x1F), 3);

      mc.dispose();
    });

    test('a slot that never answers does not end the walk', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(
        fake,
        channelProbeIdle: const Duration(milliseconds: 40),
      );
      fake.emit(deviceInfoFrame(maxChannels: 6));
      // Only slot 0 is answered; the rest stay silent, which is what an
      // unconfigured or refused slot looks like.
      fake.emit(channelInfoFrame(idx: 0, name: 'Public'));
      await settle();

      await Future<void>.delayed(const Duration(milliseconds: 200));
      final int asks = asksFor(fake, 0x1F);
      expect(asks, greaterThanOrEqualTo(4),
          reason: 'an unanswered slot is not the end of the table');
      expect(asks, lessThanOrEqualTo(6),
          reason: 'the walk stops at the count DEVICE_INFO reported');
      mc.dispose();
    });

    test('the walk stops at the reported count', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(
        fake,
        channelProbeIdle: const Duration(milliseconds: 60),
      );
      fake.emit(deviceInfoFrame(maxChannels: 2));
      fake.emit(channelInfoFrame(idx: 0, name: 'Public'));
      await settle();
      fake.emit(channelInfoFrame(idx: 1, name: 'ops'));
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(asksFor(fake, 0x1F), 2,
          reason: 'two slots reported, two slots asked for, and no more');
      mc.dispose();
    });
  });

  group('contact enumeration: a stalled stream is retried, bounded', () {
    test(
        'silence mid-stream re-requests, keeps what arrived, and marks the '
        'table incomplete', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(
        fake,
        contactIdle: const Duration(milliseconds: 60),
      );

      fake.emit(contactsStart(9));
      await settle();
      fake.emit(contactFrame(name: 'One', firstPubByte: 0x11));
      await settle();
      expect(mc.probedContacts.length, 1);

      // The radio goes quiet without END_OF_CONTACTS. The watchdog re-requests
      // the table and gives up after its attempt ceiling.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(asksFor(fake, 0x04), greaterThanOrEqualTo(armedRetries),
          reason: 'a stalled stream is asked again, not waited on');
      expect(mc.probedContacts.length, 1,
          reason: 'the entries that did arrive are kept');
      expect(mc.contactsIncomplete, isTrue,
          reason: 'a partial table must say so rather than read as complete');

      // An end-of-contacts frame clears the flag.
      fake.emit(endOfContacts());
      await settle();
      expect(mc.contactsIncomplete, isFalse);
      mc.dispose();
    });

    test('a lost end-of-contacts frame does not wedge the next sync', () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(
        fake,
        contactIdle: const Duration(milliseconds: 40),
      );
      fake.emit(contactsStart(2));
      await settle();
      // No contact frames and no END: the stream stalls entirely.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(mc.contactsIncomplete, isTrue);

      final int before = asksFor(fake, 0x04);
      await mc.refreshDeviceContacts();
      expect(asksFor(fake, 0x04), greaterThan(before),
          reason: 'the next sync must send a request rather than believing '
              'one is already in flight');
      mc.dispose();
    });
  });

  group('send confirmation: what the radio says about acks is taken', () {
    test('expected_ack 0 leaves the row sent, and no watchdog fails it',
        () async {
      final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = await connected(
        fake,
        deliveryTimeout: const Duration(milliseconds: 80),
      );

      const String peer =
          'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899';
      await mc.sendDirectText(peer, 'no ack expected');
      fake.emit(msgSentFrame(ack: 0, flood: false));
      await settle();
      expect(mc.dmHistoryFor(peer).single.delivery, MessageDelivery.sent);

      // Well past the confirmation watchdog and the ack window: the radio said
      // no acknowledgement would come, so there is nothing to wait for.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(mc.dmHistoryFor(peer).single.delivery, MessageDelivery.sent,
          reason: 'a send the radio accepted must not become unknown or '
              'failed only because no ACK was ever going to arrive');
      mc.dispose();
    });
  });
}

/// The first request plus its bounded retries: `contactSyncAttempts` is 3, so a
/// stalled stream is asked for at most four times in total.
const int armedRetries = 2;
