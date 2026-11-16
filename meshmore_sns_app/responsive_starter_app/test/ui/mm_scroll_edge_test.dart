// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/ui/mm_scroll_edge.dart';

/// A body tall enough to hold a list longer than the screen.
const Size _phone = Size(400, 700);

Widget _frame(Widget body) {
  return MaterialApp(
    home: Scaffold(body: body),
  );
}

Finder _line() => find.byKey(const ValueKey<String>('mm-scroll-edge'));
Finder _closing() =>
    find.byKey(const ValueKey<String>('mm-scroll-edge-closing'));

/// The fill's share of the width, read from the widget the line draws.
double _fill(WidgetTester t) {
  final FractionallySizedBox fill = t.widget<FractionallySizedBox>(
    find.descendant(of: _line(), matching: find.byType(FractionallySizedBox)),
  );
  return fill.widthFactor!;
}

void main() {
  setUp(() {
    // A deterministic phone, so "more than fits" is a fact and not a guess.
    // 40 dp rows and 700 dp of screen: 40 rows is 1600 dp, which does not fit.
  });

  testWidgets('a long list gets the line, and nothing when it fits',
      (WidgetTester t) async {
    t.view.physicalSize = _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    await t.pumpWidget(_frame(
      MmScrollEdge(
        child: ListView(
          children: <Widget>[
            for (int i = 0; i < 40; i++) const SizedBox(height: 40),
          ],
        ),
      ),
    ));
    // The scrollable's metrics arrive in a microtask, so one more frame lands
    // the line. A page that fits draws nothing at all.
    await t.pump();
    expect(_line(), findsOneWidget);
    expect(_closing(), findsNothing);
    // At the top: the track is there, the fill is the minimum sliver that says
    // "this is a position, not a divider".
    expect(_fill(t), closeTo(.02, .001));
  });

  testWidgets('a list that fits gets no line, because there is nothing to say',
      (WidgetTester t) async {
    t.view.physicalSize = _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    await t.pumpWidget(_frame(
      MmScrollEdge(
        child: ListView(
          children: const <Widget>[
            SizedBox(height: 40),
            SizedBox(height: 40),
          ],
        ),
      ),
    ));
    await t.pump();
    expect(_line(), findsNothing);
    expect(_closing(), findsNothing);
  });

  testWidgets('a body with no scrollable gets the closing rule',
      (WidgetTester t) async {
    t.view.physicalSize = _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    await t.pumpWidget(_frame(
      const MmScrollEdge(
        child: Center(child: Text('a page that ends')),
      ),
    ));
    // The closing rule is decided after two frames: the first post-frame
    // callback cannot know whether a scrollable's metrics are still on the way.
    await t.pump();
    await t.pump();
    expect(_closing(), findsOneWidget);
    expect(_line(), findsNothing);
  });

  testWidgets('closing false leaves a docked control its own edge',
      (WidgetTester t) async {
    t.view.physicalSize = _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    await t.pumpWidget(_frame(
      const MmScrollEdge(
        closing: false,
        child: Center(child: Text('a composer sits here')),
      ),
    ));
    await t.pump();
    await t.pump();
    expect(_closing(), findsNothing);
    expect(_line(), findsNothing);
  });

  testWidgets('the fill follows the reader down the list', (WidgetTester t) async {
    t.view.physicalSize = _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    await t.pumpWidget(_frame(
      MmScrollEdge(
        child: ListView(
          children: <Widget>[
            for (int i = 0; i < 40; i++) const SizedBox(height: 40),
          ],
        ),
      ),
    ));
    await t.pump();
    final double atTop = _fill(t);
    await t.drag(find.byType(ListView), const Offset(0, -400));
    await t.pump();
    final double moved = _fill(t);
    expect(moved, greaterThan(atTop));
    expect(moved, lessThan(1));
  });

  testWidgets('progress false draws one neutral hairline that never moves',
      (WidgetTester t) async {
    t.view.physicalSize = _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    // A thread appends at the bottom: a position bar there reports the opposite
    // of what the view does, so the edge is a plain rule at a fixed length.
    await t.pumpWidget(_frame(
      MmScrollEdge(
        progress: false,
        child: ListView(
          children: <Widget>[
            for (int i = 0; i < 40; i++) const SizedBox(height: 40),
          ],
        ),
      ),
    ));
    await t.pump();
    final Finder neutral =
        find.byKey(const ValueKey<String>('mm-scroll-edge-neutral'));
    expect(neutral, findsOneWidget);
    expect(_line(), findsNothing);
    final double before = t.getRect(neutral).width;
    await t.drag(find.byType(ListView), const Offset(0, -400));
    await t.pump();
    expect(t.getRect(neutral).width, before,
        reason: 'the neutral edge must not respond to the scroll');
  });

  testWidgets('a scrollable above the edge does not drive the line',
      (WidgetTester t) async {
    t.view.physicalSize = _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    // The page view is the shell's horizontal pager: it is an ancestor, so its
    // notifications are remote and must not turn a still page into a scrolling
    // one. The page inside holds no scrollable, so the closing rule is the
    // honest answer.
    await t.pumpWidget(_frame(
      PageView(
        children: const <Widget>[
          MmScrollEdge(child: Center(child: Text('page'))),
        ],
      ),
    ));
    await t.pump();
    await t.pump();
    expect(_closing(), findsOneWidget);
    expect(_line(), findsNothing);
  });

  testWidgets('the line takes no pointer, so the last row is still tappable',
      (WidgetTester t) async {
    t.view.physicalSize = _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    int taps = 0;
    await t.pumpWidget(_frame(
      MmScrollEdge(
        child: Column(
          children: <Widget>[
            const Expanded(child: SizedBox()),
            GestureDetector(
              // A SizedBox paints nothing, so deferToChild would never hit it.
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox(height: 40, width: double.infinity),
            ),
          ],
        ),
      ),
    ));
    await t.pump();
    await t.pump();
    final IgnorePointer guard = t.widget<IgnorePointer>(
      find.ancestor(of: _closing(), matching: find.byType(IgnorePointer)).first,
    );
    expect(guard.ignoring, isTrue);
    // The bottom row's own area still receives the tap through the rule.
    final Rect row = t.getRect(find.byType(GestureDetector));
    await t.tapAt(row.center);
    expect(taps, 1);
  });
}
