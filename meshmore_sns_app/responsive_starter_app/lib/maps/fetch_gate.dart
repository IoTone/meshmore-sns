// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:collection';

/// R81 — bounds the tile requests a panning map can pile up.
///
/// `vector_map_tiles` asks for every tile in view and cannot cancel a
/// provider call once made (VectorTileProvider.provide has no cancel
/// hook; its own cancellation only skips the *parse*). A fast pan across
/// five zoom levels therefore leaves dozens of requests for tiles that are
/// already off screen. This gate does two things about that:
///
///  * **At most [maxConcurrent] run at once.** 4 is the researched mobile
///    default (4-6 per host); the old behaviour was whatever the library
///    felt like, up to dozens in parallel on one HTTP client.
///  * **Newest first, and the queue is bounded.** A request that has
///    waited behind [maxQueued] newer ones is the one the user scrolled
///    away from, so it is dropped (its future completes with
///    [TileDropped]) instead of being fetched later for nothing.
class TileFetchGate {
  TileFetchGate({this.maxConcurrent = 4, this.maxQueued = 32})
      : assert(maxConcurrent > 0),
        assert(maxQueued >= 0);

  final int maxConcurrent;
  final int maxQueued;

  int _running = 0;
  final ListQueue<_Waiter> _queue = ListQueue<_Waiter>();

  int get running => _running;
  int get queued => _queue.length;

  /// Run [task] when a slot is free. Completes with [TileDropped] if it
  /// was queued and then pushed out by newer work.
  Future<T> run<T>(Future<T> Function() task) {
    if (_running < maxConcurrent) return _start(task);
    final Completer<T> c = Completer<T>();
    _queue.addLast(_Waiter(() {
      _start(task).then(c.complete, onError: c.completeError);
    }, () => c.completeError(const TileDropped())));
    while (_queue.length > maxQueued) {
      _queue.removeFirst().drop(); // the oldest: most likely off screen
    }
    return c.future;
  }

  Future<T> _start<T>(Future<T> Function() task) {
    _running++;
    return Future<T>.sync(task).whenComplete(() {
      _running--;
      if (_queue.isNotEmpty) _queue.removeLast().start(); // newest first
    });
  }
}

/// A queued tile request that was superseded before it started.
class TileDropped implements Exception {
  const TileDropped();
  @override
  String toString() => 'TileDropped';
}

class _Waiter {
  _Waiter(this.start, this.drop);
  final void Function() start;
  final void Function() drop;
}
