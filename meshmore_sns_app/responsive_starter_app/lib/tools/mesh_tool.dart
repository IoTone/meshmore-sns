// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:meshcore/meshcore.dart';

import '../meshcore/meshcore_controller.dart';

/// R60 — the Tools under Settings. See `meshmore-sns-tools-spec.md`.
enum ToolKind { stats, ping, trace, discover, soak, range }

/// Why a tool could not do what was asked. The screens turn each into
/// a sentence; none of them is a generic "failed".
enum ToolFailure {
  /// No radio link.
  notConnected,

  /// Another tool holds the radio (rule 3: one at a time).
  busy,

  /// The firmware does not know the command (ERR_CODE_UNSUPPORTED_CMD).
  unsupported,

  /// The radio does not have the contact (ERR_CODE_NOT_FOUND).
  notFound,

  /// The radio's packet table is full (ERR_CODE_TABLE_FULL).
  tableFull,

  /// The radio refused the arguments (ERR_CODE_ILLEGAL_ARG / other).
  rejected,

  /// The radio never confirmed the send.
  noConfirm,

  /// The scope is Public — tools that send text refuse it (rule 2).
  publicScope,

  /// The channel's key has not been read from the radio yet, so we
  /// cannot tell whether it is Public.
  unknownChannel,

  /// Nothing to send along: no route to trace, no target chosen.
  noTarget,
}

class ToolException implements Exception {
  const ToolException(this.failure);
  final ToolFailure failure;
  @override
  String toString() => 'ToolException($failure)';
}

ToolFailure failureForErrCode(int? code) => switch (code) {
      kErrUnsupportedCmd => ToolFailure.unsupported,
      kErrNotFound => ToolFailure.notFound,
      kErrTableFull => ToolFailure.tableFull,
      _ => ToolFailure.rejected,
    };

/// Rule 4: wait the radio's own estimate ×1.5, clamped to 5–60 s.
Duration replyTimeoutFor(int estTimeoutMs) =>
    Duration(milliseconds: (estTimeoutMs * 1.5).round().clamp(5000, 60000));

final Random _tagRng = Random.secure();

/// A random non-zero 32-bit tag for trace / discover matching.
int randomTag() => _tagRng.nextInt(0xFFFFFFFE) + 1;

// Subscription cancels below are deliberately not awaited: nothing
// depends on their completion, and awaiting a root-zone cancel future
// wedges `pump` under the fake clock the tests run on.

/// Base for every tool: a ChangeNotifier owned by `ToolsController`
/// so a run survives leaving its screen (a soak runs for an hour).
abstract class MeshTool extends ChangeNotifier {
  MeshTool(this.mc, {DateTime Function()? now}) : now = now ?? DateTime.now;

  final MeshcoreController mc;

  /// Injectable clock — tests advance it alongside fake timers.
  final DateTime Function() now;

  /// Set by `ToolsController`; asks it for the radio.
  bool Function(MeshTool tool)? acquire;
  void Function(MeshTool tool)? release;

  bool _running = false;
  bool get running => _running;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// A run can outlive its owner by one step; never notify after.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  ToolFailure? _failure;

  /// The last run's failure, if it ended on one.
  ToolFailure? get failure => _failure;

  bool _stopRequested = false;
  bool get stopRequested => _stopRequested;
  Completer<void>? _wake;

  /// Start a run. Returns false (with [failure] set) when it cannot.
  @protected
  bool begin({bool exclusive = true}) {
    if (_running) return false;
    if (!mc.isReady) {
      _failure = ToolFailure.notConnected;
      notifyListeners();
      return false;
    }
    if (exclusive && acquire != null && !acquire!(this)) {
      _failure = ToolFailure.busy;
      notifyListeners();
      return false;
    }
    _exclusive = exclusive;
    _running = true;
    _stopRequested = false;
    _failure = null;
    notifyListeners();
    return true;
  }

  bool _exclusive = true;

  @protected
  void finish([ToolFailure? failure]) {
    if (!_running) return;
    _running = false;
    _failure = failure;
    if (_exclusive) release?.call(this);
    notifyListeners();
  }

  /// Ask the run to stop at its next step; wakes any wait.
  void stop() {
    if (!_running) return;
    _stopRequested = true;
    _wake?.complete();
    _wake = null;
    notifyListeners();
  }

  /// Sleep that [stop] cuts short.
  @protected
  Future<void> pause(Duration d) {
    final Completer<void> c = Completer<void>();
    _wake = c;
    final Timer t = Timer(d, () {
      if (!c.isCompleted) c.complete();
    });
    return c.future.whenComplete(() {
      t.cancel();
      if (identical(_wake, c)) _wake = null;
    });
  }

  /// Send a request the radio answers with RESP_CODE_SENT; resolves
  /// with that confirmation. Throws [ToolException] on ERR or silence.
  @protected
  Future<MsgSent> sendAwaitingSent(Uint8List frame,
      {Duration confirm = const Duration(seconds: 5)}) async {
    final Completer<MeshcoreInbound> got = Completer<MeshcoreInbound>();
    final StreamSubscription<MeshcoreInbound> sub =
        mc.inboundFrames.listen((MeshcoreInbound f) {
      if (got.isCompleted) return;
      if (f is MsgSentFrame || f is ErrorFrame) got.complete(f);
    });
    try {
      try {
        await mc.sendToolRequest(frame);
      } catch (_) {
        throw const ToolException(ToolFailure.noConfirm);
      }
      final MeshcoreInbound f = await got.future
          .timeout(confirm, onTimeout: () => const OkFrame(null));
      if (f is MsgSentFrame) return f.sent;
      mc.abandonToolRequest();
      if (f is ErrorFrame) throw ToolException(failureForErrCode(f.code));
      throw const ToolException(ToolFailure.noConfirm);
    } finally {
      unawaited(sub.cancel());
    }
  }

  /// Send a local command answered by OK/ERR (or by [accept]).
  @protected
  Future<MeshcoreInbound> sendAwaitingReply(
    Uint8List frame, {
    bool Function(MeshcoreInbound f)? accept,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final Completer<MeshcoreInbound> got = Completer<MeshcoreInbound>();
    final StreamSubscription<MeshcoreInbound> sub =
        mc.inboundFrames.listen((MeshcoreInbound f) {
      if (got.isCompleted) return;
      if (f is ErrorFrame || (accept ?? (g) => g is OkFrame)(f)) {
        got.complete(f);
      }
    });
    try {
      await mc.send(frame);
      final MeshcoreInbound f =
          await got.future.timeout(timeout, onTimeout: () {
        throw const ToolException(ToolFailure.noConfirm);
      });
      if (f is ErrorFrame) throw ToolException(failureForErrCode(f.code));
      return f;
    } on ToolException {
      rethrow;
    } catch (_) {
      throw const ToolException(ToolFailure.noConfirm);
    } finally {
      unawaited(sub.cancel());
    }
  }

  /// Wait up to [timeout] for the first frame [match] accepts.
  @protected
  Future<T?> awaitFrame<T extends MeshcoreInbound>(
      bool Function(T f) match, Duration timeout) async {
    final Completer<T?> got = Completer<T?>();
    final StreamSubscription<MeshcoreInbound> sub =
        mc.inboundFrames.listen((MeshcoreInbound f) {
      if (!got.isCompleted && f is T && match(f)) got.complete(f);
    });
    // stop() ends the wait early, as a miss.
    final Completer<void> wake = Completer<void>();
    _wake = wake;
    unawaited(wake.future.then((_) {
      if (!got.isCompleted) got.complete(null);
    }));
    try {
      return await got.future.timeout(timeout, onTimeout: () => null);
    } finally {
      if (identical(_wake, wake)) _wake = null;
      unawaited(sub.cancel());
    }
  }
}

String hexOf(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List bytesOfHex(String hex) => Uint8List.fromList(<int>[
      for (int i = 0; i + 1 < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
