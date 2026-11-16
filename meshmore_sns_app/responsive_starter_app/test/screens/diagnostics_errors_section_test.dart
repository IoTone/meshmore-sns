// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/app/app_errors.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/ui/app_errors_list.dart';

/// The app collected the last twenty throws and displayed them nowhere, so a
/// periodic freeze left no readable account. This is the surface that reads them.
///
/// The widget is reached through the diagnostics screen's developer section,
/// which needs a controller and a router, so the list is tested where it lives:
/// the section's own rows are asserted through the real screen in
/// `diagnostics_screen_test.dart`; here the rendering rules are pinned.
void main() {
  testWidgets('rows read newest first, with the age as a number',
      (WidgetTester t) async {
    await t.pumpWidget(_host());
    expect(find.textContaining('framework'), findsOneWidget);
    expect(find.textContaining('async'), findsOneWidget);
    // Newest first: "second" was recorded later and must be above "first".
    final Offset first = t.getTopLeft(find.textContaining('Bad state: first'));
    final Offset second = t.getTopLeft(find.textContaining('Bad state: second'));
    expect(second.dy, lessThan(first.dy),
        reason: 'the question a support report asks is what happened last');
  });

  testWidgets('a row says how long ago, not what the clock said',
      (WidgetTester t) async {
    // "3m ago" answers "how often does this happen"; a timestamp makes the
    // reader subtract.
    await t.pumpWidget(_host(
      at: DateTime.now().subtract(const Duration(minutes: 3)),
    ));
    expect(find.textContaining('3m ago'), findsOneWidget);
  });

  testWidgets('the list survives a long message without overflowing',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_host(
      message: 'the whole basemap layer failed to parse and the map stayed '
          'empty for the rest of the session, which is what the operator saw '
          'and could not explain',
    ));
    expect(t.takeException(), isNull);
  });
}

Widget _host({
  DateTime? at,
  String message = 'Bad state: first',
}) {
  final DateTime when = at ?? DateTime.now().subtract(const Duration(minutes: 1));
  // The section renders the app's own records, so the list is fed directly with
  // the records it would hold. Reaching into AppErrors would make this test
  // depend on the sink's global state and on writes to a mock store.
  // No ThemeController above it, which is the isolated-widget case `context.skin`
  // documents: the fallback skin renders the rows without a provider tree.
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const <Locale>[Locale('en')],
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: ListView(
        children: <Widget>[
          AppErrorsList(
            previous: false,
            errors: <AppErrorRecord>[
              AppErrorRecord('framework', message, when),
              AppErrorRecord('async', 'Bad state: second',
                  when.add(const Duration(seconds: 1))),
            ],
          ),
        ],
      ),
    ),
  );
}
