// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/ui/mm_collapse_controller.dart';
import 'package:meshmore_sns_app/ui/mm_collapsible.dart';
import 'package:provider/provider.dart';

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

  group('R66 missing provider', () {
    Future<List<String>> run(WidgetTester tester, Widget w, int taps) async {
      final List<String> logs = <String>[];
      final old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      try {
        await tester.pumpWidget(w);
        expect(logs, isEmpty, reason: 'no warning on build');
        for (int i = 0; i < taps; i++) {
          await tester.tap(find.byType(InkWell));
          await tester.pump();
        }
      } finally {
        // Restore inside the body: flutter_test checks debug vars
        // before addTearDown callbacks run.
        debugPrint = old;
      }
      return logs;
    }

    testWidgets('warns once, on toggle only, and still toggles',
        (WidgetTester tester) async {
      final List<String> logs = await run(tester, _host(), 3);
      expect(logs, hasLength(1));
      expect(logs.single, contains('"g"'));
      expect(logs.single, contains('session-only'));
      expect(find.text('inside'), findsNothing,
          reason: 'three toggles from open leave it closed');
    });

    testWidgets('no warning when a controller is provided',
        (WidgetTester tester) async {
      final MmCollapseController c =
          MmCollapseController(known: const <String>{'g'});
      final List<String> logs = await run(
          tester,
          ChangeNotifierProvider<MmCollapseController>.value(
              value: c, child: _host()),
          2);
      expect(logs, isEmpty);
    });
  });
}
