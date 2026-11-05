// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:collection';
import 'dart:typed_data';

import 'media_chunk.dart';

/// Why an inbound chunk did not join a transfer.
enum MediaReassemblyRefusal {
  /// The chunk arrived twice. The radio retries and a resend is salted, so a
  /// duplicate is normal traffic rather than an error.
  duplicate,

  /// A chunk that is not a chunk of this payload: a different kind, or a
  /// different chunk count for the same id. One of the two senders is wrong
  /// and the transfer cannot be trusted, so it is dropped.
  conflictingTransfer,

  /// A chunk of a payload this receiver has already handed on. The dedupe
  /// window covers a replay for as long as its slots live; this is the same
  /// answer once the window has moved on.
  alreadyCompleted,

  /// The frame named more chunks than a transfer can hold. The count comes
  /// from the same unauthenticated source as the bytes, so it cannot size the
  /// pool.
  countTooLarge,
}

/// An assembled payload, or the state of a transfer that is still missing
/// chunks.
final class MediaTransfer {
  MediaTransfer({
    required this.payloadId,
    required this.kind,
    required this.count,
    required this.firstSeenAt,
  }) : lastSeenAt = firstSeenAt;

  final int payloadId;
  final MediaKind kind;
  final int count;
  final DateTime firstSeenAt;
  DateTime lastSeenAt;

  final Map<int, Uint8List> _chunks = <int, Uint8List>{};

  int get received => _chunks.length;

  bool get complete => _chunks.length == count;

  /// Indexes that have not arrived, ascending. This is what the requester
  /// asks for: exactly what is missing, never a re-request of everything.
  List<int> get missing => <int>[
        for (int i = 0; i < count; i++)
          if (!_chunks.containsKey(i)) i,
      ];

  /// The payload in chunk order, or null while a chunk is missing — a
  /// partial payload is not a smaller payload, it is a broken one.
  Uint8List? assemble() {
    if (!complete) return null;
    final BytesBuilder out = BytesBuilder(copy: false);
    for (int i = 0; i < count; i++) {
      out.add(_chunks[i]!);
    }
    return out.takeBytes();
  }

  /// Fills a slot from an FEC repair block. The caller has already proved the
  /// bytes; this only records them, so a repaired payload goes through the
  /// same completion path as a received one.
  void restore(int index, Uint8List data, {DateTime? now}) {
    _chunks.putIfAbsent(index, () => data);
    lastSeenAt = now ?? DateTime.now();
  }
}

/// Reassembles media payloads out of individual datagrams.
///
/// Two bounds, both from the register's transport ruling:
/// * **16 transfers** in flight. A seventeenth evicts the transfer that has
///   been quiet longest, because a stalled transfer will not finish and a
///   live one is being actively fed.
/// * **160 chunks** of dedupe memory. The radio retries, so the same chunk
///   arrives again; without a window a late duplicate would re-arm a
///   transfer that has already completed. The window is what makes a
///   duplicate cheap and a replay harmless.
/// * **[maxChunks] per transfer.** A 16-bit count from a peer would otherwise
///   let one transfer hold ~9.8 MB and the pool ~157 MB, so the field is
///   bounded here rather than trusted.
/// * **A bounded completion memory.** The dedupe window forgets; a replay
///   after 160 other chunks would otherwise reassemble the payload a second
///   time. Completed ids are remembered for [completedMemory] payloads, which
///   is enough to refuse the replay the radio actually produces.
final class MediaReassembler {
  MediaReassembler({
    this.maxTransfers = 16,
    this.dedupeWindow = 160,
  });

  final int maxTransfers;
  final int dedupeWindow;

  /// Chunks one transfer may name. The app's own largest payload is a 4 KB
  /// photo (28 chunks) and a 20-packet voice message, so this leaves two
  /// orders of magnitude of headroom and still bounds the pool.
  static const int maxChunks = 512;

  /// Completed payloads remembered to refuse a replay, and evictions kept for
  /// the caller to name. Both are bounded because the process outlives any
  /// one transfer, and both are large enough that the bound is reached only
  /// after a session's worth of traffic rather than by a replay arriving a
  /// little late.
  static const int completedMemory = 1024;
  static const int evictionMemory = 32;

  final LinkedHashMap<int, MediaTransfer> _transfers =
      LinkedHashMap<int, MediaTransfer>();

  /// Insertion-ordered slot keys; the oldest is dropped past [dedupeWindow].
  final LinkedHashSet<String> _seen = LinkedHashSet<String>();

  /// Payload ids already handed on, oldest first, bounded by
  /// [completedMemory].
  final LinkedHashSet<int> _completed = LinkedHashSet<int>();

  int _completedCount = 0;
  int _evictedCount = 0;

  /// The most recent evictions, oldest first, so a caller can tell the user
  /// which payload will never complete. Bounded by [evictionMemory];
  /// [evictions] counts them all.
  final List<int> evicted = <int>[];

  /// Every eviction this reassembler has made, including the ones that have
  /// fallen out of [evicted].
  int get evictions => _evictedCount;

  /// Payloads completed here, for a surface that wants to say how much traffic
  /// it has taken.
  int get completions => _completedCount;

  Iterable<MediaTransfer> get transfers => _transfers.values;

  MediaTransfer? transfer(int payloadId) => _transfers[payloadId];

  /// Adds one chunk. Returns the transfer when the payload is now complete,
  /// null when it is still short, and throws nothing: every refusal is a
  /// named value in [lastRefusal].
  MediaReassemblyRefusal? lastRefusal;

  MediaTransfer? add(MediaChunk chunk, {DateTime? now}) {
    final DateTime at = now ?? DateTime.now();
    lastRefusal = null;
    if (chunk.count > maxChunks) {
      lastRefusal = MediaReassemblyRefusal.countTooLarge;
      return null;
    }
    if (_completed.contains(chunk.payloadId)) {
      lastRefusal = MediaReassemblyRefusal.alreadyCompleted;
      return null;
    }
    if (_seen.contains(chunk.slotKey)) {
      lastRefusal = MediaReassemblyRefusal.duplicate;
      return null;
    }
    MediaTransfer? t = _transfers[chunk.payloadId];
    if (t == null) {
      if (_transfers.length >= maxTransfers) {
        // The oldest insertion is the one that has been quiet longest: every
        // add re-inserts, so order is last-seen order.
        final int victim = _transfers.keys.first;
        _transfers.remove(victim);
        _rememberEvicted(victim);
      }
      t = MediaTransfer(
        payloadId: chunk.payloadId,
        kind: chunk.kind,
        count: chunk.count,
        firstSeenAt: at,
      );
    } else if (t.kind != chunk.kind || t.count != chunk.count) {
      lastRefusal = MediaReassemblyRefusal.conflictingTransfer;
      return null;
    }
    // Re-insert at the end so the pool is ordered by last activity.
    _transfers.remove(t.payloadId);
    _transfers[t.payloadId] = t;
    t._chunks[chunk.index] = chunk.data;
    t.lastSeenAt = at;
    _remember(chunk.slotKey);
    if (!t.complete) return null;
    _rememberCompleted(t.payloadId);
    return t;
  }

  void _rememberEvicted(int payloadId) {
    _evictedCount++;
    evicted.add(payloadId);
    while (evicted.length > evictionMemory) {
      evicted.removeAt(0);
    }
  }

  /// Remembers a payload that was handed on. Bounded, because payload ids are
  /// 32 bits and a long session would otherwise hold every one it ever saw.
  void _rememberCompleted(int payloadId) {
    _completedCount++;
    _completed.remove(payloadId);
    _completed.add(payloadId);
    while (_completed.length > completedMemory) {
      _completed.remove(_completed.first);
    }
  }

  void _remember(String key) {
    _seen.remove(key);
    _seen.add(key);
    while (_seen.length > dedupeWindow) {
      _seen.remove(_seen.first);
    }
  }

  /// Forgets a transfer once its payload has been handed on. The dedupe
  /// window keeps the slots, so a replayed chunk cannot resurrect it.
  void forget(int payloadId) => _transfers.remove(payloadId);

  /// True when this slot was already recorded, used by the sender side of a
  /// request-missing loop to avoid asking twice for one chunk in one round.
  bool hasSeen(int payloadId, int index) =>
      _seen.contains('$payloadId:$index');
}
