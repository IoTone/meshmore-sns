// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/chat/report_flow.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/util/share.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = Directory.systemTemp.createTempSync('report_flow_test');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('the flow writes a report and says it was not sent',
      (WidgetTester t) async {
    final ChatMessage m = ChatMessage(
      channelIdx: 1,
      text: 'Mallory: the ford is mined',
      outgoing: false,
    );
    await t.pumpWidget(wrap(Builder(
      builder: (BuildContext ctx) => TextButton(
        onPressed: () => reportMessage(
          ctx,
          m,
          threadName: 'Local',
          senderDisplayName: 'Mallory',
          // A synchronous write: the flow's own sequencing is what this test
          // is about, and ReportBundle.write has its own test. Real file IO
          // inside a widget test races pumpAndSettle.
          write: (Map<String, Object?> bundle) async {
            final File f = File('${dir.path}/bundle.json')
              ..writeAsStringSync(jsonEncode(bundle));
            return f;
          },
        ),
        child: const Text('open'),
      ),
    )));
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    expect(find.text('Report this message'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'this looks like a trap');
    await t.tap(find.widgetWithText(TextButton, 'Report…'));
    await t.pumpAndSettle();

    expect(find.textContaining('Nothing was sent'), findsOneWidget);
    final List<FileSystemEntity> files = dir.listSync();
    expect(files.length, 1, reason: 'exactly one bundle, no side files');
    final String raw = (files.single as File).readAsStringSync();
    final Map<String, dynamic> bundle = jsonDecode(raw) as Map<String, dynamic>;
    expect(bundle['format'], 'meshmore.report');
    expect(bundle['observation'], 'this looks like a trap');
    final Map<String, dynamic> message =
        bundle['message'] as Map<String, dynamic>;
    expect(message['text'], 'Mallory: the ford is mined');
    expect(message['channel'], 'Local');
    expect(message['senderName'], 'Mallory');
    expect(bundle['transmission'], contains('none'));

    // The clipboard is a platform channel; without a handler the call never
    // completes, and this also lets the test read what was put there.
    String? clipboard;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          final Map<Object?, Object?> args =
              call.arguments as Map<Object?, Object?>;
          clipboard = args['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await t.tap(find.widgetWithText(TextButton, 'Copy the report'));
    await t.pumpAndSettle();
    expect(find.text('Report copied.'), findsOneWidget);
    expect(clipboard, isNotNull);
    final Map<String, dynamic> copied =
        jsonDecode(clipboard!) as Map<String, dynamic>;
    expect(copied['format'], 'meshmore.report',
        reason: 'the clipboard carries the same bundle that was written');
    expect(find.textContaining('Nothing was sent'), findsNothing,
        reason: 'the dialog closes on copy');
  });

  testWidgets('the reader can hand the file to another app',
      (WidgetTester t) async {
    final ChatMessage m =
        ChatMessage(channelIdx: 0, text: 'Trent: follow the treeline', outgoing: false);
    await t.pumpWidget(wrap(Builder(
      builder: (BuildContext ctx) => TextButton(
        onPressed: () => reportMessage(ctx, m,
            threadName: 'Public',
            write: (Map<String, Object?> bundle) async {
              final File f = File('${dir.path}/bundle.json')
                ..writeAsStringSync(jsonEncode(bundle));
              return f;
            }),
        child: const Text('open'),
      ),
    )));
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'came from the north');
    await t.tap(find.widgetWithText(TextButton, 'Report…'));
    await t.pumpAndSettle();

    // The platform side wraps the file in a content:// URI; here it answers
    // the way Android does when a share sheet opens.
    final MethodChannel channel = Share.channel;
    final List<MethodCall> calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) async {
        calls.add(call);
        return true;
      },
    );
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await t.tap(find.widgetWithText(TextButton, 'Share the report'));
    await t.pumpAndSettle();

    expect(calls.map((MethodCall c) => c.method), <String>['shareFile']);
    final Map<Object?, Object?> args =
        calls.single.arguments as Map<Object?, Object?>;
    expect(args['path'], '${dir.path}/bundle.json',
        reason: 'the file that was written is the file handed over');
    expect(args['mime'], 'application/json');
    expect(find.text('Report copied.'), findsNothing,
        reason: 'sharing is not copying, and says so by not claiming it');
  });

  testWidgets('cancelling the observation writes nothing',
      (WidgetTester t) async {
    final ChatMessage m =
        ChatMessage(channelIdx: 0, text: 'Trudy: hi', outgoing: false);
    await t.pumpWidget(wrap(Builder(
      builder: (BuildContext ctx) => TextButton(
        onPressed: () => reportMessage(ctx, m,
            threadName: 'Public',
            write: (Map<String, Object?> bundle) async {
              final File f = File('${dir.path}/bundle.json')
                ..writeAsStringSync(jsonEncode(bundle));
              return f;
            }),
        child: const Text('open'),
      ),
    )));
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Cancel'));
    await t.pumpAndSettle();
    expect(dir.listSync(), isEmpty);
  });
}
