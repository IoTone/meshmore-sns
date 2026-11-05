// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_echo.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

/// A place report's countdown is anchored on when the message arrived, not on
/// when the row happens to be built. Anchoring on the build re-started the TTL
/// on every rebuild, so an expired hazard kept reading "expires in 2 h" and the
/// number under the pin never moved (found in review, 2026-11-05).
ChatMessage _report({required DateTime at, String ttl = '3h'}) => ChatMessage(
      channelIdx: 0,
      outgoing: false,
      at: at,
      text: 'Ana: [PLACE]38.900000,-104.700000 Bridge out [hazard] [TTL:$ttl]',
    );

Widget _host(PlaceStore store, Place place) => ChangeNotifierProvider<
        ThemeController>(
      create: (_) => ThemeController(),
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: PlaceEchoLine(place: place, store: store)),
      ),
    );

void main() {
  test('the parse is anchored on the message, so an old report is expired', () {
    final DateTime now = DateTime(2026, 11, 5, 12);
    final ChatMessage old =
        _report(at: now.subtract(const Duration(hours: 4)));
    final Place? place = PlaceEchoLine.placeOf(old);
    expect(place, isNotNull);
    expect(place!.isLiveAt(now), isFalse,
        reason: 'a 3 h report that arrived 4 h ago has expired');
    expect(place.expiresAt, old.at.add(const Duration(hours: 3)));
  });

  test('a fresh report keeps its own arrival time as the anchor', () {
    final DateTime now = DateTime(2026, 11, 5, 12);
    final ChatMessage fresh =
        _report(at: now.subtract(const Duration(minutes: 30)));
    final Place place = PlaceEchoLine.placeOf(fresh)!;
    expect(place.isLiveAt(now), isTrue);
    expect(place.remainingAt(now), const Duration(hours: 2, minutes: 30),
        reason: 'the remaining time counts from arrival, not from the build');
  });

  testWidgets('the echo says expired, and the countdown is not re-anchored',
      (WidgetTester t) async {
    final DateTime now = DateTime.now();
    final PlaceStore store = PlaceStore();
    final Place expired =
        PlaceEchoLine.placeOf(_report(at: now.subtract(const Duration(hours: 4))))!;
    await t.pumpWidget(_host(store, expired));
    expect(find.textContaining('Expired'), findsOneWidget,
        reason: 'the thread must not promise a hazard that is gone');
    expect(find.textContaining('expires in 3 h'), findsNothing);

    final Place running = PlaceEchoLine
        .placeOf(_report(at: now.subtract(const Duration(minutes: 30))))!;
    await t.pumpWidget(_host(PlaceStore(), running));
    expect(find.textContaining('2h 29m'), findsOneWidget,
        reason: 'half an hour into a 3 h report, 2 h 29-30 m remains');
  });

  testWidgets('the stored row wins over the freshly parsed copy',
      (WidgetTester t) async {
    final DateTime now = DateTime.now();
    final ChatMessage message =
        _report(at: now.subtract(const Duration(minutes: 30)));
    final Place parsed = PlaceEchoLine.placeOf(message)!;
    final PlaceStore store = PlaceStore();
    // The store keeps the same id with a later renewal, as a re-broadcast does.
    store.upsert(Place(
      id: parsed.id,
      reporterName: parsed.reporterName,
      type: parsed.type,
      typeToken: parsed.typeToken,
      label: 'Bridge reopened',
      latE6: parsed.latE6,
      lonE6: parsed.lonE6,
      decimals: parsed.decimals,
      provenance: parsed.provenance,
      ttl: parsed.ttl,
      sentAt: now,
      expiresAt: now.add(const Duration(hours: 3)),
      lastSeen: now,
    ));
    await t.pumpWidget(_host(store, parsed));
    expect(find.textContaining('Bridge reopened'), findsOneWidget);
    expect(find.textContaining('expired'), findsNothing);
  });
}
