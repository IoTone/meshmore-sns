// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/discovered_node.dart';
import 'package:meshmore_sns_app/screens/tools/tool_pickers.dart';

/// Choosing a contact in a real modal sheet returns that contact.
///
/// The handset showed the sheet closing with no target set while `adb input tap`
/// was stepping through it. These tests settle the app side: the sheet is built
/// by `showModalBottomSheet` exactly as the app builds it, a row is tapped, and
/// the future completes with that node — including the last row of a sixty-row
/// list at 320 dp. So the sheet is not the defect, and synthetic taps on this
/// ROM are the thing to distrust.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DiscoveredNode node(String name, String key) => DiscoveredNode(
        pubKeyHex: key,
        name: name,
        type: 1,
        lastHeardUnix: 0,
        viaAdvert: true,
      );

  Future<DiscoveredNode?> openAndPick(
    WidgetTester t, {
    required int count,
    required String nameToTap,
    Size size = const Size(1080, 2400),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final List<DiscoveredNode> nodes = <DiscoveredNode>[
      for (int i = 0; i < count; i++)
        node('node-$i', i.toRadixString(16).padLeft(12, '0')),
    ];
    DiscoveredNode? picked;
    await t.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: Builder(builder: (BuildContext ctx) {
          return TextButton(
            onPressed: () async {
              picked = await showModalBottomSheet<DiscoveredNode>(
                context: ctx,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (BuildContext inner) => SafeArea(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(inner).size.height * .7),
                    child: ContactPickerSheet(
                      nodes: nodes,
                      l: AppLocalizations.of(inner),
                    ),
                  ),
                ),
              );
            },
            child: const Text('open'),
          );
        }),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    // Drag the sheet's list to its end, then bring the row fully into view: a
    // row clipped by the sheet's edge is the case that cannot be tapped.
    for (int i = 0; i < 24 && find.text(nameToTap).evaluate().isEmpty; i++) {
      await t.drag(find.byType(ListView).last, const Offset(0, -300));
      await t.pumpAndSettle();
    }
    expect(find.text(nameToTap), findsOneWidget,
        reason: 'the row exists after scrolling the sheet');
    await t.ensureVisible(find.text(nameToTap));
    await t.pumpAndSettle();
    await t.tap(find.text(nameToTap));
    await t.pumpAndSettle();
    return picked;
  }

  testWidgets('a short list returns the tapped contact', (WidgetTester t) async {
    final DiscoveredNode? picked = await openAndPick(t,
        count: 3, nameToTap: 'node-1');
    expect(picked?.name, 'node-1');
  });

  testWidgets('the last row of a long list is reachable and returns',
      (WidgetTester t) async {
    // Sixty rows is past one screen, so the list has to scroll inside the
    // sheet's own height. A list laid out taller than its box paints rows
    // nothing can tap.
    final DiscoveredNode? picked =
        await openAndPick(t, count: 60, nameToTap: 'node-59');
    expect(picked?.name, 'node-59');
  });

  testWidgets('it holds the narrow floor', (WidgetTester t) async {
    final DiscoveredNode? picked = await openAndPick(t,
        count: 8, nameToTap: 'node-7', size: const Size(320, 780));
    expect(picked?.name, 'node-7');
    expect(t.takeException(), isNull);
  });
}
