// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT

/// One received frame, every tracker, and a throw from one is not allowed to
/// cost the rest.
///
/// A tracker is a function of the frame plus the app's stores, and none of them
/// is sandboxed. Before this, a throw in any one of them aborted the rest for
/// that frame — a message could be recorded but never heat-mapped, a delivery
/// state could be left half-updated — and the only trace was an uncaught async
/// error. Nothing said the frame had arrived in part.
///
/// Order is preserved, and a failure is reported rather than swallowed, so the
/// surface that reads the count can say a frame was partial.
///
/// Returns the number of trackers that threw for [frame].
int runFrameTrackers<T extends Object>(
  List<void Function(T)> trackers,
  T frame, {
  required void Function(Object error, StackTrace stack) onFailure,
}) {
  int failures = 0;
  for (final void Function(T) tracker in trackers) {
    try {
      tracker(frame);
    } catch (error, stack) {
      failures++;
      onFailure(error, stack);
    }
  }
  return failures;
}
