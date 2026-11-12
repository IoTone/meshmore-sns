// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/chat_screen.dart';
import 'package:meshmore_sns_app/screens/nodes_screen.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/mm_components.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

/// The text-size batch, pinned: **a row decides its shape by being measured,
/// not by how many characters it happens to hold.**
///
/// Three components were relying on the width running out to decide the
/// layout — a readout whose label pushed its value off the edge, a section
/// header whose ornament squeezed the heading until "LINK" broke mid-word, and
/// a picker row whose value was capped at a flat 160 dp and ellipsised past
/// it. The fixes are structural and cheap to regress, so each one is asserted
/// twice: at the shape it should take, and by measuring that the text it
/// carries is not truncated.
///
/// The matrix is the app's own claim: 320 dp is the narrowest width it
/// supports and 200 % is the accessibility floor (APP-K2), while 1.0 and 1.6
/// are the sizes a user actually runs at. 411 dp is the handset the owner
/// reads it on.
/// Tear a radio-backed tree down inside the test body.
///
/// `MeshcoreController` keeps polling timers and persists airtime; the
/// harness checks for pending timers at the end of the body, before teardowns
/// run, so the tree has to be disposed and fake time drained here.
Future<void> drainRadio(WidgetTester t, MeshcoreController mc) async {
  mc.dispose();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

void main() {
  const List<double> widths = <double>[320, 411];
  const List<double> scales = <double>[1.0, 1.6, 2.0];

  /// The width a single-line run of text needs, in the style the widget itself
  /// paints with. Comparing this against the box the widget was given is how a
  /// test tells "it fitted" from "it was cut with an ellipsis": both look the
  /// same in the widget tree.
  /// The style the widget actually paints with: `Text` merges its own style
  /// over the ambient one, so a measurement that reads only `w.style` misses
  /// the theme's line height and under-reports the needed height by a third.
  TextStyle effectiveStyle(WidgetTester t, Finder f) {
    final Text w = t.widget<Text>(f);
    return DefaultTextStyle.of(t.element(f)).style.merge(w.style);
  }

  double neededWidth(WidgetTester t, Finder f, double scale) {
    final Text w = t.widget<Text>(f);
    final TextPainter p = TextPainter(
      text: TextSpan(text: w.data, style: effectiveStyle(t, f)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: TextScaler.linear(scale),
    )..layout();
    final double need = p.width;
    p.dispose();
    return need;
  }

  double neededHeight(WidgetTester t, Finder f, double scale) {
    final Text w = t.widget<Text>(f);
    final TextPainter p = TextPainter(
      text: TextSpan(text: w.data, style: effectiveStyle(t, f)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(scale),
    )..layout();
    final double need = p.height;
    p.dispose();
    return need;
  }

  Future<void> pumpBox(
    WidgetTester t, {
    required MmThemePreset preset,
    required double width,
    required double scale,
    required Widget child,
  }) async {
    final ThemeController tc = ThemeController();
    await tc.setPreset(preset);
    addTearDown(tc.dispose);
    t.view.physicalSize = Size(width, 780);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<ThemeController>.value(
      value: tc,
      child: MaterialApp(
        theme: tc.theme,
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  // ---------------------------------------------------------------------------
  // MmReadout — a label and a figure, on one line while they fit on one.
  // ---------------------------------------------------------------------------
  group('MmReadout', () {
    const String longLabel = 'NODES IN RANGE AND HEARD';
    const String value = '53';

    for (final double width in widths) {
      for (final double scale in scales) {
        for (final MmThemePreset preset in <MmThemePreset>[
          MmThemePreset.nerv,
          MmThemePreset.studio,
        ]) {
          testWidgets(
              'readout at ${width.toInt()} dp ${scale}x on ${preset.name}: '
              'the value is never truncated', (WidgetTester t) async {
            await pumpBox(t,
                preset: preset,
                width: width,
                scale: scale,
                child: const MmReadout(label: longLabel, value: value));
            final Finder valueFinder = find.text(value);
            expect(valueFinder, findsOneWidget);
            expect(t.getSize(valueFinder).width,
                greaterThanOrEqualTo(neededWidth(t, valueFinder, scale) - 0.5),
                reason: 'the value was shortened instead of given its own line');
            expect(t.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('a pair that cannot share a line stops sharing one',
        (WidgetTester t) async {
      await pumpBox(t,
          preset: MmThemePreset.studio,
          width: 320,
          scale: 2.0,
          child: const MmReadout(label: longLabel, value: value));
      final double labelBottom = t.getBottomLeft(find.text(longLabel)).dy;
      final double valueTop = t.getTopLeft(find.text(value)).dy;
      expect(valueTop, greaterThanOrEqualTo(labelBottom - 1),
          reason: 'the value takes its own line under the label');
      // One line each: the stacked shape is not a licence to wrap the figure.
      expect(t.getSize(find.text(value)).height,
          lessThanOrEqualTo(neededHeight(t, find.text(value), 2.0) + 1));
    });

    testWidgets('a short pair still shares one line', (WidgetTester t) async {
      await pumpBox(t,
          preset: MmThemePreset.studio,
          width: 411,
          scale: 1.0,
          child: const MmReadout(label: 'BATTERY', value: '87 %'));
      final double labelTop = t.getTopLeft(find.text('BATTERY')).dy;
      final double valueTop = t.getTopLeft(find.text('87 %')).dy;
      expect((valueTop - labelTop).abs(), lessThan(6),
          reason: 'baseline-aligned on one line');
    });
  });

  // ---------------------------------------------------------------------------
  // MmSectionHeader — the label is the content, the stripes are ornament.
  // ---------------------------------------------------------------------------
  group('MmSectionHeader', () {
    for (final double width in widths) {
      for (final double scale in scales) {
        testWidgets(
            'heading at ${width.toInt()} dp ${scale}x beside two 48 dp '
            'controls stays on one line', (WidgetTester t) async {
          await pumpBox(t,
              preset: MmThemePreset.nerv,
              width: width,
              scale: scale,
              child: MmSectionHeader(
                'LINK',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (int i = 0; i < 2; i++)
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          tooltip: 'control $i',
                          onPressed: () {},
                          icon: const Icon(Icons.tune),
                        ),
                      ),
                  ],
                ),
              ));
          final Finder label = find.text('LINK');
          expect(label, findsOneWidget);
          expect(t.getSize(label).height,
              lessThanOrEqualTo(neededHeight(t, label, scale) + 1),
              reason: 'two 48 dp controls may not squeeze the heading into two '
                  'lines — that is "LINK" split mid-word at 2.0 text');
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  // ---------------------------------------------------------------------------
  // MmPickerTile — the value is a value, not a 160 dp slot.
  // ---------------------------------------------------------------------------
  group('MmPickerTile', () {
    const String title = 'Smart broadcast (on movement)';
    const String value = 'Every 15 minutes';

    for (final double width in widths) {
      for (final double scale in scales) {
        testWidgets(
            'picker at ${width.toInt()} dp ${scale}x keeps its value whole',
            (WidgetTester t) async {
          await pumpBox(t,
              preset: MmThemePreset.studio,
              width: width,
              scale: scale,
              child: MmPickerTile(
                title: title,
                value: value,
                onTap: () {},
              ));
          final Finder f = find.text(value);
          expect(f, findsOneWidget);
          // A value may take two lines; what it may not do is lose characters
          // to an ellipsis. The old tile capped the trailing slot at a flat
          // 160 dp and cut the rest off.
          expect(t.widget<Text>(f).overflow, isNot(TextOverflow.ellipsis),
              reason: 'the value must wrap or move, never be shortened');
          final double box = t.getSize(f).width;
          final double need = neededWidth(t, f, scale);
          if (box < need - 0.5) {
            expect(t.getSize(f).height,
                greaterThan(neededHeight(t, f, scale) * 1.5),
                reason: 'a value too wide for its box has to wrap, not clip');
          }
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('the value drops under the title when the pair will not fit',
        (WidgetTester t) async {
      await pumpBox(t,
          preset: MmThemePreset.studio,
          width: 320,
          scale: 2.0,
          child: MmPickerTile(title: title, value: value, onTap: () {}));
      expect(t.getTopLeft(find.text(value)).dy,
          greaterThan(t.getBottomLeft(find.text(title)).dy - 1));
    });

    testWidgets('a short pair keeps the value in the trailing slot',
        (WidgetTester t) async {
      await pumpBox(t,
          preset: MmThemePreset.studio,
          width: 411,
          scale: 1.0,
          child: MmPickerTile(
              title: 'Periodic interval', value: 'Off', onTap: () {}));
      final double titleTop = t.getTopLeft(find.text('Periodic interval')).dy;
      final double valueTop = t.getTopLeft(find.text('Off')).dy;
      expect((valueTop - titleTop).abs(), lessThan(6));
    });

    testWidgets('a disabled picker still says what it is', (WidgetTester t) async {
      await pumpBox(t,
          preset: MmThemePreset.studio,
          width: 320,
          scale: 2.0,
          child: const MmPickerTile(
            title: 'Periodic interval',
            value: 'Off',
            onTap: null,
          ));
      // One of the two colours a disabled row can use, never a framework wash.
      final Text titleText = t.widget<Text>(find.text('Periodic interval'));
      final MmSkin skin = mmSkinFor(MmThemePreset.studio);
      expect(titleText.style!.color, skin.color.fgDisabled);
      expect(t.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // MmValueFields — the dashboard's radio tuple, and every other machine value.
  // ---------------------------------------------------------------------------
  group('MmValueFields', () {
    const List<String> fields = <String>['910.525MHz', 'SF7', 'CR5', '22dBm'];

    for (final double width in widths) {
      for (final double scale in scales) {
        testWidgets(
            'radio tuple at ${width.toInt()} dp ${scale}x breaks between its '
            'fields only', (WidgetTester t) async {
          await pumpBox(t,
              preset: MmThemePreset.studio,
              width: width,
              scale: scale,
              child: const MmValueFields(fields: fields));
          // Either one line carrying every field, or one field per line: never
          // a line that ends inside a field, and never a line holding half a
          // pair of separators.
          final bool oneLine =
              find.text(fields.join(' · ')).evaluate().isNotEmpty;
          if (oneLine) {
            expect(find.text('·'), findsNothing);
          } else {
            for (final String f in fields) {
              expect(find.text(f), findsOneWidget,
                  reason: '$f must be whole when the value is stacked');
              expect(t.getSize(find.text(f)).width,
                  greaterThanOrEqualTo(neededWidth(t, find.text(f), scale) - 0.5),
                  reason: '$f was cut');
            }
          }
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  // ---------------------------------------------------------------------------
  // The chat composer — the field keeps its own width, the buttons move.
  // ---------------------------------------------------------------------------
  group('chat composer', () {
    Future<MeshcoreController> pumpChat(WidgetTester t,
        {required double width, required double scale}) async {
      final FakeMeshcoreTransport fake =
          FakeMeshcoreTransport(connected: true);
      final MeshcoreController mc = MeshcoreController(
        transportFactory: () async => fake,
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
      );
      final ThemeController tc = ThemeController();
      await tc.setPreset(MmThemePreset.studio);
      addTearDown(tc.dispose);
      t.view.physicalSize = Size(width, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final TtsController tts = TtsController(speaker: _SilentSpeaker());
      await t.pumpWidget(MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<TtsController>.value(value: tts),
          ChangeNotifierProvider<ThemeController>.value(value: tc),
        ],
        child: MaterialApp(
          theme: tc.theme,
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const ChatScreen(),
          ),
        ),
      ));
      await mc.connect();
      fake.emit(selfInfoFrame());
      await t.pumpAndSettle();
      return mc;
    }

    testWidgets('at 320 dp and 200 % the actions take their own row',
        (WidgetTester t) async {
      final MeshcoreController mc = await pumpChat(t, width: 320, scale: 2.0);
      final double fieldBottom = t.getBottomLeft(find.byType(TextField)).dy;
      final double sendTop = t.getTopLeft(find.byIcon(Icons.send)).dy;
      expect(sendTop, greaterThanOrEqualTo(fieldBottom - 1),
          reason: 'a 48 dp-wide field beside three buttons is not a composer');
      // The field got the whole row back.
      expect(t.getSize(find.byType(TextField)).width,
          greaterThan(320 * 0.8));
      expect(t.takeException(), isNull);
      await drainRadio(t, mc);
    });

    testWidgets('at 411 dp and 1.0 the actions stay beside the field',
        (WidgetTester t) async {
      final MeshcoreController mc = await pumpChat(t, width: 411, scale: 1.0);
      final Rect field = t.getRect(find.byType(TextField));
      final Rect send = t.getRect(find.byIcon(Icons.send));
      expect(send.top, lessThan(field.bottom),
          reason: 'one row while the field has room for its hint');
      expect(send.left, greaterThan(field.right),
          reason: 'the actions sit to the right of the field');
      expect(t.takeException(), isNull);
      await drainRadio(t, mc);
    });
  });

  // ---------------------------------------------------------------------------
  // The Nodes list, at the matrix, through the screen itself.
  // ---------------------------------------------------------------------------
  group('nodes list', () {
    for (final double width in widths) {
      for (final double scale in scales) {
        testWidgets(
            'nodes at ${width.toInt()} dp ${scale}x lays out without '
            'clipping', (WidgetTester t) async {
          final FakeMeshcoreTransport fake =
              FakeMeshcoreTransport(connected: true);
          final MeshcoreController mc = MeshcoreController(
            transportFactory: () async => fake,
          );
          final ThemeController tc = ThemeController();
          await tc.setPreset(MmThemePreset.studio);
          addTearDown(tc.dispose);
          t.view.physicalSize = Size(width, 780);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          await t.pumpWidget(MultiProvider(
            providers: <SingleChildWidget>[
              ChangeNotifierProvider<MeshcoreController>.value(value: mc),
              ChangeNotifierProvider<ThemeController>.value(value: tc),
            ],
            child: MaterialApp(
              theme: tc.theme,
              locale: const Locale('en'),
              supportedLocales: LocaleController.supported,
              localizationsDelegates: const <LocalizationsDelegate<Object>>[
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: const NodesScreen(),
              ),
            ),
          ));
          await mc.connect();
          fake.emit(selfInfoFrame());
          // The shape the live mesh has: a long hyphenated repeater name and a
          // short one, so the row has to hold a wrapped name beside its age and
          // its star.
          fake.emit(contactFrame(name: 'DEN-CRK-QRMSOS-RD-52ed', firstPubByte: 10));
          fake.emit(contactFrame(name: 'HELTEC-REP', firstPubByte: 90));
          await t.pumpAndSettle();
          expect(find.text('DEN-CRK-QRMSOS-RD-52ed'), findsOneWidget,
              reason: 'the node list is on screen');
          expect(t.takeException(), isNull,
              reason: 'the nodes list overflowed at ${width.toInt()} dp / $scale');
          await drainRadio(t, mc);
        });
      }
    }
  });
}

/// A speech backend that does nothing: the chat screen reads the TTS state, and
/// a widget test has no platform to speak through.
class _SilentSpeaker implements TtsSpeaker {
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> setVoice(TtsVoice? voice) async {}
  @override
  Future<List<TtsVoice>> listVoices() async => const <TtsVoice>[];
  @override
  Future<bool> isLanguageAvailable(String locale) async => true;
}
