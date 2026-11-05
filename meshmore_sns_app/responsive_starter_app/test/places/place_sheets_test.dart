// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_create_sheet.dart';
import 'package:meshmore_sns_app/places/place_echo.dart';
import 'package:meshmore_sns_app/places/place_history_sheet.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_sender.dart';
import 'package:meshmore_sns_app/places/place_store.dart';

final DateTime _now = DateTime(2026, 11, 5, 12);

final class _FakeSender implements PlaceSender {
  final List<String> sent = <String>[];

  @override
  String get reporterName => 'Ana';

  @override
  Uint8List? get reporterKey => null;

  @override
  Future<void> sendPlaceText(String text) async => sent.add(text);
}

Place _place({
  String id = 'abcd1234',
  String label = 'Water at the ford',
  String reporter = 'Ana',
  PlaceType type = PlaceType.water,
}) =>
    Place(
      id: id,
      reporterName: reporter,
      type: type,
      typeToken: type.token,
      label: label,
      latE6: 51500741,
      lonE6: -124596,
      decimals: 6,
      provenance: PlaceProvenance.received,
      ttl: PlaceTtl.d2,
      sentAt: _now,
      expiresAt: _now.add(PlaceTtl.d2.life),
      lastSeen: _now,
    );

Widget _host(Widget child) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

void main() {
  late PlaceStore store;
  late _FakeSender sender;
  late PlaceComposer composer;

  setUp(() {
    store = PlaceStore(clock: () => _now);
    sender = _FakeSender();
    composer = PlaceComposer(
      store: store,
      budget: PlaceReportBudget(clock: () => _now),
      sender: sender,
      clock: () => _now,
    );
  });

  tearDown(() => store.dispose());

  group('the create sheet (spec §3, §9, §12)', () {
    testWidgets('a report goes out with the chosen type and life',
        (WidgetTester t) async {
      await t.pumpWidget(_host(Builder(
        builder: (BuildContext c) => TextButton(
          onPressed: () => PlaceCreateSheet.show(c,
              latitude: 51.500741,
              longitude: -0.124596,
              composer: composer),
          child: const Text('open'),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      await t.enterText(
          find.byKey(const ValueKey<String>('place-label')), 'Ford is out');
      await t.tap(find.byKey(const ValueKey<String>('place-type-water')));
      await t.tap(find.byKey(const ValueKey<String>('place-ttl-6h')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey<String>('place-send')));
      await t.pumpAndSettle();

      expect(sender.sent.single,
          '[PLACE]51.500741,-0.124596 Ford is out [water] [TTL:6h]');
      expect(store.live().single.label, 'Ford is out');
    });

    testWidgets('the precision choice moves the digits that travel',
        (WidgetTester t) async {
      await t.pumpWidget(_host(PlaceCreateSheet(
        latitude: 51.500741,
        longitude: -0.124596,
        composer: composer,
      )));
      await t.enterText(
          find.byKey(const ValueKey<String>('place-label')), 'Ford');
      await t.tap(find.byKey(const ValueKey<String>('place-precision-3')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey<String>('place-send')));
      await t.pump();
      expect(sender.sent.single, startsWith('[PLACE]51.501,-0.125 Ford'));
    });

    testWidgets('an empty label is refused in place, and nothing is sent',
        (WidgetTester t) async {
      await t.pumpWidget(_host(PlaceCreateSheet(
        latitude: 51.5,
        longitude: -0.12,
        composer: composer,
      )));
      await t.tap(find.byKey(const ValueKey<String>('place-send')));
      await t.pump();
      expect(find.text('A place needs a few words.'), findsOneWidget);
      expect(sender.sent, isEmpty);
    });

    testWidgets('a spent budget says when the next one may go',
        (WidgetTester t) async {
      final PlaceReportBudget budget = PlaceReportBudget(clock: () => _now);
      budget.take();
      budget.take();
      final PlaceComposer spent = PlaceComposer(
        store: store,
        budget: budget,
        sender: sender,
        clock: () => _now,
      );
      await t.pumpWidget(_host(PlaceCreateSheet(
        latitude: 51.5,
        longitude: -0.12,
        composer: spent,
      )));
      await t.enterText(
          find.byKey(const ValueKey<String>('place-label')), 'Ford');
      await t.tap(find.byKey(const ValueKey<String>('place-send')));
      await t.pump();
      expect(find.textContaining('You have sent 6 in the last hour'),
          findsOneWidget);
      expect(sender.sent, isEmpty);
    });
  });

  group('the history sheet (spec §10)', () {
    testWidgets('search and the live filter narrow the list',
        (WidgetTester t) async {
      store
        ..upsert(_place(id: 'aaaa0001'))
        ..upsert(_place(
            id: 'bbbb0002', label: 'Bridge out', type: PlaceType.hazard));
      await t.pumpWidget(_host(PlaceHistorySheet(store: store)));
      await t.pump();
      expect(find.byKey(const ValueKey<String>('place-row-aaaa0001')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('place-row-bbbb0002')),
          findsOneWidget);

      await t.enterText(
          find.byKey(const ValueKey<String>('place-search')), 'bridge');
      await t.pump();
      expect(find.byKey(const ValueKey<String>('place-row-aaaa0001')),
          findsNothing);
      expect(find.byKey(const ValueKey<String>('place-row-bbbb0002')),
          findsOneWidget);
    });

    testWidgets('the empty state explains how to make one',
        (WidgetTester t) async {
      await t.pumpWidget(_host(PlaceHistorySheet(store: store)));
      await t.pump();
      expect(find.textContaining('Long-press the map'), findsOneWidget);
    });
  });

  group('the chat echo (spec §6)', () {
    test('a channel line is read as a place, an ordinary line is not', () {
      final ChatMessage place = ChatMessage(
        channelIdx: 0,
        text: 'Ana: [PLACE]51.500741,-0.124596 Water at the ford [water] [TTL:2d]',
        outgoing: false,
        at: _now,
      );
      expect(PlaceEchoLine.placeOf(place)?.label, 'Water at the ford');
      final ChatMessage text = ChatMessage(
        channelIdx: 0,
        text: 'Ana: see you at the ford',
        outgoing: false,
        at: _now,
      );
      expect(PlaceEchoLine.placeOf(text), isNull);
    });

    testWidgets('the echo names the place, its type and its time left',
        (WidgetTester t) async {
      final Place place = _place();
      await t.pumpWidget(_host(PlaceEchoLine(place: place, store: store)));
      await t.pump();
      expect(find.textContaining('Water at the ford'), findsOneWidget);
      expect(find.textContaining('Water'), findsOneWidget);
    });
  });
}
