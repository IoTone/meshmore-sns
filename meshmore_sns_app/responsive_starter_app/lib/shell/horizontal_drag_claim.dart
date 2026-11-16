// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// R109 — who owns a horizontal drag.
///
/// The shell's body [PageView] changes view on a horizontal drag (issue #4).
/// A surface that already uses that drag for itself holds the claim while it
/// shows, and the shell stops paging until it lets go: the Map tab, whose
/// pan/zoom canvas owns the middle of the screen, and the hyperlocal grid
/// while its Swipe ⇄ Pan toggle is in pan mode.
///
/// Two surfaces can hold it, and they overlap for a frame while one page is
/// replaced by another, so the claim counts named holders rather than one
/// boolean two widgets would overwrite for each other.
class HorizontalDragClaim {
  HorizontalDragClaim();

  final Set<String> _holders = <String>{};

  /// True while any surface holds the claim. The shell listens.
  final ValueNotifier<bool> claimed = ValueNotifier<bool>(false);

  bool get isClaimed => claimed.value;

  /// [holder] takes horizontal drags from now on. Idempotent, so a rebuild
  /// can call it again without stacking a second claim.
  void hold(String holder) {
    if (_holders.add(holder)) _publish();
  }

  /// [holder] no longer takes them; any other holder keeps the claim.
  void release(String holder) {
    if (_holders.remove(holder)) _publish();
  }

  /// Tells the shell, but never from inside a build pass. The writers are
  /// widget lifecycle (a tab mounting, a tab being disposed), and disposing
  /// happens in `finalizeTree`; notifying there would mark the shell - an
  /// ancestor - dirty while the framework walks the tree. One deferred
  /// publish per frame is enough: the value is read from [_holders] when it
  /// runs, so the last writer wins.
  void _publish() {
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    final bool inBuildPass = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (!inBuildPass) {
      claimed.value = _holders.isNotEmpty;
      return;
    }
    if (_publishPending) return;
    _publishPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _publishPending = false;
      claimed.value = _holders.isNotEmpty;
    });
  }

  bool _publishPending = false;

  @visibleForTesting
  bool heldBy(String holder) => _holders.contains(holder);

  /// Back to "nobody holds it". Tests only: the app's holders release
  /// themselves when their widget is disposed.
  @visibleForTesting
  void reset() {
    _holders.clear();
    _publishPending = false;
    claimed.value = false;
  }
}

/// The one claim the shell reads ([HomeShell]) and the surfaces write
/// (`GridScreen`, `MapScreen`). Process-wide for the same reason
/// `GridScreen._sessionMode` is: a tab's state is disposed when another view
/// replaces it, and the claim must outlive that teardown by no more than the
/// release those widgets themselves perform.
final HorizontalDragClaim shellDragClaim = HorizontalDragClaim();
