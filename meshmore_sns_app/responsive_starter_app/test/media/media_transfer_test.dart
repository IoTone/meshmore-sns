// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';

import 'package:meshmore_sns_app/meshcore/airtime.dart';
import 'package:meshmore_sns_app/meshcore/channel_datagram.dart';
import 'package:meshmore_sns_app/media/media_chunk.dart';
import 'package:meshmore_sns_app/media/media_codec.dart';
import 'package:meshmore_sns_app/media/media_photo.dart';
import 'package:meshmore_sns_app/media/media_reassembly.dart';
import 'package:meshmore_sns_app/media/media_send_policy.dart';
import 'package:meshmore_sns_app/media/media_sender.dart';
import 'package:meshmore_sns_app/media/media_transfer.dart';
import 'package:meshmore_sns_app/voice/voice_codec.dart';

MediaPhoto photo(int width, int height) => MediaPhoto(
      width: width,
      height: height,
      rgba: Uint8List(width * height * 4),
    );

/// The failure a radio call throws when the link is gone rather than busy.
final class _LinkGone implements Exception {
  const _LinkGone();
}

/// A clock a test moves by hand, so a transfer that would take a minute of
/// wall time costs nothing here.
final class TestClock {
  DateTime now = DateTime.utc(2026, 11, 5, 12);

  DateTime call() => now;

  Future<void> wait(Duration d) async {
    now = now.add(d);
  }
}

void main() {
  group('a transfer is costed before it goes on air', () {
    test('the Public gate refuses before the encoder runs', () async {
      final FakeMediaCodec codec = FakeMediaCodec();
      final TestClock clock = TestClock();
      final MediaTransferService service = MediaTransferService(
        codec: codec,
        estimator: const AirtimeEstimator(millisPerByte: 4),
        clock: clock.call,
      );
      final MediaPreparation outcome = await service.prepare(
        photo(320, 240),
        channelPsk: kPublicChannelPsk,
        byteBudget: 4000,
      );
      expect(outcome, isA<MediaRefused>());
      expect((outcome as MediaRefused).refusal,
          MediaSendRefusal.mediaOffOnPublic);
      expect(codec.encodeCalls, 0,
          reason: 'refusing after a second of native encoding is a bad answer');
    });

    test('the chunk count and the airtime are stated, not discovered', () async {
      final TestClock clock = TestClock();
      final MediaTransferService service = MediaTransferService(
        codec: FakeMediaCodec(encodedBytes: 900),
        estimator: const AirtimeEstimator(millisPerByte: 4),
        clock: clock.call,
        newPayloadId: () => 42,
      );
      final MediaPreparation outcome = await service.prepare(
        photo(320, 240),
        channelPsk: List<int>.filled(16, 0x11),
        byteBudget: 2000,
      );
      final MediaTransferPlan plan = (outcome as MediaPrepared).plan;
      // 900 bytes at 150 per chunk is six chunks, six datagrams on air. Each
      // datagram is a full frame: 12 header bytes and 150 payload bytes, plus
      // the four bytes of datagram header the radio adds before the blob, so
      // 166 bytes of airtime at the flat 4 ms/byte estimate is 664 ms — the
      // number the cost line has to show before anyone taps Send.
      expect(plan.payloadId, 42);
      expect(plan.chunks.length, 6);
      expect(plan.cost.chunks, 6);
      expect(plan.cost.bytes, 900);
      expect(plan.cost.airtime, const Duration(milliseconds: 3984));
    });

    test('a short last chunk is charged for what it actually carries', () async {
      final TestClock clock = TestClock();
      final MediaTransferService service = MediaTransferService(
        codec: FakeMediaCodec(encodedBytes: 460),
        estimator: const AirtimeEstimator(millisPerByte: 4),
        clock: clock.call,
        newPayloadId: () => 7,
      );
      final MediaPreparation outcome = await service.prepare(
        photo(320, 240),
        channelPsk: List<int>.filled(16, 0x11),
        byteBudget: 2000,
      );
      final MediaTransferPlan plan = (outcome as MediaPrepared).plan;
      // Three full datagrams of 150 and one of 10: charging every chunk as if
      // it were full would overstate the last one by 140 bytes of airtime.
      expect(plan.chunks.length, 4);
      expect(
          plan.cost.airtime, const Duration(milliseconds: 4 * (3 * 166 + 26)));
      expect(plan.withinBudget, isTrue);
    });

    test('a picture the encoder cannot squeeze in says so', () async {
      final MediaTransferService service = MediaTransferService(
        codec: FakeMediaCodec(encodedBytes: 5000),
        estimator: const AirtimeEstimator(millisPerByte: 4),
        clock: TestClock().call,
      );
      final MediaPreparation outcome = await service.prepare(
        photo(320, 240),
        channelPsk: List<int>.filled(16, 0x22),
        byteBudget: 1000,
      );
      expect((outcome as MediaPrepared).plan.withinBudget, isFalse);
    });
  });

  group('the upload obeys the pacing and the retry rules', () {
    test('every chunk goes out once, and the receipt counts them', () async {
      final TestClock clock = TestClock();
      final MediaTransferService service = MediaTransferService(
        codec: FakeMediaCodec(encodedBytes: 450),
        estimator: const AirtimeEstimator(millisPerByte: 4),
        clock: clock.call,
      );
      final MediaTransferPlan plan = ((await service.prepare(
        photo(320, 240),
        channelPsk: List<int>.filled(16, 0x33),
        byteBudget: 2000,
      )) as MediaPrepared)
          .plan;
      final MediaUpload upload = MediaUpload(
        plan: plan,
        clock: clock.call,
        wait: clock.wait,
      );
      final List<Uint8List> sent = <Uint8List>[];
      final MediaReceipt receipt = await upload.run((Uint8List blob) async {
        sent.add(blob);
        return const ChannelDataSendResult(ChannelDataSendStatus.accepted);
      });
      expect(sent.length, plan.chunks.length);
      expect(receipt.chunks, plan.chunks.length);
      expect(receipt.resends, 0);
      // The pacing is real: three chunks cost at least two intervals.
      expect(receipt.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 700)));
    });

    test('a table-full answer spends no attempt and the chunk goes again',
        () async {
      final TestClock clock = TestClock();
      final MediaTransferPlan plan = MediaTransferPlan(
        payloadId: 5,
        kind: MediaKind.image,
        photo: photo(320, 240),
        payload: Uint8List(300),
        chunks: MediaChunkCodec.split(List<int>.filled(300, 9),
            payloadId: 5, kind: MediaKind.image),
        cost: const MediaTransferCost(
            chunks: 2, bytes: 300, airtime: Duration(milliseconds: 8)),
        withinBudget: true,
      );
      final MediaUpload upload = MediaUpload(
        plan: plan,
        clock: clock.call,
        wait: clock.wait,
      );
      int calls = 0;
      final MediaReceipt receipt = await upload.run((Uint8List blob) async {
        calls++;
        // The first answer is capacity, not refusal: nothing was written.
        if (calls == 1) {
          return const ChannelDataSendResult(ChannelDataSendStatus.notReady);
        }
        return const ChannelDataSendResult(ChannelDataSendStatus.accepted);
      });
      expect(receipt.chunks, 2);
      expect(receipt.resends, 0,
          reason: 'nothing was transmitted on the first answer');
      // 3 calls: one not-ready requeue plus two accepted chunks.
      expect(calls, 3);
    });

    test('no answer still counts as sent, because the frame was written',
        () async {
      final TestClock clock = TestClock();
      final MediaUpload upload = MediaUpload(
        plan: MediaTransferPlan(
          payloadId: 6,
          kind: MediaKind.image,
          photo: photo(320, 240),
          payload: Uint8List(150),
          chunks: MediaChunkCodec.split(List<int>.filled(150, 4),
              payloadId: 6, kind: MediaKind.image),
          cost: const MediaTransferCost(
              chunks: 1, bytes: 150, airtime: Duration(milliseconds: 4)),
          withinBudget: true,
        ),
        clock: clock.call,
        wait: clock.wait,
      );
      final MediaReceipt receipt = await upload.run((Uint8List blob) async =>
          const ChannelDataSendResult(ChannelDataSendStatus.noAnswer));
      expect(receipt.chunks, 1);
      expect(receipt.resends, 0);
    });

    test('a refusal is retried with a new salt and then given up on', () async {
      final TestClock clock = TestClock();
      final MediaUpload upload = MediaUpload(
        plan: MediaTransferPlan(
          payloadId: 7,
          kind: MediaKind.image,
          photo: photo(320, 240),
          payload: Uint8List(150),
          chunks: MediaChunkCodec.split(List<int>.filled(150, 5),
              payloadId: 7, kind: MediaKind.image),
          cost: const MediaTransferCost(
              chunks: 1, bytes: 150, airtime: Duration(milliseconds: 4)),
          withinBudget: true,
        ),
        clock: clock.call,
        wait: clock.wait,
      );
      final List<Uint8List> sent = <Uint8List>[];
      await expectLater(
        upload.run((Uint8List blob) async {
          sent.add(blob);
          return const ChannelDataSendResult(
              ChannelDataSendStatus.refusedByRadio,
              errorCode: 3);
        }),
        throwsA(isA<MediaUploadFailed>()),
      );
      expect(sent.length, MediaChunkCodec.maxAttempt + 1);
      // Every retry differs in its first byte; the payload is unchanged.
      final Set<int> headers = <int>{for (final Uint8List b in sent) b[0]};
      expect(headers.length, sent.length,
          reason: 'the radio drops a packet it has already seen');
    });

    test('a thrown send puts the chunk back instead of losing it', () async {
      final TestClock clock = TestClock();
      final MediaUpload upload = MediaUpload(
        plan: MediaTransferPlan(
          payloadId: 9,
          kind: MediaKind.image,
          photo: photo(320, 240),
          payload: Uint8List(150),
          chunks: MediaChunkCodec.split(List<int>.filled(150, 7),
              payloadId: 9, kind: MediaKind.image),
          cost: const MediaTransferCost(
              chunks: 1, bytes: 150, airtime: Duration(milliseconds: 4)),
          withinBudget: true,
        ),
        clock: clock.call,
        wait: clock.wait,
      );
      int calls = 0;
      final MediaReceipt receipt = await upload.run((Uint8List blob) async {
        calls++;
        if (calls == 1) throw StateError('the link went away');
        return const ChannelDataSendResult(ChannelDataSendStatus.accepted);
      });
      // Two calls, one receipt, no resend: the chunk went out once.
      expect(calls, 2);
      expect(receipt.chunks, 1);
      expect(receipt.resends, 0);
      expect(upload.sent, 1);
    });

    test('a run of thrown sends reports the link failure, not a lost receipt',
        () async {
      final TestClock clock = TestClock();
      final MediaUpload upload = MediaUpload(
        plan: MediaTransferPlan(
          payloadId: 10,
          kind: MediaKind.image,
          photo: photo(320, 240),
          payload: Uint8List(150),
          chunks: MediaChunkCodec.split(List<int>.filled(150, 8),
              payloadId: 10, kind: MediaKind.image),
          cost: const MediaTransferCost(
              chunks: 1, bytes: 150, airtime: Duration(milliseconds: 4)),
          withinBudget: true,
        ),
        clock: clock.call,
        wait: clock.wait,
      );
      int calls = 0;
      await expectLater(
        upload.run((Uint8List blob) async {
          calls++;
          throw const _LinkGone();
        }),
        throwsA(isA<_LinkGone>()),
      );
      // The first throw is treated as a busy link and retried; the third one
      // in a row is the link being gone, so the transfer stops and says so
      // instead of looping or reporting a lost receipt.
      expect(calls, 3,
          reason: 'a run of throws is a dead link, not a busy one');
    });

    test('a peer request resends exactly what it asked for, once', () async {
      final TestClock clock = TestClock();
      final MediaUpload upload = MediaUpload(
        plan: MediaTransferPlan(
          payloadId: 8,
          kind: MediaKind.image,
          photo: photo(320, 240),
          payload: Uint8List(450),
          chunks: MediaChunkCodec.split(List<int>.filled(450, 2),
              payloadId: 8, kind: MediaKind.image),
          cost: const MediaTransferCost(
              chunks: 3, bytes: 450, airtime: Duration(milliseconds: 12)),
          withinBudget: true,
        ),
        clock: clock.call,
        wait: clock.wait,
      );
      expect(upload.acceptRequest(<int>[1, 99]), 1,
          reason: 'an index outside the transfer is not requeued');
      expect(upload.acceptRequest(<int>[1]), 0,
          reason: 'a repeated ask must not spend airtime twice');
    });
  });

  group('the download reports what it is missing instead of guessing',
      () {
    test('chunks rejoin, progress is exact, and a duplicate is normal', () {
      final MediaDownload download = MediaDownload();
      final List<Uint8List> chunks = MediaChunkCodec.split(
          List<int>.generate(320, (int i) => i & 0xFF),
          payloadId: 21,
          kind: MediaKind.image);
      final DateTime now = DateTime.utc(2026, 11, 5, 12);

      expect(download.accept(chunks[0], now: now), MediaIntake.chunk);
      MediaDownloadProgress progress = download.progressFor(21)!;
      expect(progress.received, 1);
      expect(progress.count, chunks.length);
      expect(progress.missing, <int>[1, 2]);

      expect(download.accept(chunks[0], now: now), MediaIntake.duplicate);
      expect(download.lastReassemblyRefusal, MediaReassemblyRefusal.duplicate);

      final Uint8List request = download.requestBytesFor(21)!;
      final MediaChunkParse parsed = MediaChunkCodec.parse(request);
      expect(parsed.chunk!.kind, MediaKind.request);
      expect(MediaRequestCodec.missingOf(parsed.chunk!), <int>[1, 2]);
      expect(MediaRequestCodec.kindOf(parsed.chunk!), MediaKind.image);

      expect(download.accept(chunks[1], now: now), MediaIntake.chunk);
      expect(download.accept(chunks[2], now: now), MediaIntake.complete);
      expect(download.progressFor(21)!.complete, isTrue);
      expect(download.requestBytesFor(21), isNull,
          reason: 'a complete transfer has nothing to ask for');
      expect(download.payloadFor(21), hasLength(320));
    });

    test('a frame naming too many chunks is refused, not called a duplicate',
        () {
      final MediaDownload download = MediaDownload();
      // A chunk whose header is well formed — the CRC is right, so the parse
      // succeeds — but whose count field names far more chunks than the pool
      // will hold.
      final Uint8List data = Uint8List(8);
      final Uint8List forged = Uint8List(MediaChunkCodec.headerBytes + 8);
      final ByteData view = ByteData.sublistView(forged);
      forged[0] = MediaChunkCodec.version << 4;
      forged[1] = MediaKind.image.code;
      view.setUint32(2, 44);
      view.setUint16(6, 0);
      view.setUint16(8, 0xFFFF);
      view.setUint16(10, MediaChunkCodec.crc16(data));
      forged.setRange(MediaChunkCodec.headerBytes, forged.length, data);
      expect(download.accept(forged), MediaIntake.refused);
      expect(download.lastReassemblyRefusal,
          MediaReassemblyRefusal.countTooLarge);
      expect(download.transfers, isEmpty);
    });

    test('a request is routed away from the reassembler', () {
      final MediaDownload download = MediaDownload();
      final Uint8List request = MediaRequestCodec.encode(
        payloadId: 22,
        kind: MediaKind.voice,
        count: 4,
        missing: <int>[0, 3],
      );
      expect(download.accept(request), MediaIntake.request);
      expect(download.transfers, isEmpty,
          reason: 'a bitmap is not image bytes and must not become a transfer');
      expect(download.lastRequest, isNotNull);
    });

    test('a corrupt chunk is refused by name, not folded into progress', () {
      final MediaDownload download = MediaDownload();
      final Uint8List chunk = MediaChunkCodec.split(List<int>.filled(40, 1),
              payloadId: 23, kind: MediaKind.image)
          .single;
      chunk[chunk.length - 1] ^= 0xFF;
      expect(download.accept(chunk), MediaIntake.refused);
      expect(download.lastChunkRefusal, MediaChunkRefusal.crcMismatch);
      expect(download.transfers, isEmpty);
    });

    test('a complete payload decodes through the codec', () async {
      final FakeMediaCodec codec = FakeMediaCodec(encodedBytes: 10);
      final MediaDownload download = MediaDownload();
      final List<Uint8List> chunks = MediaChunkCodec.split(
          List<int>.filled(20, 7),
          payloadId: 24,
          kind: MediaKind.image);
      for (final Uint8List c in chunks) {
        download.accept(c);
      }
      final MediaPhoto decoded =
          await download.decode(codec, download.payloadFor(24)!);
      expect(codec.decodeCalls, 1);
      expect(decoded.width, MediaPhoto.floorWidth);
    });
  });

  group('the request datagram is one packet no matter how many holes', () {
    test('a bitmap covers 1200 chunks inside one 162-byte blob', () {
      final Uint8List request = MediaRequestCodec.encode(
        payloadId: 31,
        kind: MediaKind.image,
        count: 1200,
        missing: <int>[0, 1199],
      );
      expect(request.length, lessThanOrEqualTo(ChannelDataLimits.maxBlob));
      final MediaChunk chunk = MediaChunkCodec.parse(request).chunk!;
      expect(MediaRequestCodec.missingOf(chunk), <int>[0, 1199]);
    });

    test('an empty ask and a request-of-request are refused', () {
      expect(
        () => MediaRequestCodec.encode(
            payloadId: 32, kind: MediaKind.image, count: 4, missing: <int>[]),
        throwsArgumentError,
      );
      expect(
        () => MediaRequestCodec.encode(
            payloadId: 32,
            kind: MediaKind.request,
            count: 4,
            missing: <int>[1]),
        throwsArgumentError,
      );
    });
  });

  group('a recorded note is costed and gated like any other payload', () {
    PackedVoice note(VoiceMode mode, int frames) => PackedVoice(
          mode: mode,
          bytes: Uint8List((frames * mode.bitsPerFrame + 7) ~/ 8),
          frames: frames,
          samples: frames * mode.samplesPerFrame,
        );

    test('a 20-second 700C note is twelve datagrams of voice, not image',
        () async {
      final TestClock clock = TestClock();
      int ids = 0;
      final MediaTransferService service = MediaTransferService(
        codec: FakeMediaCodec(),
        estimator: const AirtimeEstimator(millisPerByte: 4),
        clock: clock.call,
        newPayloadId: () => 100 + ids++,
      );
      final MediaPreparation outcome = await service.prepareVoice(
        voice: note(VoiceMode.narrowband, 500),
        channelPsk: const <int>[1, 2, 3],
      );
      expect(outcome, isA<MediaPrepared>());
      final MediaTransferPlan plan = (outcome as MediaPrepared).plan;
      expect(plan.kind, MediaKind.voice);
      expect(plan.photo, isNull, reason: 'a note is not a picture');
      expect(plan.payload.length, 1751);
      expect(plan.cost.chunks, 12);
      expect(plan.cost.bytes, 1751);
      expect(plan.withinBudget, isTrue);
      expect(plan.cost.airtime, greaterThan(Duration.zero));
      // The one-chunk-per-datagram rule holds for voice too.
      for (final Uint8List chunk in plan.chunks) {
        expect(chunk.length, lessThanOrEqualTo(162));
      }
    });

    test('the Public gate refuses before any payload exists', () async {
      final TestClock clock = TestClock();
      int ids = 0;
      final MediaTransferService service = MediaTransferService(
        codec: FakeMediaCodec(),
        estimator: const AirtimeEstimator(millisPerByte: 4),
        clock: clock.call,
        newPayloadId: () => ids++,
      );
      final MediaPreparation outcome = await service.prepareVoice(
        voice: note(VoiceMode.narrowband, 500),
        channelPsk: kPublicChannelPsk,
      );
      expect((outcome as MediaRefused).refusal,
          MediaSendRefusal.mediaOffOnPublic);
      expect(ids, 0, reason: 'nothing was chunked for a refused channel');
    });

    test('an empty take is a refusal, not a codec exception', () async {
      final MediaTransferService service = MediaTransferService(
        codec: FakeMediaCodec(),
        estimator: const AirtimeEstimator(millisPerByte: 4),
        clock: TestClock().call,
      );
      final MediaPreparation outcome = await service.prepareVoice(
        voice: PackedVoice(
          mode: VoiceMode.narrowband,
          bytes: Uint8List(0),
          frames: 0,
          samples: 0,
        ),
        channelPsk: const <int>[1, 2, 3],
      );
      expect((outcome as MediaRefused).refusal,
          MediaSendRefusal.payloadUnusable);
    });

    test('a payload past the receiver\'s own chunk ceiling is refused here',
        () async {
      final MediaTransferService service = MediaTransferService(
        codec: FakeMediaCodec(),
        estimator: const AirtimeEstimator(millisPerByte: 4),
        clock: TestClock().call,
      );
      // 512 chunks is the reassembler's bound; 513 would arrive as a count it
      // refuses, so the sender refuses rather than spending the airtime.
      final MediaPreparation outcome = await service.prepareVoice(
        voice: PackedVoice(
          mode: VoiceMode.narrowband,
          bytes: Uint8List(513 * MediaChunkCodec.maxDataBytes),
          frames: 513 * 40,
          samples: 513 * 40 * 320,
        ),
        channelPsk: const <int>[1, 2, 3],
      );
      expect((outcome as MediaRefused).refusal,
          MediaSendRefusal.payloadUnusable);
    });
  });

  group('capacity that never comes back is a stop, not a spinner', () {
    MediaUpload upload(TestClock clock) => MediaUpload(
          plan: MediaTransferPlan(
            payloadId: 55,
            kind: MediaKind.voice,
            photo: null,
            payload: Uint8List(300),
            chunks: MediaChunkCodec.split(List<int>.filled(300, 3),
                payloadId: 55, kind: MediaKind.voice),
            cost: const MediaTransferCost(
                chunks: 2, bytes: 300, airtime: Duration(milliseconds: 8)),
            withinBudget: true,
          ),
          clock: clock.call,
          wait: clock.wait,
        );

    test('a run of TABLE_FULL answers stops and names the capacity', () async {
      final TestClock clock = TestClock();
      int calls = 0;
      await expectLater(
        upload(clock).run((Uint8List blob) async {
          calls++;
          return const ChannelDataSendResult(ChannelDataSendStatus.notReady);
        }),
        throwsA(isA<MediaUploadStalled>().having(
            (MediaUploadStalled e) => e.reason,
            'reason',
            MediaSendResult.tableFull)),
      );
      expect(calls, MediaUpload.maxCapacityAnswers);
    });

    test('an airtime refusal is the same stop with its own reason', () async {
      final TestClock clock = TestClock();
      await expectLater(
        upload(clock).run((Uint8List blob) async =>
            const ChannelDataSendResult(ChannelDataSendStatus.refusedAirtime)),
        throwsA(isA<MediaUploadStalled>().having(
            (MediaUploadStalled e) => e.reason,
            'reason',
            MediaSendResult.budgetRefused)),
      );
    });

    test('a cancel stops the loop before the next datagram', () async {
      final TestClock clock = TestClock();
      final MediaUpload u = upload(clock);
      u.cancel();
      int calls = 0;
      await expectLater(
        u.run((Uint8List blob) async {
          calls++;
          return const ChannelDataSendResult(ChannelDataSendStatus.accepted);
        }),
        throwsA(isA<MediaUploadCancelled>()),
      );
      expect(calls, 0, reason: 'a closed sheet puts nothing on air');
    });
  });

  // The owner's report: one photo reported sixteen messages, and the airtime was
  // the complaint. Every chunk is its own frame on air, so the send size is the
  // airtime, and the small sizes have to reach the encoder rather than only the
  // projection.
  test('the send size decides the budget and the pixel ceiling', () async {
    for (final MediaSendSize size in MediaSendSize.values) {
      final FakeMediaCodec codec = FakeMediaCodec(encodedBytes: 200);
      final MediaTransferService svc = MediaTransferService(
        codec: codec,
        estimator: const AirtimeEstimator(millisPerByte: 4),
        clock: () => DateTime.utc(2026, 1, 1),
        mediaOnPublic: true,
      );
      final MediaPreparation p =
          await svc.prepare(photo(320, 240),
              channelPsk: List<int>.filled(16, 7), size: size);
      expect(p, isA<MediaPrepared>());
      expect(codec.budgets.single, size.budgetBytes, reason: size.name);
      expect(codec.ceilings.single, (size.maxWidth, size.maxHeight),
          reason: size.name);
    }
  });

  test('the default photo is a snapshot, not the old full budget', () {
    // 1600 bytes is ten 162-byte blobs at the very worst and about six for a
    // real photo, against 4096's 28 and 18.
    expect(MediaSendSize.standard.budgetBytes, lessThan(2048));
    expect(MediaSendSize.standard.maxWidth, lessThan(MediaPhoto.floorWidth));
    expect(MediaSendSize.preview.budgetBytes, lessThan(
        MediaSendSize.standard.budgetBytes));
  });
}
