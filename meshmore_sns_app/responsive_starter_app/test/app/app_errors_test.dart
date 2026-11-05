// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/app/app_errors.dart';

void main() {
  setUp(AppErrors.clear);

  test('the last error is kept, and the buffer is bounded', () {
    for (int i = 0; i < AppErrors.capacity + 5; i++) {
      AppErrors.record(StateError('failure $i'), null);
    }
    expect(AppErrors.records, hasLength(AppErrors.capacity));
    expect(AppErrors.records.last.message, contains('failure ${AppErrors.capacity + 4}'));
    expect(AppErrors.records.first.message, contains('failure 5'));
  });

  test('a record keeps one line, because a screen cannot hold a trace', () {
    AppErrors.record(
      StateError('table full\n#0 frame\n#1 frame'),
      StackTrace.current,
      where: 'framework',
    );
    final AppErrorRecord record = AppErrors.records.single;
    expect(record.message, 'Bad state: table full');
    expect(record.where, 'framework');
    expect(record.at, isA<DateTime>());
  });

  test('install wires the three sinks and replaces the grey box', () {
    final FlutterExceptionHandler? before = FlutterError.onError;
    final ErrorWidgetBuilder beforeBuilder = ErrorWidget.builder;
    addTearDown(() {
      FlutterError.onError = before;
      ErrorWidget.builder = beforeBuilder;
    });

    AppErrors.install();
    expect(FlutterError.onError, isNotNull);
    expect(ErrorWidget.builder, isNot(same(beforeBuilder)));
    expect(ErrorWidget.builder(FlutterErrorDetails(exception: StateError('x'))),
        isA<FailedView>());
  });

  testWidgets('a failed build says what happened and what to do',
      (WidgetTester tester) async {
    await tester.pumpWidget(const FailedView(message: 'Bad state: table full'));
    expect(find.text('This part of the app could not be drawn.'), findsOneWidget);
    expect(find.text('Go back and open it again. Diagnostics keeps the record.'),
        findsOneWidget);
    expect(find.text('Bad state: table full'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
