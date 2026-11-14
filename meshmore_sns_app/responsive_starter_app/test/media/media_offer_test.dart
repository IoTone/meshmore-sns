// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/media/media_offer.dart';
import 'package:meshmore_sns_app/media/media_send_policy.dart';

/// A picture is announced, then fetched. These are the two rules that make that
/// true, and both are cheap to break by accident.
void main() {
  group('a full picture never travels on a channel', () {
    test('the policy refuses it whatever the channel is', () {
      const MediaSendPolicy policy = MediaSendPolicy(mediaOnPublic: true);
      // Even with media explicitly allowed on Public, a full picture is not a
      // channel payload: the opt-in is about a preview, not about flooding
      // twenty datagrams.
      expect(
        policy.refusalFor(
            channelPsk: List<int>.filled(16, 7),
            payloadBytes: 4000,
            fullPicture: true),
        MediaSendRefusal.fullPictureOnChannel,
      );
    });

    test('a preview is still allowed on a private channel', () {
      const MediaSendPolicy policy = MediaSendPolicy();
      expect(
        policy.refusalFor(
            channelPsk: List<int>.filled(16, 7), payloadBytes: 163),
        isNull,
      );
    });
  });

  group('offers expire and are bounded', () {
    test('an offer is served until its ttl runs out', () {
      DateTime now = DateTime(2026, 11, 14, 12);
      final MediaOfferStore store = MediaOfferStore(clock: () => now);
      store.add(MediaOffer(
        id: 7,
        payload: Uint8List(300),
        chunkCount: 2,
        createdAt: now,
      ));
      expect(store.find(7), isNotNull);
      now = now.add(const Duration(minutes: 14));
      expect(store.find(7), isNotNull, reason: 'still inside the window');
      now = now.add(const Duration(minutes: 2));
      expect(store.find(7), isNull, reason: 'a promise nobody can keep is worse');
    });

    test('the store keeps the newest and drops the oldest', () {
      DateTime now = DateTime(2026, 11, 14, 12);
      final MediaOfferStore store = MediaOfferStore(capacity: 2, clock: () => now);
      for (int i = 0; i < 3; i++) {
        store.add(MediaOffer(
          id: i,
          payload: Uint8List(10),
          chunkCount: 1,
          createdAt: now,
        ));
      }
      expect(store.offers.map((MediaOffer o) => o.id), <int>[1, 2]);
    });
  });

  group('the request grammar', () {
    test('round trips', () {
      expect(MediaRequestCodec.encode(42), '[IMG1:42]');
      expect(MediaRequestCodec.decode('[IMG1:42]'), 42);
      expect(MediaRequestCodec.decode('  [IMG1:7] '), 7);
    });

    test('an ordinary message is not a request', () {
      expect(MediaRequestCodec.decode('hello'), isNull);
      expect(MediaRequestCodec.decode('[IMG1:]'), isNull);
      expect(MediaRequestCodec.decode('[IMG1:abc]'), isNull);
      expect(MediaRequestCodec.decode('[IMG1:999999]'), isNull);
      expect(MediaRequestCodec.looksLikeRequest('[IMG1:1]'), isTrue);
      expect(MediaRequestCodec.looksLikeRequest('IMG1:1'), isFalse);
    });
  });
}
