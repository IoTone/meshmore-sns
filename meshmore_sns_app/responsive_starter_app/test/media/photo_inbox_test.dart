// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/media/media_chunk.dart';
import 'package:meshmore_sns_app/media/media_inbox.dart';
import 'package:meshmore_sns_app/media/photo_inbox.dart';

/// The half of media that was missing.
///
/// A photo sent on a channel was reassembled by `MediaInbox` and then dropped:
/// the inbox hands a completed payload to whoever claimed it, and nothing
/// claimed an image. The sender's receipt said "accepted" and the receiver saw
/// nothing at all. These pin the claim.
void main() {
  late StreamController<MediaInboxPayload> completed;
  late PhotoInbox inbox;

  setUp(() {
    completed = StreamController<MediaInboxPayload>.broadcast();
    inbox = PhotoInbox(completed: completed.stream)..start();
  });

  tearDown(() async {
    inbox.dispose();
    await completed.close();
  });

  MediaInboxPayload payload({
    required int id,
    MediaKind kind = MediaKind.image,
    int channel = 1,
    int bytes = 4,
    DateTime? at,
  }) =>
      MediaInboxPayload(
        payloadId: id,
        kind: kind,
        channelIndex: channel,
        receivedAt: at ?? DateTime(2026, 11, 13, 10, 0),
        bytes: Uint8List.fromList(List<int>.filled(bytes, 0x41)),
      );

  Future<void> deliver(MediaInboxPayload p) async {
    completed.add(p);
    // The subscription is a stream listener, so the event lands on a microtask.
    await Future<void>.delayed(Duration.zero);
  }

  test('a completed picture is kept, newest first', () async {
    await deliver(payload(id: 1));
    await deliver(payload(id: 2));
    expect(inbox.photos.map((ReceivedPhoto p) => p.payloadId), <int>[2, 1]);
    expect(inbox.photos.first.byteCount, 4);
  });

  test('a voice note is somebody else\'s row', () async {
    // One inbox serves every media kind; filing a note as a picture would put
    // an undecodable payload in the photo sheet.
    await deliver(payload(id: 1, kind: MediaKind.voice));
    expect(inbox.photos, isEmpty);
  });

  test('pictures are counted and listed per channel', () async {
    await deliver(payload(id: 1, channel: 1));
    await deliver(payload(id: 2, channel: 2));
    await deliver(payload(id: 3, channel: 1));
    expect(inbox.countFor(1), 2);
    expect(inbox.countFor(2), 1);
    expect(inbox.countFor(3), 0);
    expect(inbox.photosFor(1).map((ReceivedPhoto p) => p.payloadId),
        <int>[3, 1]);
  });

  test('the list is bounded and drops the oldest', () async {
    final PhotoInbox small = PhotoInbox(completed: completed.stream, capacity: 2)
      ..start();
    addTearDown(small.dispose);
    await deliver(payload(id: 1));
    await deliver(payload(id: 2));
    await deliver(payload(id: 3));
    expect(small.photos.map((ReceivedPhoto p) => p.payloadId), <int>[3, 2]);
  });

  test('the same payload is not filed twice', () async {
    // A replayed chunk can complete a payload the inbox has already handed on;
    // two rows for one picture would be a duplicate the reader cannot explain.
    await deliver(payload(id: 7));
    await deliver(payload(id: 7));
    expect(inbox.photos, hasLength(1));
  });

  test('an empty payload is not a picture', () async {
    await deliver(payload(id: 1, bytes: 0));
    expect(inbox.photos, isEmpty);
  });

  test('clear empties what is on screen', () async {
    await deliver(payload(id: 1));
    inbox.clear();
    expect(inbox.photos, isEmpty);
    expect(inbox.countFor(1), 0);
  });

  test('a listener is told when a picture arrives', () async {
    int notified = 0;
    inbox.addListener(() => notified++);
    await deliver(payload(id: 1));
    expect(notified, 1);
  });

  test('a payload that arrives after dispose is not filed', () async {
    // The tab can be disposed while a transfer is still completing; notifying a
    // dead notifier throws in debug, which is what SafeNotifier exists for.
    inbox.dispose();
    completed.add(payload(id: 1));
    await Future<void>.delayed(Duration.zero);
    expect(inbox.photos, isEmpty);
  });
}
