// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/discovered_node.dart';
import 'package:meshmore_sns_app/screens/tools/tool_pickers.dart';

/// The tool pickers list every synced contact, which on a full radio is a
/// couple of hundred rows. The filter is the difference between finding a node
/// and dragging for a while, so its rule is pinned here.
void main() {
  DiscoveredNode node(String name, String key) => DiscoveredNode(
        pubKeyHex: key,
        name: name,
        type: 1,
        lastHeardUnix: 0,
        viaAdvert: true,
      );

  final List<DiscoveredNode> nodes = <DiscoveredNode>[
    node('HELTEC-BASE', '615f43aa11'),
    node('K0EHR T-Deck', 'eacc4412bb'),
    node('WIOld', '26f6071fcc'),
  ];

  sheetTests();

  group('the contact filter', () {
    test('an empty query keeps every row', () {
      expect(filterContacts(nodes, ''), nodes);
      expect(filterContacts(nodes, '   '), nodes);
    });

    test('a name matches anywhere in it, ignoring case', () {
      expect(filterContacts(nodes, 't-deck').single.name, 'K0EHR T-Deck');
      expect(filterContacts(nodes, 'heltec').single.name, 'HELTEC-BASE');
    });

    test('a key matches from its start only, because that is what a user reads',
        () {
      expect(filterContacts(nodes, '26f6').single.name, 'WIOld');
      expect(filterContacts(nodes, '6071'), isEmpty,
          reason: 'a prefix read off another screen is at the start');
    });

    test('a query matching nothing is an empty list, not every row', () {
      expect(filterContacts(nodes, 'zzzz'), isEmpty);
    });
  });
}

void sheetTests() {
  testWidgets('the last row is reachable at the narrow floor', (
      WidgetTester t) async {
    t.view.physicalSize = const Size(320, 780);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    // Sixty rows is past one screen at any width, so the list has to scroll
    // inside the sheet's own height rather than overflow it.
    final List<DiscoveredNode> many = <DiscoveredNode>[
      for (int i = 0; i < 60; i++)
        DiscoveredNode(
          pubKeyHex: i.toRadixString(16).padLeft(12, '0'),
          name: 'node-$i',
          type: 1,
          lastHeardUnix: 0,
          viaAdvert: true,
        ),
    ];
    DiscoveredNode? picked;
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
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
                      nodes: many,
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
    await t.scrollUntilVisible(find.text('node-59'), 200,
        scrollable: find.byType(Scrollable).last);
    // Centre it before tapping: scrollUntilVisible only guarantees the row is
    // somewhere in the viewport, and a row clipped by the sheet's bottom edge
    // is exactly the case that used to swallow taps.
    await t.ensureVisible(find.text('node-59'));
    await t.pumpAndSettle();
    await t.tap(find.text('node-59'));
    await t.pumpAndSettle();
    expect(picked?.name, 'node-59');
  });
}
