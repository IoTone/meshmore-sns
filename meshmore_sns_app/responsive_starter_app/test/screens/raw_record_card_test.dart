// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/mesh_sender.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/raw_record_card.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/mm_components.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/fake_transport.dart';

/// The raw-record tool: one typed record to one contact, answered by the
/// radio's own OK or ERR.
///
/// Nothing here needs a radio. Every refusal is decided before a frame exists,
/// and the two answers come from the fake transport, which is the point of
/// testing this surface rather than trusting it.
class _Host {
  _Host(this.mc, this.fake, this.sender);
  final MeshcoreController mc;
  final FakeMeshcoreTransport fake;
  final MeshcoreMeshSender sender;
}

Future<_Host> _host(
  WidgetTester t, {
  bool withRoute = true,
  bool ready = true,
  ThemeController? theme,
  double textScale = 1.0,
}) async {
  final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
  final MeshcoreController mc = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  final MeshcoreMeshSender sender =
      MeshcoreMeshSender(mc, answerTimeout: const Duration(seconds: 2));
  // A widget test runs in a fake-async zone, so the link is driven by pumps:
  // awaiting a bare Future here would wait for a timer nothing advances.
  unawaited(mc.connect());
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: MultiProvider(
          providers: <SingleChildWidget>[
            ChangeNotifierProvider<MeshcoreController>.value(value: mc),
            if (theme != null)
              ChangeNotifierProvider<ThemeController>.value(value: theme),
          ],
          child: Scaffold(
            body: SingleChildScrollView(
              child: RawRecordCard(mc: mc, sender: sender),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  if (ready) {
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();
  }
  if (withRoute && ready) {
    // 176 - 1 opcode - 1 path_len - 2 path bytes = 172 for the record, and
    // the receiver's own ceiling of 171 is the smaller of the two.
    fake.emit(contactFrame(
        name: 'peer',
        firstPubByte: 70,
        outPathLen: 2,
        path: const <int>[0xAA, 0xBB]));
    await t.pumpAndSettle();
  }
  return _Host(mc, fake, sender);
}

Future<void> _teardown(WidgetTester t, _Host h) async {
  h.mc.dispose();
  await h.sender.dispose();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 3));
}

List<Uint8List> _rawSends(FakeMeshcoreTransport fake) =>
    fake.sent.where((Uint8List f) => f.isNotEmpty && f[0] == 0x19).toList();

String _hexOf(int n) => List<int>.filled(n, 0x5A)
    .map((int b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('a contact with no route is named, not an empty list',
      (WidgetTester t) async {
    final _Host h = await _host(t, withRoute: false);
    expect(find.textContaining('No contact has a direct route yet'),
        findsOneWidget);
    expect(t.widget<MmAction>(find.byType(MmAction)).onPressed, isNull);
    await _teardown(t, h);
  });

  testWidgets('the two ceilings are stated: the frame and this route',
      (WidgetTester t) async {
    final _Host h = await _host(t);
    expect(find.textContaining('Frame ${MeshCarryLimits.maxFrameSize} bytes'),
        findsOneWidget);
    expect(find.textContaining('leaves 171 for the record'), findsOneWidget);
    await _teardown(t, h);
  });

  testWidgets('the button waits for bytes that parse', (WidgetTester t) async {
    final _Host h = await _host(t);
    expect(t.widget<MmAction>(find.byType(MmAction)).onPressed, isNull,
        reason: 'nothing typed yet');

    await t.enterText(find.byType(TextField), '01 02 zz 04');
    await t.pumpAndSettle();
    expect(find.textContaining('Not hex'), findsOneWidget);
    expect(t.widget<MmAction>(find.byType(MmAction)).onPressed, isNull);

    await t.enterText(find.byType(TextField), '01 02 03');
    await t.pumpAndSettle();
    expect(find.textContaining('At least 4 bytes'), findsOneWidget);

    await t.enterText(find.byType(TextField), '01 02 03 04');
    await t.pumpAndSettle();
    expect(t.widget<MmAction>(find.byType(MmAction)).onPressed, isNotNull);
    await _teardown(t, h);
  });

  testWidgets('a record over this route budget is refused before the radio',
      (WidgetTester t) async {
    final _Host h = await _host(t);
    await t.enterText(find.byType(TextField), _hexOf(173));
    await t.pumpAndSettle();
    expect(find.textContaining("Over this contact's 171-byte budget"),
        findsOneWidget);
    expect(t.widget<MmAction>(find.byType(MmAction)).onPressed, isNull);
    expect(_rawSends(h.fake), isEmpty);
    await _teardown(t, h);
  });

  testWidgets('every send asks first, and says what it cannot check',
      (WidgetTester t) async {
    final _Host h = await _host(t);
    await t.enterText(find.byType(TextField), 'aa bb cc dd');
    await t.pumpAndSettle();
    await t.tap(find.byType(MmAction));
    await t.pumpAndSettle();

    expect(find.text('Send these bytes?'), findsOneWidget);
    expect(find.textContaining('The app cannot check what these bytes do'),
        findsOneWidget);
    await t.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Cancel')));
    await t.pumpAndSettle();
    expect(_rawSends(h.fake), isEmpty);
    await _teardown(t, h);
  });

  testWidgets('confirming writes 0x19 with the path and the record',
      (WidgetTester t) async {
    final _Host h = await _host(t);
    await t.enterText(find.byType(TextField), 'aa bb cc dd');
    await t.pumpAndSettle();
    await t.tap(find.byType(MmAction));
    await t.pumpAndSettle();
    await t.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Send')));
    await t.pumpAndSettle();

    final List<Uint8List> writes = _rawSends(h.fake);
    expect(writes, hasLength(1));
    expect(writes.single, <int>[0x19, 2, 0xAA, 0xBB, 0xAA, 0xBB, 0xCC, 0xDD]);

    h.fake.emit(Uint8List.fromList(<int>[0x00])); // RESP_CODE_OK
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('raw-record-outcome')),
        findsOneWidget);
    expect(find.textContaining('The MeshCore radio accepted it'), findsOneWidget);
    expect(find.textContaining('not delivery'), findsOneWidget,
        reason: 'a raw record carries no receipt from the peer');
    await _teardown(t, h);
  });

  testWidgets('a radio refusal states the code and what it means',
      (WidgetTester t) async {
    final _Host h = await _host(t);
    await t.enterText(find.byType(TextField), 'aa bb cc dd');
    await t.pumpAndSettle();
    await t.tap(find.byType(MmAction));
    await t.pumpAndSettle();
    await t.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Send')));
    await t.pumpAndSettle();

    h.fake.emit(errorFrame(3)); // ERR_CODE_TABLE_FULL
    await t.pumpAndSettle();
    expect(find.textContaining('(code 3)'), findsOneWidget);
    // The meaning comes from the failure catalogue, not a literal here.
    expect(find.textContaining('queue or table is full'), findsOneWidget);
    expect(find.textContaining('Nothing was lost'), findsOneWidget,
        reason: 'capacity, not a lost record');
    await _teardown(t, h);
  });

  testWidgets('with no link the card says so and offers no send',
      (WidgetTester t) async {
    // The fourth answer state. It has to be a sentence, not a dead button
    // that says nothing about why it is dead.
    final _Host h = await _host(t, ready: false);
    expect(find.text('No MeshCore radio connected.'), findsOneWidget);
    expect(find.byType(MmAction), findsNothing);
    await _teardown(t, h);
  });

  testWidgets('no answer says the bytes may have gone anyway',
      (WidgetTester t) async {
    final _Host h = await _host(t);
    await t.enterText(find.byType(TextField), 'aa bb cc dd');
    await t.pumpAndSettle();
    await t.tap(find.byType(MmAction));
    await t.pumpAndSettle();
    await t.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Send')));
    await t.pumpAndSettle();

    // The sender's deadline is two seconds in this harness; nothing answers.
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(find.textContaining('No answer in 2 s'), findsOneWidget);
    expect(find.textContaining('may have sent it anyway'), findsOneWidget,
        reason: 'silence is not failure: the frame was written');
    await _teardown(t, h);
  });

  testWidgets('the card survives 320 dp at 200 % text in every skin',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final ThemeController theme = ThemeController();
    for (final MmThemePreset preset in MmThemePreset.values) {
      await theme.setPreset(preset);
      final _Host h = await _host(t, theme: theme, textScale: 2.0);
      expect(t.takeException(), isNull, reason: 'preset ${preset.name}');
      expect(find.byType(MmAction), findsOneWidget,
          reason: 'preset ${preset.name}');
      expect(find.textContaining('(hex)'), findsOneWidget,
          reason: 'the byte field survives the floor at ${preset.name}');
      await _teardown(t, h);
    }
  });
}
