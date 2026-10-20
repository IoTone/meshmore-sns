// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/ui/mm_edge_swipe.dart';

/// R70 — one gesture is exactly one `onSwipe`, with the right sign.
Future<List<int>> _pump(WidgetTester t,
    {EdgeInsets sys = EdgeInsets.zero}) async {
  await t.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final List<int> calls = <int>[];
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (BuildContext c) => MediaQuery(
        data: MediaQuery.of(c).copyWith(systemGestureInsets: sys),
        child: Scaffold(
          body: MmEdgeSwipe(onSwipe: calls.add, child: const SizedBox()),
        ),
      ),
    ),
  ));
  return calls;
}

void main() {
  testWidgets('left band, inward drag: exactly one -1', (WidgetTester t) async {
    final List<int> calls = await _pump(t);
    await t.fling(find.byKey(const ValueKey<String>('mm-edge-left')),
        const Offset(300, 0), 1200);
    await t.pumpAndSettle();
    expect(calls, <int>[-1]);
  });

  testWidgets('right band, inward drag: exactly one +1',
      (WidgetTester t) async {
    final List<int> calls = await _pump(t);
    await t.fling(find.byKey(const ValueKey<String>('mm-edge-right')),
        const Offset(-300, 0), 1200);
    await t.pumpAndSettle();
    expect(calls, <int>[1]);
  });

  testWidgets('a drag across the whole screen is still one call',
      (WidgetTester t) async {
    final List<int> calls = await _pump(t);
    final TestGesture g = await t.startGesture(const Offset(10, 400));
    for (int i = 0; i < 40; i++) {
      await g.moveBy(const Offset(9, 0));
      await t.pump(const Duration(milliseconds: 8));
    }
    await g.up();
    await t.pumpAndSettle();
    expect(calls, <int>[-1]);
  });

  testWidgets('two separate gestures are two calls', (WidgetTester t) async {
    final List<int> calls = await _pump(t);
    await t.fling(find.byKey(const ValueKey<String>('mm-edge-left')),
        const Offset(300, 0), 1200);
    await t.pumpAndSettle();
    await t.fling(find.byKey(const ValueKey<String>('mm-edge-right')),
        const Offset(-300, 0), 1200);
    await t.pumpAndSettle();
    expect(calls, <int>[-1, 1]);
  });

  testWidgets('bands sit just inside the system gesture zone',
      (WidgetTester t) async {
    await _pump(t, sys: const EdgeInsets.symmetric(horizontal: 30));
    final Rect l =
        t.getRect(find.byKey(const ValueKey<String>('mm-edge-left')));
    final Rect r =
        t.getRect(find.byKey(const ValueKey<String>('mm-edge-right')));
    expect(l.left, 30, reason: 'the OS owns x < 30 (system Back)');
    expect(r.right, 400 - 30);
  });

  testWidgets('with no system gesture zone the bands are flush',
      (WidgetTester t) async {
    await _pump(t);
    expect(
        t.getRect(find.byKey(const ValueKey<String>('mm-edge-left'))).left, 0);
  });
}
