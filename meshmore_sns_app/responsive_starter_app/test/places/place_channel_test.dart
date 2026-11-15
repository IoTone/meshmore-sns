// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/gen/app_localizations_en.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/secure/record_cipher.dart';
import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_channel_pref.dart';
import 'package:meshmore_sns_app/places/place_create_sheet.dart';
import 'package:meshmore_sns_app/places/place_report_budget.dart';
import 'package:meshmore_sns_app/places/place_sender.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/places/place_ui.dart';
import 'package:meshmore_sns_app/places/place_wiring.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// A place is ordinary channel text, so the slot it goes to is its whole
/// audience. The app used to send to whichever channel was active and say
/// nothing about it; these are the cases that make the choice real and
/// remembered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final DateTime now = DateTime(2026, 11, 5, 12);

  Place place({
    PlaceProvenance provenance = PlaceProvenance.pinned,
    int? channelIdx,
  }) =>
      Place(
        id: 'abcd1234',
        reporterName: 'Ana',
        type: PlaceType.water,
        typeToken: PlaceType.water.token,
        label: 'Water at the ford',
        latE6: 51500741,
        lonE6: -124596,
        decimals: 6,
        provenance: provenance,
        ttl: PlaceTtl.h1,
        sentAt: now,
        expiresAt: now.add(PlaceTtl.h1.life),
        lastSeen: now,
        channelIdx: channelIdx,
      );

  group('the composer records the slot it sent on', () {
    late PlaceStore store;
    late _FakeSender sender;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = PlaceStore(clock: () => now);
      sender = _FakeSender();
    });

    tearDown(() => store.dispose());

    test('a report carries the sender channel', () async {
      sender.channel = 3;
      final PlaceComposer composer = PlaceComposer(
        store: store,
        budget: PlaceReportBudget(clock: () => now),
        sender: sender,
        clock: () => now,
      );
      final PlaceComposeResult result = await composer.compose(
        latitude: 51.500741,
        longitude: -0.124596,
        label: 'Ford is out',
        type: PlaceType.water,
        ttl: PlaceTtl.h1,
      );
      expect(result.sent, isTrue);
      expect(result.place!.channelIdx, 3);
      expect(store.live().single.channelIdx, 3);
    });

    test('a sender with no channel of its own records none', () async {
      sender.channel = null;
      final PlaceComposer composer = PlaceComposer(
        store: store,
        budget: PlaceReportBudget(clock: () => now),
        sender: sender,
        clock: () => now,
      );
      final PlaceComposeResult result = await composer.compose(
        latitude: 51.500741,
        longitude: -0.124596,
        label: 'Ford is out',
        type: PlaceType.water,
        ttl: PlaceTtl.h1,
      );
      expect(result.place!.channelIdx, isNull);
    });
  });

  group('the store keeps the slot', () {
    late Directory dir;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      dir = Directory.systemTemp.createTempSync('mm_places_channel');
      PlaceStore.cipherOverride = MemoryRecordCipher.random();
      PlaceStore.directoryOverride = dir;
    });

    tearDown(() {
      PlaceStore.cipherOverride = null;
      PlaceStore.directoryOverride = null;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('a row written with a channel reads back with it', () async {
      final PlaceStore first = PlaceStore(clock: () => now);
      await first.load();
      first.upsert(place(channelIdx: 2));
      await first.settled;
      first.dispose();

      final PlaceStore second = PlaceStore(clock: () => now);
      await second.load();
      expect(second.live().single.channelIdx, 2);
      second.dispose();
    });

    test('an arriving report records the channel it arrived on', () async {
      final PlaceStore store = PlaceStore(clock: () => now);
      await store.load();
      final Place? stored = store.ingestMessage(ChatMessage(
        channelIdx: 4,
        text: 'Ana: [PLACE1]51.500741,-0.124596 Ford [water]',
        outgoing: false,
        at: now,
      ));
      expect(stored, isNotNull);
      expect(store.live().single.channelIdx, 4);
      store.dispose();
    });

    test('a renewal keeps the slot the row was first seen on', () async {
      final PlaceStore store = PlaceStore(clock: () => now);
      await store.load();
      store.ingestMessage(ChatMessage(
        channelIdx: 1,
        text: 'Ana: [PLACE1]51.500741,-0.124596 Ford [water]',
        outgoing: false,
        at: now,
      ));
      store.ingestMessage(ChatMessage(
        channelIdx: 5,
        text: 'Ana: [PLACE1]51.500741,-0.124596 Ford [water]',
        outgoing: false,
        at: now.add(const Duration(minutes: 1)),
      ));
      expect(store.live().single.channelIdx, 1);
      store.dispose();
    });
  });

  group('the remembered slot', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('nothing is remembered until the reader picks', () async {
      expect(await PlaceChannelPref.read(), isNull);
    });

    test('a choice survives a relaunch and can be forgotten', () async {
      await PlaceChannelPref.write(2);
      expect(await PlaceChannelPref.read(), 2);
      await PlaceChannelPref.clear();
      expect(await PlaceChannelPref.read(), isNull);
    });

    test('a value that is not a slot is dropped rather than trusted', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PlaceChannelPref.key: 'not a number',
      });
      expect(await PlaceChannelPref.read(), isNull);
    });
  });

  group('the channel line', () {
    final AppLocalizations en = AppLocalizationsEn();

    test('a report this device sent says where it went', () {
      expect(
        placeChannelText(en, place(channelIdx: 1),
            <MapEntry<int, String>>[const MapEntry<int, String>(1, '#field')]),
        'Sent on #field',
      );
    });

    test('a report that arrived says where it arrived', () {
      expect(
        placeChannelText(
            en,
            place(provenance: PlaceProvenance.received, channelIdx: 1),
            <MapEntry<int, String>>[const MapEntry<int, String>(1, '#field')]),
        'Arrived on #field',
      );
    });

    test('a slot whose channel is gone still prints its number', () {
      expect(
        placeChannelText(en, place(channelIdx: 7),
            <MapEntry<int, String>>[const MapEntry<int, String>(1, '#field')]),
        'Sent on CH 7',
      );
    });

    test('a row with no channel says nothing', () {
      expect(placeChannelText(en, place(), const <MapEntry<int, String>>[]),
          isNull);
    });
  });

  group('the create sheet', () {
    late FakeMeshcoreTransport fake;
    late MeshcoreController mc;
    late PlaceStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      fake = FakeMeshcoreTransport(connected: true);
      mc = MeshcoreController(
        transportFactory: () async => fake,
        connection:
            MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
        deliveryTimeoutOverride: const Duration(milliseconds: 40),
      );
      await mc.connect();
      fake.emit(selfInfoFrame());
      fake.emit(channelInfoFrame(idx: 0, name: 'Public'));
      fake.emit(channelInfoFrame(idx: 1, name: '#field'));
      await Future<void>.delayed(Duration.zero);
      store = PlaceStore(clock: () => now);
    });

    tearDown(() async {
      mc.dispose();
      store.dispose();
    });

    Widget host(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<MeshcoreController>.value(value: mc),
            ChangeNotifierProvider<PlaceStore>.value(value: store),
            Provider<PlaceReportBudget>(
                create: (_) => PlaceReportBudget(clock: () => now)),
            ChangeNotifierProvider<ThemeController>(
                create: (_) => ThemeController()),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: LocaleController.supported,
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(body: child),
          ),
        );

    testWidgets('a caller that knows the channel wins over the remembered one',
        (WidgetTester t) async {
      // A place suggested by a message belongs on the channel that message
      // arrived on. The sheet used to ignore the caller's slot and open on the
      // remembered one, so the picker and the composer disagreed on screen.
      await PlaceChannelPref.write(0);
      await t.pumpWidget(host(Builder(
        builder: (BuildContext c) => TextButton(
          onPressed: () => PlaceCreateSheet.show(c,
              latitude: 51.500741,
              longitude: -0.124596,
              composer: placeComposerOf(c, channelIdx: 1),
              initialChannelIdx: 1),
          child: const Text('open'),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('#field'), findsWidgets,
          reason: 'the caller named slot 1, and the remembered slot was 0');
    });

    testWidgets('a remembered slot the radio no longer has falls back',
        (WidgetTester t) async {
      // A remembered slot can outlive the channel it named, and a picker that
      // opens on a slot the radio does not have would send nowhere.
      await PlaceChannelPref.write(9);
      await t.pumpWidget(host(Builder(
        builder: (BuildContext c) => TextButton(
          onPressed: () => PlaceCreateSheet.show(c,
              latitude: 51.500741,
              longitude: -0.124596,
              composer: placeComposerOf(c)),
          child: const Text('open'),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Public'), findsOneWidget,
          reason: 'slot 9 does not exist, so the active channel is the answer');
    });

    testWidgets('the picker starts on the active channel and lists the rest',
        (WidgetTester t) async {
      await t.pumpWidget(host(Builder(
        builder: (BuildContext c) => TextButton(
          onPressed: () => PlaceCreateSheet.show(c,
              latitude: 51.500741,
              longitude: -0.124596,
              composer: placeComposerOf(c)),
          child: const Text('open'),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('place-channel-picker')),
          findsOneWidget);
      expect(find.text('Public'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('place-channel-picker')));
      await t.pumpAndSettle();
      expect(find.text('#field'), findsWidgets);
    });

    testWidgets('a chosen channel is the one the report goes out on',
        (WidgetTester t) async {
      await t.pumpWidget(host(Builder(
        builder: (BuildContext c) => TextButton(
          onPressed: () => PlaceCreateSheet.show(c,
              latitude: 51.500741,
              longitude: -0.124596,
              composer: placeComposerOf(c)),
          child: const Text('open'),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      await t.enterText(
          find.byKey(const ValueKey<String>('place-label')), 'Ford is out');
      await t.tap(find.byKey(const ValueKey<String>('place-channel-picker')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('place-channel-1')).last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('place-send')));
      // The radio answers the channel text, which is what makes the send
      // resolve rather than wait out its delivery timeout.
      fake.emit(Uint8List.fromList(<int>[0x00]));
      await t.pumpAndSettle();

      expect(store.live().single.channelIdx, 1);
      // And the choice is remembered for the next report.
      expect(await PlaceChannelPref.read(), 1);
      // A gated send arms the airtime meter's rolling-window tick, which is
      // still pending when the tree is torn down. Let it run out so the test
      // does not end on a live timer.
      await t.pump(const Duration(minutes: 2));
    });
  });
}

final class _FakeSender implements PlaceSender {
  String name = 'Ana';
  Uint8List? key;
  int? channel;

  final List<String> sent = <String>[];

  @override
  String get reporterName => name;

  @override
  Uint8List? get reporterKey => key;

  @override
  int? get destinationChannelIdx => channel;

  @override
  Future<bool> sendPlaceText(String text) async {
    sent.add(text);
    return true;
  }
}
