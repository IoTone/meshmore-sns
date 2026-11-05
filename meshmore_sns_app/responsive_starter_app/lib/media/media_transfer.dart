// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';

import '../meshcore/airtime.dart';
import '../meshcore/channel_datagram.dart';
import 'media_chunk.dart';
import 'media_journal.dart';
import 'media_codec.dart';
import 'media_photo.dart';
import 'media_reassembly.dart';
import 'media_send_policy.dart';
import 'media_sender.dart';

/// The byte budget a channel photo is encoded to.
///
/// 4 KB is what the 320x240 floor is worth: a container spends 200-350 bytes
/// before the first pixel, so a bigger number buys no visible detail and costs
/// airtime, and a smaller one turns a sign into a smear. It is a target, not a
/// guarantee — the plan reports an over-budget picture rather than refusing it
/// after the encode.
const int kMediaPhotoBudgetBytes = 4096;

/// What one transfer costs, stated before anything goes on air.
///
/// Airtime is the number people do not have: a 3 KB photo is twenty datagrams,
/// which on the USA/Canada preset is most of a minute of transmitter time and
/// all of a 36-second hourly budget. Showing the chunk count and the projected
/// airtime before the send is the difference between a considered send and a
/// surprise.
final class MediaTransferCost {
  const MediaTransferCost({
    required this.chunks,
    required this.bytes,
    required this.airtime,
  });

  final int chunks;
  final int bytes;
  final Duration airtime;

  @override
  String toString() => 'MediaTransferCost($chunks chunks, $bytes B, $airtime)';
}

/// A transfer ready to send: the encoded bytes, the chunks that carry them,
/// and what they cost.
final class MediaTransferPlan {
  const MediaTransferPlan({
    required this.payloadId,
    required this.kind,
    required this.photo,
    required this.payload,
    required this.chunks,
    required this.cost,
    required this.withinBudget,
  });

  /// Random per transfer rather than a counter, so two senders on one channel
  /// cannot collide on the same id with the same chunk count.
  final int payloadId;
  final MediaKind kind;
  final MediaPhoto photo;
  final Uint8List payload;
  final List<Uint8List> chunks;
  final MediaTransferCost cost;

  /// False when the encoder could not reach the byte budget even at its lowest
  /// quality. The sender may still choose to send it; the surface has to say so
  /// first rather than discovering it halfway through a transfer.
  final bool withinBudget;
}

/// The outcome of preparing a picture: a plan, or the rule that refused it.
sealed class MediaPreparation {
  const MediaPreparation();
}

final class MediaPrepared extends MediaPreparation {
  const MediaPrepared(this.plan);

  final MediaTransferPlan plan;
}

final class MediaRefused extends MediaPreparation {
  const MediaRefused(this.refusal);

  final MediaSendRefusal refusal;
}

/// How one datagram ended, as the sender's loop needs it.
///
/// The mapping from the radio's answer is the honest part:
///
/// * `accepted` is the radio taking the datagram. For group data that is all a
///   sender can ever know — there is no ACK — so the receipt says "accepted",
///   never "delivered".
/// * `noAnswer` still counts as a send: the frame was written, the radio may
///   have transmitted it, so it is charged and not retried forever.
/// * `refusedLocally` and `refusedByRadio` are the only outcomes that cost the
///   chunk an attempt.
/// * `notReady` wrote nothing, so it must not burn an attempt; it is handled as
///   capacity, which is the requeue-without-attempt branch.
MediaSendResult resultFor(ChannelDataSendStatus status) => switch (status) {
      ChannelDataSendStatus.accepted => MediaSendResult.accepted,
      ChannelDataSendStatus.noAnswer => MediaSendResult.accepted,
      ChannelDataSendStatus.refusedLocally => MediaSendResult.refused,
      ChannelDataSendStatus.refusedByRadio => MediaSendResult.refused,
      ChannelDataSendStatus.notReady => MediaSendResult.tableFull,
    };

/// One outbound transfer, driven by the sender's pacing.
final class MediaUpload {
  MediaUpload({
    required this.plan,
    required DateTime Function() clock,
    Future<void> Function(Duration)? wait,
  })  : _wait = wait ?? _realWait,
        _sender = MediaSender(chunks: plan.chunks, clock: clock);

  final MediaTransferPlan plan;
  final Future<void> Function(Duration) _wait;
  final MediaSender _sender;
  final Set<String> _requestsTaken = <String>{};

  /// How many throws from the radio call, in a row, are treated as a busy
  /// link before the transfer stops pretending. One throw is a hiccup; a run
  /// of them is the link being gone, and the caller needs that error rather
  /// than the engine's own end-of-loop one.
  static const int maxConsecutiveSendFailures = 3;
  int _consecutiveSendFailures = 0;

  int get sent => _sender.delivered;

  int get chunks => _sender.chunkCount;

  bool get complete => _sender.complete;

  bool get failed => _sender.failed;

  Duration get waitBeforeDue => _sender.waitBeforeDue;

  MediaReceipt? get receipt => _sender.receipt;

  /// Drives the whole transfer, one paced datagram at a time.
  ///
  /// [send] is the radio call. It returns the app's datagram result, and this
  /// loop turns it into the sender's vocabulary so the retry rules stay in one
  /// place: a refusal salts the resend, capacity pauses without spending an
  /// attempt, and nothing is ever sent twice byte-identical.
  Future<MediaReceipt> run(
    Future<ChannelDataSendResult> Function(Uint8List blob) send,
  ) async {
    // One record per payload in flight: a process kill loses the transfer, and
    // the next launch reports it as interrupted instead of dropping it.
    await MediaJournal.markStarted(plan.payloadId);
    try {
      return await _run(send);
    } finally {
      // A transfer that never reached its end keeps the record, which is what
      // the next launch reads.
      if (_sender.complete) await MediaJournal.markFinished(plan.payloadId);
    }
  }

  Future<MediaReceipt> _run(
    Future<ChannelDataSendResult> Function(Uint8List blob) send,
  ) async {
    while (!_sender.complete && !_sender.failed) {
      final List<MediaSend> due = _sender.takeDue();
      if (due.isEmpty) {
        final Duration wait = _sender.waitBeforeDue;
        if (wait <= Duration.zero) {
          // Nothing due and nothing to wait for means the transfer is finished
          // or lost; the loop condition above is the only other exit.
          break;
        }
        await _wait(wait);
        continue;
      }
      for (final MediaSend item in due) {
        final ChannelDataSendResult result;
        try {
          result = await send(item.blob);
          _consecutiveSendFailures = 0;
        } catch (_) {
          // The call threw, so nothing was written: the chunk goes back to the
          // front of the queue with no attempt spent, the same accounting a
          // full packet table gets. Without this the chunk is lost and the
          // loop ends by throwing its own "no receipt" error, which names
          // neither the chunk nor the radio's failure.
          _consecutiveSendFailures++;
          _sender.acknowledge(item.index, MediaSendResult.tableFull);
          if (_consecutiveSendFailures >= maxConsecutiveSendFailures) rethrow;
          continue;
        }
        _sender.acknowledge(item.index, resultFor(result.status));
      }
    }
    if (_sender.failed) {
      throw MediaUploadFailed(_sender.lost);
    }
    final MediaReceipt? receipt = _sender.receipt;
    if (receipt == null) {
      // Unreachable by construction; kept so a receipt is never invented.
      throw StateError('transfer ended without a receipt');
    }
    return receipt;
  }

  /// A receiver asked for [missing] chunks of this payload.
  ///
  /// A request is evidence the datagrams did not arrive, so the resend takes a
  /// fresh salt — sending the same bytes again is the one thing the radio's
  /// seen-table guarantees will be dropped. Each index is answered once per
  /// transfer: a second identical request is the receiver's own duplicate, and
  /// re-sending on it would spend airtime on a packet already on its way.
  int acceptRequest(List<int> missing) {
    int requeued = 0;
    for (final int index in missing) {
      if (index < 0 || index >= _sender.chunkCount) continue;
      if (_sender.complete) break;
      if (!_requestsTaken.add('${plan.payloadId}:$index')) continue;
      _sender.acknowledge(index, MediaSendResult.refused);
      requeued++;
    }
    return requeued;
  }

  static Future<void> _realWait(Duration d) => Future<void>.delayed(d);
}

/// A transfer that ran out of resend attempts on at least one chunk.
final class MediaUploadFailed implements Exception {
  const MediaUploadFailed(this.lost);

  final Set<int> lost;

  @override
  String toString() => 'MediaUploadFailed(lost ${lost.length} chunks)';
}

/// What an inbound datagram did.
enum MediaIntake {
  /// It joined a transfer; the payload is not complete yet.
  chunk,

  /// It was already recorded. Normal traffic: the radio retries.
  duplicate,

  /// It was a request for missing chunks, not a chunk.
  request,

  /// It completed a transfer. [MediaDownload.payloadFor] now returns bytes.
  complete,

  /// It was not a media datagram this build can use.
  refused,
}

/// How much of a transfer has arrived, and what a request should ask for.
final class MediaDownloadProgress {
  const MediaDownloadProgress({
    required this.payloadId,
    required this.kind,
    required this.received,
    required this.count,
    required this.missing,
  });

  final int payloadId;
  final MediaKind kind;
  final int received;
  final int count;
  final List<int> missing;

  bool get complete => missing.isEmpty;

  double get fraction => count == 0 ? 0 : received / count;
}

/// One inbound direction: datagrams in, a payload and a picture out.
final class MediaDownload {
  MediaDownload({MediaReassembler? reassembler})
      : _reassembler = reassembler ?? MediaReassembler();

  final MediaReassembler _reassembler;

  MediaChunkRefusal? _lastChunkRefusal;
  MediaReassemblyRefusal? _lastReassemblyRefusal;
  MediaChunk? _lastRequest;
  final Map<int, MediaChunk> _lastRequestSeen = <int, MediaChunk>{};

  /// Why the last datagram was refused, when it was. Chunk-level and
  /// transfer-level refusals are different answers, so they stay separate:
  /// a duplicate is normal traffic and a CRC mismatch is a bad packet.
  MediaChunkRefusal? get lastChunkRefusal => _lastChunkRefusal;

  MediaReassemblyRefusal? get lastReassemblyRefusal => _lastReassemblyRefusal;

  /// The most recent request a peer sent, so a surface can answer it.
  MediaChunk? get lastRequest => _lastRequest;

  Iterable<MediaTransfer> get transfers => _reassembler.transfers;

  /// The reassembler itself, read-only for callers that need its eviction
  /// count: a transfer dropped to make room is a fact the inbox reports.
  MediaReassembler get reassembler => _reassembler;

  /// Takes one datagram blob. A request is routed away from the reassembler —
  /// a bitmap is not image bytes — and reported as [MediaIntake.request].
  MediaIntake accept(List<int> blob, {DateTime? now}) {
    _lastChunkRefusal = null;
    _lastReassemblyRefusal = null;
    final MediaChunkParse parsed = MediaChunkCodec.parse(blob);
    final MediaChunk? chunk = parsed.chunk;
    if (chunk == null) {
      _lastChunkRefusal = parsed.refusal;
      return MediaIntake.refused;
    }
    if (chunk.kind == MediaKind.request) {
      _lastRequest = chunk;
      _lastRequestSeen[chunk.payloadId] = chunk;
      return MediaIntake.request;
    }
    final MediaTransfer? complete =
        _reassembler.add(chunk, now: now);
    _lastReassemblyRefusal = _reassembler.lastRefusal;
    if (_lastReassemblyRefusal != null) {
      // A duplicate is normal traffic. Every other refusal is a datagram this
      // build will not use, and calling a frame that names 65,535 chunks a
      // duplicate would hide the only interesting thing about it.
      return _lastReassemblyRefusal == MediaReassemblyRefusal.duplicate
          ? MediaIntake.duplicate
          : MediaIntake.refused;
    }
    return complete == null ? MediaIntake.chunk : MediaIntake.complete;
  }

  MediaTransfer? transfer(int payloadId) => _reassembler.transfer(payloadId);

  MediaDownloadProgress? progressFor(int payloadId) {
    final MediaTransfer? t = _reassembler.transfer(payloadId);
    if (t == null) return null;
    return MediaDownloadProgress(
      payloadId: t.payloadId,
      kind: t.kind,
      received: t.received,
      count: t.count,
      missing: t.missing,
    );
  }

  /// The complete payload, or null while any chunk is missing. A partial
  /// payload is not a smaller payload; it is a broken one.
  Uint8List? payloadFor(int payloadId) =>
      _reassembler.transfer(payloadId)?.assemble();

  /// Forgets a payload once its bytes have been handed on. The dedupe window
  /// keeps the slots, so a replayed chunk cannot resurrect it.
  void forget(int payloadId) {
    _reassembler.forget(payloadId);
    _lastRequestSeen.remove(payloadId);
  }

  /// The datagram that asks [payloadId]'s sender for exactly what is missing,
  /// or null when nothing is missing (or the transfer is unknown).
  Uint8List? requestBytesFor(int payloadId) {
    final MediaTransfer? t = _reassembler.transfer(payloadId);
    if (t == null || t.complete) return null;
    return MediaRequestCodec.encode(
      payloadId: t.payloadId,
      kind: t.kind,
      count: t.count,
      missing: t.missing,
    );
  }

  /// Decodes a complete payload into a picture. The codec owns the failure
  /// vocabulary, so a surface shows one sentence rather than a stack trace.
  Future<MediaPhoto> decode(MediaCodec codec, Uint8List payload) =>
      codec.decode(payload);
}

/// Prepares outbound media and owns the inbound direction.
///
/// One object so a surface has one dependency, and so the payload id generator
/// has exactly one implementation (random in production, fixed in tests).
final class MediaTransferService {
  MediaTransferService({
    required this.codec,
    required this.estimator,
    required this.clock,
    this.kind = MediaKind.image,
    this.mediaOnPublic = false,
    this.wait = _realWait,
    MediaDownload? download,
    int Function()? newPayloadId,
  })  : _newPayloadId = newPayloadId ?? _randomPayloadId,
        download = download ?? MediaDownload();

  final MediaCodec codec;
  final AirtimeEstimator estimator;
  final DateTime Function() clock;
  final MediaKind kind;
  final bool mediaOnPublic;

  /// How the pacing loop sleeps. Injected so a test's clock owns the time and
  /// a transfer that would take a minute costs none.
  final Future<void> Function(Duration) wait;
  final MediaDownload download;
  final int Function() _newPayloadId;

  /// Encodes [photo] and works out what sending it would cost.
  ///
  /// The order matters: the Public gate is checked before the encode, because
  /// refusing after a second of native encoding would be rude and would also
  /// make the refusal look like an encoder failure.
  Future<MediaPreparation> prepare(
    MediaPhoto photo, {
    required List<int>? channelPsk,
    required int byteBudget,
  }) async {
    final MediaSendRefusal? refusal = MediaSendPolicy(mediaOnPublic: mediaOnPublic)
        .channelRefusalFor(channelPsk: channelPsk);
    if (refusal != null) return MediaRefused(refusal);

    final EncodedPhoto encoded = await codec.encode(photo, byteBudget: byteBudget);
    final int payloadId = _newPayloadId();
    final List<Uint8List> chunks = MediaChunkCodec.split(
      encoded.bytes,
      payloadId: payloadId,
      kind: kind,
    );
    return MediaPrepared(MediaTransferPlan(
      payloadId: payloadId,
      kind: kind,
      photo: photo,
      payload: encoded.bytes,
      chunks: chunks,
      cost: MediaTransferCost(
        chunks: chunks.length,
        bytes: encoded.bytes.length,
        // Every datagram is its own frame on air: the radio wraps each blob in
        // the datagram header and the packet it sends, so the cost is the sum
        // over chunks of the bytes that datagram puts on air — not one byte
        // per chunk, which understated a photo by roughly two orders of
        // magnitude.
        airtime: chunks.fold<Duration>(
          Duration.zero,
          (Duration sum, Uint8List chunk) => sum +
              estimator.forBytes(ChannelDataLimits.airtimeBytesFor(chunk.length)),
        ),
      ),
      withinBudget: encoded.withinBudget,
    ));
  }

  MediaUpload upload(MediaTransferPlan plan) =>
      MediaUpload(plan: plan, clock: clock, wait: wait);

  static Future<void> _realWait(Duration d) => Future<void>.delayed(d);

  static int _randomPayloadId() {
    // Random, because a counter would collide with another sender's counter on
    // the same channel. 30 bits leaves the top bits clear for diagnostics.
    final int seed = DateTime.now().microsecondsSinceEpoch;
    return (seed ^ (seed >> 11) ^ (seed >> 23)) & 0x3FFFFFFF;
  }
}
