// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/bot/bot_controller.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/diagnostics_screen.dart';
import 'package:meshmore_sns_app/tools/tools_controller.dart';
import 'package:meshmore_sns_app/ui/mm_components.dart';

import '../meshcore/fake_transport.dart';

/// The radio's own alert outputs, on the surface that ships them (D8.24).
///
/// Two commands, `get/set buzzer` and `get/set vibration`, reached through the
/// closed whitelist in `packages/meshcore`. The wire-level behaviour is covered
/// in `test/meshcore/radio_cli_test.dart`; these cases are about what a reader
/// sees, and about the one thing this surface must never grow: a text field that
/// could reach the radio's shell.
///
/// A note on the harness, because it is the whole difficulty: a bare `OK` is
/// claimed by the *oldest* command waiting for one (the wire carries no
/// correlation tag), and the controller keeps a background drain running. So the
/// fake radio goes quiet while a CLI command waits, and every case feeds the
/// verdict until the slot frees — which is what a real radio does, in order.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Uint8List cliReply(String line) =>
      Uint8List.fromList(<int>[0x1D, ...line.codeUnits]);
  Uint8List ok() => Uint8List.fromList(<int>[0x00]);
  Uint8List err(int code) => Uint8List.fromList(<int>[0x01, code]);

  Future<(MeshcoreController, _AnsweringTransport)> pump(WidgetTester t) async {
    final _AnsweringTransport fake = _AnsweringTransport();
    final MeshcoreController ctrl = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
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
        home: MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<MeshcoreController>.value(value: ctrl),
            ChangeNotifierProvider<ToolsController>(
                create: (_) => ToolsController(ctrl)),
            ChangeNotifierProvider<BotController>(
                create: (_) => BotController()),
          ],
          child: const DiagnosticsScreen(),
        ),
      ),
    );
    await ctrl.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();
    return (ctrl, fake);
  }

  /// Pumps until [done] holds, so a case never guesses how many frames an
  /// asynchronous chain needs.
  Future<void> pumpUntil(WidgetTester t, bool Function() done,
      {int frames = 40}) async {
    for (int i = 0; i < frames; i++) {
      if (done()) return;
      await t.pump();
    }
  }

  /// Every frame the app put on the wire, as text after the opcode.
  List<String> sentTexts(_AnsweringTransport fake) => <String>[
        for (final Uint8List f in fake.sent) String.fromCharCodes(f.skip(1)),
      ];

  Future<void> awaitSent(
      WidgetTester t, _AnsweringTransport fake, String text) async {
    await pumpUntil(t, () => sentTexts(fake).contains(text));
    expect(sentTexts(fake), contains(text));
  }

  /// The text one alert row is showing.
  String rowText(WidgetTester t, String id) =>
      t
          .widget<Text>(find.byKey(ValueKey<String>('radio-alert-$id-said')))
          .data ??
      '';

  /// Answer the command queue until the row under test changes.
  ///
  /// Stopping on `cliBusy` is not possible: the two reads run in series, so the
  /// slot is busy again the instant one row is answered, and another `OK` would
  /// then answer the *next* command with no text. The row itself is the signal —
  /// it is what the case is about, and it changes exactly once per answer.
  Future<void> answerCli(WidgetTester t, _AnsweringTransport fake,
      {required String id, required Uint8List verdict}) async {
    final String before = rowText(t, id);
    for (int i = 0; i < 12; i++) {
      if (rowText(t, id) != before) break;
      fake.emit(verdict);
      await t.pump();
      await t.pump();
    }
    for (int i = 0; i < 3; i++) {
      await t.pump();
    }
  }

  /// The developer blocks are folded away by default; opening the fold is also
  /// what asks the radio for both alert values.
  ///
  /// The transport goes quiet first: while a CLI command waits, nothing else may
  /// answer, or the verdict would be claimed by whatever the background drain
  /// sent before it.
  Future<void> openDeveloper(WidgetTester t, _AnsweringTransport fake) async {
    fake.quiet = true;
    await t.tap(find.text('DEVELOPER'));
    await t.pump();
    await t.pump();
  }

  /// Open the developer fold and ask for both values.
  ///
  /// The fold itself sends nothing: a read is a frame, and a frame is channel
  /// time, so asking is a tap even on a developer surface.
  Future<void> readAlerts(WidgetTester t, _AnsweringTransport fake) async {
    await openDeveloper(t, fake);
    await t.ensureVisible(find.byKey(const Key('radio-alerts-read')));
    await t.pump();
    await t.tap(find.byKey(const Key('radio-alerts-read')));
    await t.pump();
    await t.pump();
  }

  Future<void> reveal(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pump();
  }

  /// Let any read still waiting run out, so the case does not end with a
  /// `Future.timeout` timer armed (flutter_test fails a test that leaves one).
  Future<void> letWindowsExpire(WidgetTester t) async {
    await t.pump(const Duration(seconds: 7));
    await t.pumpAndSettle();
  }

  testWidgets('opening the developer fold reads both outputs from the radio',
      (WidgetTester t) async {
    final (MeshcoreController ctrl, _AnsweringTransport fake) = await pump(t);
    await readAlerts(t, fake);
    await awaitSent(t, fake, 'b1|get buzzer');

    fake.emit(cliReply('b1buzzer: on'));
    await answerCli(t, fake, id: 'buzzer', verdict: ok());
    expect(find.text('Buzzer — The MeshCore radio said: buzzer: on'), findsOneWidget,
        reason: 'the radio\'s own words, not a parsed paraphrase');

    // The second read follows the first, because the app allows one CLI command
    // at a time.
    await awaitSent(t, fake, 'v1|get vibration');
    fake.emit(cliReply('v1vibration: off'));
    await answerCli(t, fake, id: 'vibration', verdict: ok());
    expect(find.text('Vibration — The MeshCore radio said: vibration: off'),
        findsOneWidget);

    // The state the radio reported is what disables the redundant choice: it
    // says the buzzer is on, so "On" cannot be pressed again.
    expect(
        t
            .widget<MmAction>(find.byKey(const Key('radio-alert-buzzer-on')))
            .onPressed,
        isNull);
    expect(
        t
            .widget<MmAction>(find.byKey(const Key('radio-alert-buzzer-off')))
            .onPressed,
        isNotNull);
    ctrl.dispose();
  });

  testWidgets('a set re-reads the radio rather than showing what was asked for',
      (WidgetTester t) async {
    final (MeshcoreController ctrl, _AnsweringTransport fake) = await pump(t);
    await readAlerts(t, fake);
    fake.emit(cliReply('b1buzzer: on'));
    await answerCli(t, fake, id: 'buzzer', verdict: ok());
    await awaitSent(t, fake, 'v1|get vibration');
    fake.emit(cliReply('v1vibration: off'));
    await answerCli(t, fake, id: 'vibration', verdict: ok());

    await reveal(t, find.byKey(const Key('radio-alert-buzzer-off')));
    await t.tap(find.byKey(const Key('radio-alert-buzzer-off')));
    await awaitSent(t, fake, 'b2|set buzzer off');

    fake.emit(cliReply('b2set buzzer off'));
    await answerCli(t, fake, id: 'buzzer', verdict: ok());
    // The screen asked again instead of assuming the write took: the re-read is
    // the only thing that proves what the radio stored.
    await awaitSent(t, fake, 'b1|get buzzer');
    expect(sentTexts(fake).where((String s) => s == 'b1|get buzzer').length, 2,
        reason: 'the read that follows a write is a second get');
    fake.emit(cliReply('b1buzzer: off'));
    await answerCli(t, fake, id: 'buzzer', verdict: ok());
    expect(find.text('Buzzer — The MeshCore radio said: buzzer: off'), findsOneWidget);
    await letWindowsExpire(t);
    ctrl.dispose();
  });

  testWidgets('a refusal names the firmware\'s cause, not just "refused"',
      (WidgetTester t) async {
    final (MeshcoreController ctrl, _AnsweringTransport fake) = await pump(t);
    await readAlerts(t, fake);
    fake.emit(cliReply('b1buzzer: on'));
    await answerCli(t, fake, id: 'buzzer', verdict: ok());
    await awaitSent(t, fake, 'v1|get vibration');
    fake.emit(cliReply('v1vibration: off'));
    await answerCli(t, fake, id: 'vibration', verdict: ok());

    await reveal(t, find.byKey(const Key('radio-alert-buzzer-off')));
    await t.tap(find.byKey(const Key('radio-alert-buzzer-off')));
    await awaitSent(t, fake, 'b2|set buzzer off');

    // ERR_CODE_BAD_STATE is what the firmware sends for a refused command.
    await answerCli(t, fake, id: 'buzzer', verdict: err(4));
    expect(find.textContaining('The MeshCore radio refused'), findsWidgets,
        reason: 'the row and the snack both say it');

    // The re-read that follows a failed set is answered too, so the screen
    // settles on a value rather than a spinner.
    await awaitSent(t, fake, 'b1|get buzzer');
    fake.emit(cliReply('b1buzzer: on'));
    await answerCli(t, fake, id: 'buzzer', verdict: ok());
    expect(find.text('Buzzer — The MeshCore radio said: buzzer: on'), findsOneWidget);
    await letWindowsExpire(t);
    ctrl.dispose();
  });

  testWidgets('silence says so and frees the control again',
      (WidgetTester t) async {
    final (MeshcoreController ctrl, _AnsweringTransport fake) = await pump(t);
    await readAlerts(t, fake);
    // Nothing answers. The window is six seconds per command and the two reads
    // run in series, so both windows are advanced here.
    await t.pump(const Duration(seconds: 7));
    await t.pump(const Duration(seconds: 7));
    await t.pumpAndSettle();

    expect(find.textContaining('No answer inside six seconds'), findsWidgets);
    expect(
        t
            .widget<MmAction>(find.byKey(const Key('radio-alerts-read')))
            .onPressed,
        isNotNull,
        reason: 'a wait that ran out must leave the read available again');
    ctrl.dispose();
  });

  testWidgets('the alerts block has no way to type anything at the radio',
      (WidgetTester t) async {
    final (MeshcoreController ctrl, _AnsweringTransport fake) = await pump(t);
    await openDeveloper(t, fake);
    final Finder block = find.byKey(const Key('radio-alerts'));
    expect(block, findsOneWidget);
    expect(find.descendant(of: block, matching: find.byType(TextField)),
        findsNothing,
        reason: 'CMD_RUN_CLI_COMMAND is the radio\'s whole shell, so the only '
            'way in is a typed command');
    expect(find.byKey(const Key('radio-alert-buzzer-on')), findsOneWidget);
    expect(find.byKey(const Key('radio-alert-buzzer-off')), findsOneWidget);
    expect(find.byKey(const Key('radio-alert-vibration-on')), findsOneWidget);
    expect(find.byKey(const Key('radio-alert-vibration-off')), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('radio-alerts-read')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('radio-alerts-read')));
    await t.pumpAndSettle();
    await awaitSent(t, fake, 'b1|get buzzer');
    fake.emit(cliReply('b1buzzer: on'));
    await answerCli(t, fake, id: 'buzzer', verdict: ok());
    await awaitSent(t, fake, 'v1|get vibration');
    fake.emit(cliReply('v1vibration: on'));
    await answerCli(t, fake, id: 'vibration', verdict: ok());
    ctrl.dispose();
  });
}

/// The fake radio, answering every command it is sent with a bare OK except the
/// CLI command (`0x42`), and going quiet while a CLI command is in flight.
///
/// The quiet part is not decoration. A bare `OK` is claimed by the oldest
/// command waiting for one, because the wire carries no correlation tag; the app
/// keeps a background drain running, so a fake that answered it while the CLI
/// command waited would give the verdict to the wrong entry.
class _AnsweringTransport extends FakeMeshcoreTransport {
  _AnsweringTransport() : super(connected: true);

  bool quiet = false;

  @override
  Future<void> send(Uint8List frame) async {
    await super.send(frame);
    if (quiet) return;
    if (frame.isNotEmpty && frame.first == 0x42) return;
    emit(Uint8List.fromList(<int>[0x00]));
  }
}
