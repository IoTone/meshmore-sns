// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';

import 'package:meshmore_sns_app/media/media_chunk.dart';
import 'package:meshmore_sns_app/media/media_codec.dart';
import 'package:meshmore_sns_app/media/media_inbox.dart';
import 'package:meshmore_sns_app/media/media_photo.dart';
import 'package:meshmore_sns_app/media/media_transfer.dart';
import 'package:meshmore_sns_app/meshcore/channel_datagram.dart';

final DateTime _t0 = DateTime.utc(2026, 11, 5, 12);

ChannelDatagram _datagram(
  Uint8List blob, {
  int dataType = kChannelDataTypeDev,
  int channelIndex = 1,
}) =>
    ChannelDatagram(
      channelIndex: channelIndex,
      dataType: dataType,
      blob: blob,
      rxVia: RxVia.unknown,
      snrDb: 6,
      pathLen: kPathLenFlood,
      receivedAt: _t0,
    );

/// One picture's worth of datagrams: [count] chunks plus the payload they
/// carry, so a test can assert the bytes that came out are the bytes that went
/// in.
({List<Uint8List> chunks, Uint8List payload}) _transfer(int payloadId,
    {int bytes = 320}) {
  final Uint8List payload =
      Uint8List.fromList(List<int>.generate(bytes, (int i) => i & 0xFF));
  return (
    chunks: MediaChunkCodec.split(payload,
        payloadId: payloadId, kind: MediaKind.image),
    payload: payload,
  );
}

void main() {
  late StreamController<ChannelDatagram> datagrams;

  setUp(() => datagrams = StreamController<ChannelDatagram>.broadcast());
  tearDown(() => datagrams.close());

  MediaInbox inbox() => MediaInbox(
        datagrams: datagrams.stream,
        codec: FakeMediaCodec(),
        clock: () => _t0,
      );

  test('a payload arrives whole and the claim gets its bytes', () async {
    final MediaInbox box = inbox()..start();
    final ({List<Uint8List> chunks, Uint8List payload}) t = _transfer(11);
    MediaInboxPayload? claimed;
    box.claim(11, (MediaInboxPayload p) => claimed = p);

    for (final Uint8List chunk in t.chunks) {
      datagrams.add(_datagram(chunk));
    }
    await pumpEventQueue();

    expect(claimed, isNotNull);
    expect(claimed!.payloadId, 11);
    expect(claimed!.kind, MediaKind.image);
    expect(claimed!.bytes, t.payload);
    expect(claimed!.channelIndex, 1);
    expect(box.completedPayloads, 1);
    expect(box.lastOutcome, MediaInboxOutcome.completed);
    await box.dispose();
  });

  test('a payload nobody claimed still completes, and says so', () async {
    final MediaInbox box = inbox()..start();
    final List<MediaInboxPayload> seen = <MediaInboxPayload>[];
    final StreamSubscription<MediaInboxPayload> sub =
        box.completed.listen(seen.add);
    final ({List<Uint8List> chunks, Uint8List payload}) t = _transfer(12);

    for (final Uint8List chunk in t.chunks) {
      datagrams.add(_datagram(chunk));
    }
    await pumpEventQueue();

    expect(seen, hasLength(1),
        reason: 'a picture for a place nobody has open is not an error');
    expect(seen.single.bytes, t.payload);
    expect(box.progressFor(12), isNull,
        reason: 'the bytes are handed on, so the transfer is released');
    await sub.cancel();
    await box.dispose();
  });

  test('another layer\'s datagram is counted as foreign, not refused', () async {
    final MediaInbox box = inbox()..start();
    final ({List<Uint8List> chunks, Uint8List payload}) t = _transfer(13);

    datagrams.add(_datagram(t.chunks.first, dataType: 0x0101));
    await pumpEventQueue();

    expect(box.foreignDatagrams, 1);
    expect(box.refusedDatagrams, 0);
    expect(box.lastOutcome, MediaInboxOutcome.foreignType);
    expect(box.download.transfers, isEmpty);
    await box.dispose();
  });

  test('a media datagram that is not a chunk is refused by name', () async {
    final MediaInbox box = inbox()..start();
    final ({List<Uint8List> chunks, Uint8List payload}) t = _transfer(14);
    final Uint8List corrupt = Uint8List.fromList(t.chunks.first);
    corrupt[corrupt.length - 1] ^= 0xFF;

    datagrams.add(_datagram(corrupt));
    await pumpEventQueue();

    expect(box.refusedDatagrams, 1);
    expect(box.lastOutcome, MediaInboxOutcome.refused);
    expect(box.download.lastChunkRefusal, MediaChunkRefusal.crcMismatch);
    await box.dispose();
  });

  test('a request for missing chunks is reported, not reassembled', () async {
    final MediaInbox box = inbox()..start();
    final Uint8List request = MediaRequestCodec.encode(
      payloadId: 15,
      kind: MediaKind.image,
      count: 4,
      missing: <int>[1, 3],
    );

    datagrams.add(_datagram(request));
    await pumpEventQueue();

    expect(box.lastOutcome, MediaInboxOutcome.request);
    expect(box.download.transfers, isEmpty,
        reason: 'a bitmap is not picture bytes');
    await box.dispose();
  });

  test('the progress and the ask come from the shared download', () async {
    final MediaInbox box = inbox()..start();
    final ({List<Uint8List> chunks, Uint8List payload}) t = _transfer(16);

    datagrams.add(_datagram(t.chunks[0]));
    await pumpEventQueue();

    final MediaDownloadProgress progress = box.progressFor(16)!;
    expect(progress.received, 1);
    expect(progress.missing, <int>[1, 2]);
    final Uint8List ask = box.requestBytesFor(16)!;
    final MediaChunk parsed = MediaChunkCodec.parse(ask).chunk!;
    expect(MediaRequestCodec.missingOf(parsed), <int>[1, 2]);
    await box.dispose();
  });

  test('starting twice does not subscribe twice', () async {
    final MediaInbox box = inbox()
      ..start()
      ..start();
    final ({List<Uint8List> chunks, Uint8List payload}) t = _transfer(17);

    datagrams.add(_datagram(t.chunks[0]));
    await pumpEventQueue();

    expect(box.lastOutcome, MediaInboxOutcome.chunk,
        reason: 'a second subscription would report a duplicate instead');
    expect(box.progressFor(17)!.received, 1);
    await box.dispose();
    expect(box.listening, isFalse);
  });

  test('a completed payload decodes through the inbox\'s codec', () async {
    final FakeMediaCodec codec = FakeMediaCodec();
    final MediaInbox box = MediaInbox(
      datagrams: datagrams.stream,
      codec: codec,
      clock: () => _t0,
    )..start();
    final ({List<Uint8List> chunks, Uint8List payload}) t = _transfer(18);
    MediaInboxPayload? claimed;
    box.claim(18, (MediaInboxPayload p) => claimed = p);

    for (final Uint8List chunk in t.chunks) {
      datagrams.add(_datagram(chunk));
    }
    await pumpEventQueue();

    final MediaPhoto photo = await box.codec.decode(claimed!.bytes);
    expect(photo.isWellFormed, isTrue);
    expect(codec.decodeCalls, 1);
    await box.dispose();
  });
}
