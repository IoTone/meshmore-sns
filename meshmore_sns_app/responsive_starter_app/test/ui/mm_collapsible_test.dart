// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/ui/mm_collapsible.dart';

Widget _host({bool open = true, ValueChanged<bool>? onChanged}) => MaterialApp(
      home: Scaffold(
        body: MmCollapsibleSection(
          id: 'g',
          title: 'Group',
          initiallyExpanded: open,
          onChanged: onChanged,
          children: const <Widget>[Text('inside')],
        ),
      ),
    );

void main() {
  testWidgets('open: content is built; tapping the header closes it',
      (WidgetTester tester) async {
    final List<bool> seen = <bool>[];
    await tester.pumpWidget(_host(onChanged: seen.add));
    expect(find.text('inside'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    await tester.tap(find.text('Group'.toUpperCase()));
    await tester.pump();
    expect(find.text('inside'), findsNothing,
        reason: 'closed content must not be composed');
    expect(find.byIcon(Icons.chevron_right), findsOneWidget,
        reason: 'the chevron SHAPE carries the state');
    expect(seen, <bool>[false]);

    await tester.tap(find.text('GROUP'));
    await tester.pump();
    expect(find.text('inside'), findsOneWidget);
    expect(seen, <bool>[false, true]);
  });

  testWidgets('initially closed starts closed', (WidgetTester tester) async {
    await tester.pumpWidget(_host(open: false));
    expect(find.text('inside'), findsNothing);
  });

  testWidgets('header is one 48dp-high button that reports expanded',
      (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(_host());
    expect(tester.getSize(find.byType(InkWell)).height,
        greaterThanOrEqualTo(kMinInteractiveDimension));
    SemanticsNode n() => tester.getSemantics(find.text('GROUP'));
    expect(n().label, 'Group');
    // ignore: deprecated_member_use
    expect(n().hasFlag(SemanticsFlag.isButton), isTrue);
    // ignore: deprecated_member_use
    expect(n().hasFlag(SemanticsFlag.isExpanded), isTrue);
    await tester.tap(find.text('GROUP'));
    await tester.pump();
    // ignore: deprecated_member_use
    expect(n().hasFlag(SemanticsFlag.isExpanded), isFalse);
    // ignore: deprecated_member_use
    expect(n().hasFlag(SemanticsFlag.hasExpandedState), isTrue);
    h.dispose();
  });
}
