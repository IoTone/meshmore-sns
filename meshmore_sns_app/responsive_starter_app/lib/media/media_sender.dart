// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:collection';
import 'dart:typed_data';

import 'media_chunk.dart';

/// What the radio said about one datagram.
enum MediaSendResult {
  /// The radio took it. For a channel datagram that is as much as the sender
  /// can know: success here is "accepted", not "delivered" — there is no ACK
  /// for group data, and the register is explicit that a broadcast carries no
  /// delivery promise.
  accepted,

  /// `ERR_CODE_TABLE_FULL`: the packet table is full. Capacity, not failure —
  /// the packet was never on air, so the chunk is still unsent.
  tableFull,

  /// The radio refused the datagram itself. This is the only result that can
  /// cost a chunk for good.
  refused,

  /// This app's own duty-cycle meter refused it before the radio saw the
  /// frame. Capacity, like [tableFull], and it clears when the window rolls
  /// over: the chunk goes back at the front and no attempt is spent.
  budgetRefused,
}

/// One datagram the sender wants on air.
final class MediaSend {
  const MediaSend({
    required this.index,
    required this.attempt,
    required this.blob,
  });

  final int index;
  final int attempt;
  final Uint8List blob;

  bool get isResend => attempt > 0;
}

/// The transfer as the sender sees it: what is left, what has been resent,
/// and whether it is finished.
final class MediaReceipt {
  const MediaReceipt({
    required this.chunks,
    required this.resends,
    required this.elapsed,
  });

  final int chunks;
  final int resends;
  final Duration elapsed;
}

/// Paces a media payload onto the radio.
///
/// The rules are the register's, and each one is here because the radio makes
/// the naive version fail:
///
/// * **350 ms between sends.** A companion's packet table is small; a burst
///   is answered with `TABLE_FULL`, which the app must treat as capacity and
///   not as loss.
/// * **Salt every resend.** The radio drops a packet it has already seen, so
///   a byte-identical retry is never heard. The salt is the chunk's attempt
///   nibble — see [MediaChunkCodec].
/// * **Marked packets.** `attempt > 0` is the mark; the receiver counts
///   resends so a lossy link can be told from a busy one.
/// * **A completion receipt.** Not a delivery promise: a receipt is the
///   sender's own account of what it put on air, which is all a broadcast can
///   ever produce.
final class MediaSender {
  MediaSender({
    required List<Uint8List> chunks,
    required DateTime Function() clock,
    this.pacing = const Duration(milliseconds: 350),
    this.tableFullBackoff = const Duration(seconds: 2),
    this.maxAttempt = MediaChunkCodec.maxAttempt,
  })  : _chunks = List<Uint8List>.unmodifiable(chunks),
        _clock = clock {
    for (int i = 0; i < _chunks.length; i++) {
      _pending.add(i);
    }
  }

  final List<Uint8List> _chunks;
  final DateTime Function() _clock;
  final Duration pacing;
  final Duration tableFullBackoff;
  final int maxAttempt;

  final ListQueue<int> _pending = ListQueue<int>();
  final Map<int, int> _attempts = <int, int>{};
  final Set<int> _delivered = <int>{};
  final Set<int> _lost = <int>{};

  DateTime? _nextSendAt;
  DateTime? _pausedUntil;
  DateTime? _startedAt;
  int _resends = 0;

  int get chunkCount => _chunks.length;

  int get delivered => _delivered.length;

  bool get complete => _delivered.length == _chunks.length;

  bool get failed => _lost.isNotEmpty;

  /// Indexes the radio refused for good.
  Set<int> get lost => Set<int>.unmodifiable(_lost);

  /// Indexes still to send, in queue order.
  List<int> get pending => List<int>.unmodifiable(_pending);

  /// True while a `TABLE_FULL` answer is holding the queue back.
  bool get paused {
    final DateTime now = _clock();
    return _pausedUntil != null && now.isBefore(_pausedUntil!);
  }

  MediaReceipt? get receipt {
    if (!complete) return null;
    final DateTime? start = _startedAt;
    return MediaReceipt(
      chunks: _chunks.length,
      resends: _resends,
      elapsed: start == null ? Duration.zero : _clock().difference(start),
    );
  }

  /// How long until [takeDue] can return a packet, or zero when it can now.
  ///
  /// The paced loop needs this: "nothing is due" is not a reason to spin, and
  /// the wait is either the pacing interval or the table-full backoff,
  /// whichever is further out.
  Duration get waitBeforeDue {
    final DateTime now = _clock();
    DateTime? until;
    if (_pausedUntil != null && now.isBefore(_pausedUntil!)) {
      until = _pausedUntil;
    }
    final DateTime? next = _nextSendAt;
    if (next != null && now.isBefore(next)) {
      until = until == null || next.isAfter(until) ? next : until;
    }
    if (until == null) return Duration.zero;
    return until.difference(now);
  }

  /// What may go on air now: at most one chunk, because the pacing is a
  /// minimum interval rather than a burst size. An empty list means "wait".
  List<MediaSend> takeDue() {
    final DateTime now = _clock();
    if (_pending.isEmpty || complete) return const <MediaSend>[];
    if (_pausedUntil != null && now.isBefore(_pausedUntil!)) {
      return const <MediaSend>[];
    }
    final DateTime? next = _nextSendAt;
    if (next != null && now.isBefore(next)) return const <MediaSend>[];
    final int index = _pending.removeFirst();
    final int attempt = _attempts[index] ?? 0;
    _startedAt ??= now;
    _nextSendAt = now.add(pacing);
    if (attempt > 0) _resends++;
    return <MediaSend>[
      MediaSend(index: index, attempt: attempt, blob: _salted(index, attempt)),
    ];
  }

  /// The bytes for [index] at [attempt].
  ///
  /// A resend rewrites the header's attempt nibble and nothing else: the CRC
  /// covers the payload, so a salted packet still validates at the receiver,
  /// and the radio's seen-table — which compares whole payloads — sees a
  /// packet it has not carried before. Sending the original bytes again is the
  /// one thing that cannot work, which is why the pacing loop does not return
  /// the stored blob for a retry.
  Uint8List _salted(int index, int attempt) {
    final Uint8List stored = _chunks[index];
    if (attempt == 0) return stored;
    final Uint8List out = Uint8List.fromList(stored);
    out[0] = (MediaChunkCodec.version << 4) | attempt;
    return out;
  }

  /// Records what the radio said. A `TABLE_FULL` puts the chunk back at the
  /// front of the queue and pauses the sender; it must not count as an
  /// attempt, because nothing was transmitted.
  void acknowledge(int index, MediaSendResult result) {
    switch (result) {
      case MediaSendResult.accepted:
        _delivered.add(index);
      case MediaSendResult.tableFull:
        _pending.addFirst(index);
        _pausedUntil = _clock().add(tableFullBackoff);
      case MediaSendResult.budgetRefused:
        _pending.addFirst(index);
        _pausedUntil = _clock().add(tableFullBackoff);
      case MediaSendResult.refused:
        final int next = (_attempts[index] ?? 0) + 1;
        _attempts[index] = next;
        if (next > maxAttempt) {
          _lost.add(index);
        } else {
          _pending.addFirst(index);
        }
    }
  }

  /// The exact bytes for a resend of [index], so the caller never has to
  /// rebuild a header itself and never accidentally re-send an identical
  /// packet.
  Uint8List resendOf(int index, MediaChunk chunk) {
    final int attempt = (_attempts[index] ?? 0) + 1;
    if (attempt > maxAttempt) {
      throw StateError('chunk $index has no salt space left');
    }
    return MediaChunkCodec.encode(
      payloadId: chunk.payloadId,
      kind: chunk.kind,
      index: chunk.index,
      count: chunk.count,
      data: chunk.data,
      attempt: attempt,
    );
  }
}
