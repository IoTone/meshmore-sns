// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';

import '../meshcore/airtime.dart';
import '../meshcore/channel_datagram.dart';
import '../voice/voice_codec.dart';
import '../voice/voice_payload.dart';
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
const int kMediaPhotoBudgetBytes = 1600;

/// The three sizes a photo may be sent at, and what each one costs on air.
///
/// The owner's report — "one photo said sixteen messages, which is way too much
/// airtime" — is a byte-budget complaint, not a codec complaint: every chunk is
/// its own LoRa frame, so the airtime is the chunk count, and the old 4096-byte
/// budget was 28 chunks in the worst case and 18 for a real photo. On five of the
/// six region presets a full-budget photo cannot fit inside the 36 s/hour
/// voluntary budget at all, so the upload stalls until the hour rolls over.
///
/// The floor drops with the budget because bytes are pixels: a 1600-byte AVIF at
/// 256×192 is a legible snapshot of a sign or a page, and a 600-byte one at
/// 160×120 is a thumbnail that says what the picture is about. The biggest size
/// stays for someone who needs it.
enum MediaSendSize {
  /// One glance: what the picture is of.
  preview(budgetBytes: 600, maxWidth: 160, maxHeight: 120),

  /// The default. A snapshot you can read.
  standard(budgetBytes: kMediaPhotoBudgetBytes, maxWidth: 256, maxHeight: 192),

  /// The old behaviour, kept for detail that matters.
  full(budgetBytes: 4096, maxWidth: 320, maxHeight: 240);

  const MediaSendSize({
    required this.budgetBytes,
    required this.maxWidth,
    required this.maxHeight,
  });

  final int budgetBytes;
  final int maxWidth;
  final int maxHeight;
}

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

  /// The picture this plan encodes, or null for a payload that is not one —
  /// a recorded voice note. The plan's own fields are format-neutral because
  /// the sender, the journal and the receipt never needed to know which kind
  /// they were carrying; only a surface that draws a picture does, and it has
  /// the photo it asked to encode.
  final MediaPhoto? photo;
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
      ChannelDataSendStatus.refusedAirtime => MediaSendResult.budgetRefused,
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

  /// Consecutive capacity answers before the loop stops.
  ///
  /// Six is 12 s at the sender's 2 s backoff: long enough that a busy packet
  /// table clears, short enough that nobody watches a stalled line for a
  /// minute. The airtime window is a different scale and is refused by the same
  /// counter — a window that is closed for an hour is not something a progress
  /// bar should pretend to wait for.
  static const int maxCapacityAnswers = 6;
  int _capacityAnswers = 0;

  bool _cancelled = false;

  /// Stops the loop. Safe from any thread of the app, including the sheet's
  /// `dispose`.
  void cancel() => _cancelled = true;

  bool get cancelled => _cancelled;

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
      if (_cancelled) throw const MediaUploadCancelled();
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
        final MediaSendResult outcome = resultFor(result.status);
        _sender.acknowledge(item.index, outcome);
        if (outcome == MediaSendResult.tableFull ||
            outcome == MediaSendResult.budgetRefused) {
          _capacityAnswers++;
          if (_capacityAnswers >= maxCapacityAnswers) {
            throw MediaUploadStalled(outcome, _sender.pending.toSet());
          }
        } else {
          _capacityAnswers = 0;
        }
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

/// A transfer stopped because capacity never came back.
///
/// `TABLE_FULL` and this app's own duty-cycle refusal are both "nothing was
/// written", so the sender requeues without spending an attempt — which is
/// right for one answer and wrong for fifty: the radio's table can stay full,
/// and the airtime window can be closed for an hour. A run of them past a
/// ceiling stops the loop and says which capacity refused it, so a surface can
/// say "the radio is busy" or "this hour's airtime is spent" instead of holding
/// a progress line that will not move.
final class MediaUploadStalled implements Exception {
  const MediaUploadStalled(this.reason, this.pending);

  /// [MediaSendResult.tableFull] or [MediaSendResult.budgetRefused].
  final MediaSendResult reason;

  /// Chunks that never went on air, ascending.
  final Set<int> pending;

  @override
  String toString() =>
      'MediaUploadStalled(${reason.name}, ${pending.length} chunks)';
}

/// The caller stopped the transfer: the sheet closed, or a newer send replaced
/// it. Not an error — the sender simply stops pacing datagrams onto a link the
/// user has walked away from.
final class MediaUploadCancelled implements Exception {
  const MediaUploadCancelled();

  @override
  String toString() => 'MediaUploadCancelled()';
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
    int? byteBudget,
    MediaSendSize size = MediaSendSize.standard,
  }) async {
    final MediaSendRefusal? refusal = MediaSendPolicy(mediaOnPublic: mediaOnPublic)
        .channelRefusalFor(channelPsk: channelPsk);
    if (refusal != null) return MediaRefused(refusal);

    final EncodedPhoto encoded = await codec.encode(
      photo,
      byteBudget: byteBudget ?? size.budgetBytes,
      maxWidth: size.maxWidth,
      maxHeight: size.maxHeight,
    );
    // Every datagram is its own frame on air: the radio wraps each blob in the
    // datagram header and the packet it sends, so the cost is the sum over
    // chunks of the bytes that datagram puts on air — not one byte per chunk,
    // which understated a photo by roughly two orders of magnitude.
    return _planFor(
      payload: encoded.bytes,
      kind: kind,
      photo: photo,
      withinBudget: encoded.withinBudget,
    );
  }

  /// Works out what a recorded note costs before any of it is queued.
  ///
  /// The order is the photo's and for the same reason: the channel rules run
  /// before the payload is built, because refusing media on the Public channel
  /// after the codec has run would look like a codec failure. The payload is
  /// the packed frames behind [VoicePayloadCodec]'s one-byte header, so the
  /// receiver can tell which width to decode at.
  ///
  /// [withinBudget] is true by construction: the ceiling that matters is the
  /// capture's 20 seconds, which stopped the microphone rather than trimming
  /// the frames afterwards.
  Future<MediaPreparation> prepareVoice({
    required PackedVoice voice,
    required List<int>? channelPsk,
  }) async {
    final MediaSendPolicy policy =
        MediaSendPolicy(mediaOnPublic: mediaOnPublic);
    // The channel rules first, because an encode that runs before a refusal is
    // work done to reach an answer the rules already had.
    final MediaSendRefusal? channelRefusal =
        policy.channelRefusalFor(channelPsk: channelPsk);
    if (channelRefusal != null) return MediaRefused(channelRefusal);
    final Uint8List payload;
    try {
      payload = VoicePayloadCodec.encode(voice);
    } on VoiceException {
      // An empty take is the same refusal every other kind gets from its own
      // size rule, rather than a codec exception reaching a surface.
      return const MediaRefused(MediaSendRefusal.payloadUnusable);
    }
    final MediaSendRefusal? refusal = policy.refusalFor(
      channelPsk: channelPsk,
      payloadBytes: payload.length,
    );
    if (refusal != null) return MediaRefused(refusal);
    return _planFor(
      payload: payload,
      kind: MediaKind.voice,
      photo: null,
      withinBudget: true,
    );
  }

  MediaUpload upload(MediaTransferPlan plan) =>
      MediaUpload(plan: plan, clock: clock, wait: wait);

  /// The plan for one payload, whatever produced it.
  ///
  /// One place for the two rules every kind shares: a payload that fits in no
  /// datagram is refused by name, and a payload the receiver's own reassembler
  /// would refuse for naming too many chunks is refused here instead of after
  /// twenty datagrams have gone on air.
  MediaPreparation _planFor({
    required Uint8List payload,
    required MediaKind kind,
    required MediaPhoto? photo,
    required bool withinBudget,
  }) {
    if (payload.isEmpty) {
      return const MediaRefused(MediaSendRefusal.payloadUnusable);
    }
    final int chunkCount =
        (payload.length + MediaChunkCodec.maxDataBytes - 1) ~/
            MediaChunkCodec.maxDataBytes;
    if (chunkCount > MediaReassembler.maxChunks) {
      return const MediaRefused(MediaSendRefusal.payloadUnusable);
    }
    final int payloadId = _newPayloadId();
    final List<Uint8List> chunks = MediaChunkCodec.split(
      payload,
      payloadId: payloadId,
      kind: kind,
    );
    return MediaPrepared(MediaTransferPlan(
      payloadId: payloadId,
      kind: kind,
      photo: photo,
      payload: payload,
      chunks: chunks,
      cost: MediaTransferCost(
        chunks: chunks.length,
        bytes: payload.length,
        airtime: chunks.fold<Duration>(
          Duration.zero,
          (Duration sum, Uint8List chunk) => sum +
              estimator.forBytes(ChannelDataLimits.airtimeBytesFor(chunk.length)),
        ),
      ),
      withinBudget: withinBudget,
    ));
  }


  static Future<void> _realWait(Duration d) => Future<void>.delayed(d);

  static int _randomPayloadId() {
    // Random, because a counter would collide with another sender's counter on
    // the same channel. 30 bits leaves the top bits clear for diagnostics.
    final int seed = DateTime.now().microsecondsSinceEpoch;
    return (seed ^ (seed >> 11) ^ (seed >> 23)) & 0x3FFFFFFF;
  }
}
