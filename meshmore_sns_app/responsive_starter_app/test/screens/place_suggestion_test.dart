// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/chat_screen.dart';
import 'package:meshmore_sns_app/sns/place_inference.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';

import '../meshcore/fake_transport.dart';

/// The per-channel inference switch used to promise that a message's place
/// names would be *plotted on the SNS grid*. That layer is gone, so the
/// switch controlled nothing and the copy described a screen that does not
/// exist.
///
/// What it controls now: a name, offered under the row that said it, with the
/// two answers a reader can give — report it or dismiss it. These tests hold
/// the parts that can be asserted without a radio: the gate, the dismissal,
/// and the fact that the offer carries no position of its own.

class _Gaz implements PlaceGazetteer {
  static const List<GazPlace> _all = <GazPlace>[
    GazPlace(
        name: 'Seattle',
        latitude: 47.6062,
        longitude: -122.3321,
        population: 750000),
    GazPlace(
        name: 'Tacoma',
        latitude: 47.2529,
        longitude: -122.4443,
        population: 220000),
  ];

  @override
  List<GazPlace> lookup(String name) {
    final String n = name.toLowerCase().trim();
    return _all.where((GazPlace p) => p.name.toLowerCase() == n).toList();
  }
}

PlaceInferenceEngine _engine() =>
    PlaceInferenceEngine(gazetteer: _Gaz(), jitter: false);

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

MeshcoreController _controller(FakeMeshcoreTransport fake) => MeshcoreController(
      transportFactory: () async => fake,
      placeInferenceEngine: _engine(),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );

ChatMessage _msg(String text, {int channelIdx = 0, bool outgoing = false}) =>
    ChatMessage(channelIdx: channelIdx, text: text, outgoing: outgoing);

Widget _host(MeshcoreController mc) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: MultiProvider(
          providers: <SingleChildWidget>[
            ChangeNotifierProvider<MeshcoreController>.value(value: mc),
            ChangeNotifierProvider<TtsController>(
                create: (_) => TtsController(speaker: _SilentSpeaker())),
            ChangeNotifierProvider<PlaceStore>(
                create: (_) => PlaceStore()),
            Provider<PlaceReportBudget>(
                create: (_) => PlaceReportBudget(clock: DateTime.now)),
          ],
          child: const ChatScreen(),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('the public channel offers a name; a quiet channel does not', () {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _controller(fake);
    expect(mc.placeSuggestionFor(_msg('hello from Seattle')), 'Seattle');
    // Inference is off by default everywhere except the public channel; the
    // switch is the only thing that changes that.
    expect(mc.placeSuggestionFor(_msg('hello from Seattle', channelIdx: 1)),
        isNull);
    mc.dispose();
  });

  test('switching a channel on makes it offer, and off stops it', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _controller(fake);
    expect(mc.placeSuggestionFor(_msg('hello from Seattle', channelIdx: 2)),
        isNull);
    await mc.setPlaceInferenceEnabled(2, true);
    expect(mc.placeSuggestionFor(_msg('hello from Seattle', channelIdx: 2)),
        'Seattle');
    await mc.setPlaceInferenceEnabled(2, false);
    expect(mc.placeSuggestionFor(_msg('hello from Seattle', channelIdx: 2)),
        isNull);
    mc.dispose();
  });

  test('ordinary text offers nothing, and our own messages never do', () {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _controller(fake);
    expect(mc.placeSuggestionFor(_msg('battery at 3.9 volts')), isNull);
    expect(
        mc.placeSuggestionFor(_msg('hello from Seattle', outgoing: true)),
        isNull);
    mc.dispose();
  });

  test('a dismissed suggestion is not offered again', () async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _controller(fake);
    final ChatMessage m = _msg('hello from Seattle');
    expect(mc.placeSuggestionFor(m), 'Seattle');
    await mc.dismissPlaceSuggestion(m);
    expect(mc.placeSuggestionFor(m), isNull);
    mc.dispose();
  });

  testWidgets('the row carries the offer, and Dismiss answers it',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = _controller(fake);
    await t.pumpWidget(_host(mc));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();
    fake.emit(channelMsgFrame(text: 'hello from Seattle, 73'));
    await t.pumpAndSettle();

    expect(find.textContaining('Looks like a place: Seattle'), findsOneWidget);

    final Finder dismiss = find.byWidgetPredicate((Widget w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>)
            .value
            .startsWith('place-suggestion-dismiss-'));
    expect(dismiss, findsOneWidget);
    await t.tap(dismiss);
    await t.pumpAndSettle();
    expect(find.textContaining('Looks like a place: Seattle'), findsNothing);
    mc.dispose();
  });
}
