// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/util/frame_trackers.dart';

/// One frame runs through every tracker, and a throw from one does not cost the
/// rest.
///
/// This is the guarantee the inbound listener depends on: before it, a throw in
/// any tracker aborted every tracker after it *and* the notification at the
/// end, so the frame arrived in part with nothing saying so. The guarantee is a
/// property of the runner, so it is tested here with trackers that throw on
/// purpose — no production tracker throws today, and inventing one inside the
/// controller to make a test fail would be a test hook in shipped code.
void main() {
  test('a throw in the middle leaves the trackers around it running', () {
    final List<String> ran = <String>[];
    final List<Object> reported = <Object>[];

    final int failures = runFrameTrackers<int>(
      <void Function(int)>[
        (int f) => ran.add('first $f'),
        (int f) => throw StateError('tracker broke on $f'),
        (int f) => ran.add('third $f'),
      ],
      7,
      onFailure: (Object error, StackTrace stack) => reported.add(error),
    );

    expect(ran, <String>['first 7', 'third 7'],
        reason: 'order is kept and a failure does not stop the queue');
    expect(failures, 1);
    expect(reported.single, isA<StateError>());
  });

  test('every failing tracker is counted, not just the first', () {
    final List<Object> reported = <Object>[];
    final int failures = runFrameTrackers<int>(
      <void Function(int)>[
        (int _) => throw ArgumentError('one'),
        (int _) => throw ArgumentError('two'),
        (int _) {},
      ],
      1,
      onFailure: (Object error, StackTrace stack) => reported.add(error),
    );
    expect(failures, 2);
    expect(reported.length, 2);
  });

  test('a clean frame reports nothing and counts nothing', () {
    final List<Object> reported = <Object>[];
    int seen = 0;
    final int failures = runFrameTrackers<int>(
      <void Function(int)>[
        (int f) => seen += f,
      ],
      2,
      onFailure: (Object error, StackTrace stack) => reported.add(error),
    );
    expect(failures, 0);
    expect(seen, 2);
    expect(reported, isEmpty);
  });
}
