// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/ui/mm_scaffold.dart';

/// The app draws edge to edge (Android 15 and later enforce it, and this app
/// targets 36), so the device's navigation area sits on top of whatever reaches
/// the bottom of the screen. Nothing in `lib/` read that inset before these
/// tests: every `MediaQueryData` in the suite set only `textScaler`, so a
/// control sliding under the gesture handle was invisible to the whole run.
///
/// One shared wrapper owns it now, and these three cases are the reason it can
/// be trusted: the body clears the inset, a nested `SafeArea` does not clear it
/// twice, and the bottom edge line marks the top of the area rather than the
/// glass.
void main() {
  const double kBottom = 48;
  const double kHeight = 800;
  const double kWidth = 400;

  /// A phone with a three-button bar's inset, which is the taller of the two
  /// cases and therefore the one a literal fails first.
  Widget host(Widget child, {double bottom = kBottom}) {
    return MaterialApp(
      home: Builder(builder: (BuildContext c) {
        final MediaQueryData m = MediaQuery.of(c);
        return MediaQuery(
          data: m.copyWith(padding: m.padding.copyWith(bottom: bottom)),
          child: Scaffold(body: child),
        );
      }),
    );
  }

  setUp(() {
    // Nothing global: each test sets the view, because the assertion is about
    // absolute geometry.
  });

  testWidgets('the body ends at the top of the navigation area',
      (WidgetTester t) async {
    t.view.physicalSize = const Size(kWidth, kHeight);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    const Key probe = ValueKey<String>('probe');
    await t.pumpWidget(host(
      const MmScaffold(child: SizedBox.expand(key: probe)),
    ));
    await t.pump();

    final Rect body = t.getRect(find.byKey(probe));
    expect(body.bottom, kHeight - kBottom,
        reason: 'the last row of the body was under the bar');
    // It still fills the width, and it still starts at the top: only the
    // bottom is inset.
    expect(body.left, 0);
    expect(body.right, kWidth);
    expect(body.top, 0);
  });

  testWidgets('a nested SafeArea does not clear the inset a second time',
      (WidgetTester t) async {
    t.view.physicalSize = const Size(kWidth, kHeight);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    const Key probe = ValueKey<String>('probe');
    // The composer screens already wrap themselves in `SafeArea(top: false)`.
    // If the wrapper inset the body and left the padding in the MediaQuery,
    // every one of them would gain another 48 dp of dead space.
    await t.pumpWidget(host(
      const MmScaffold(
        child: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              Spacer(),
              SizedBox(key: probe, height: 40, width: 40),
            ],
          ),
        ),
      ),
    ));
    await t.pump();

    expect(t.getRect(find.byKey(probe)).bottom, kHeight - kBottom,
        reason: 'the inset was counted twice');
  });

  testWidgets('the bottom edge line marks the top of the navigation area',
      (WidgetTester t) async {
    t.view.physicalSize = const Size(kWidth, kHeight);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    // A body with no scrollable, which is the state that draws the closing
    // rule. The rule is the page's last line, so it has to sit where the page
    // ends — above the bar, never on the glass.
    await t.pumpWidget(host(
      const MmScaffold(
        child: Column(
          children: <Widget>[
            Spacer(),
            SizedBox(height: 40, width: double.infinity),
          ],
        ),
      ),
    ));
    await t.pump();
    await t.pump();

    final Rect rule =
        t.getRect(find.byKey(const ValueKey<String>('mm-scroll-edge-closing')));
    expect(rule.bottom, kHeight - kBottom);
    expect(rule.width, kWidth, reason: 'the rule spans the body, not a column');
  });

  testWidgets('a screen can opt its own bottom edge out', (WidgetTester t) async {
    t.view.physicalSize = const Size(kWidth, kHeight);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    // A canvas draws to its own edge; a rule over it would be a rule over the
    // thing the reader came to use.
    await t.pumpWidget(host(
      const MmScaffold(
        bottomEdge: false,
        child: Column(
          children: <Widget>[
            Spacer(),
            SizedBox(height: 40, width: double.infinity),
          ],
        ),
      ),
    ));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey<String>('mm-scroll-edge-closing')),
        findsNothing);
  });

  testWidgets('with no inset the body is not moved', (WidgetTester t) async {
    t.view.physicalSize = const Size(kWidth, kHeight);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    const Key probe = ValueKey<String>('probe');
    await t.pumpWidget(host(
      const MmScaffold(child: SizedBox.expand(key: probe)),
      bottom: 0,
    ));
    await t.pump();
    expect(t.getRect(find.byKey(probe)).bottom, kHeight,
        reason: 'a phone with no navigation area must not gain dead space');
  });
}
