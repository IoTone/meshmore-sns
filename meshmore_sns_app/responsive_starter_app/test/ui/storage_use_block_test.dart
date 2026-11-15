// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/field/position_history.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/media/media_journal.dart';
import 'package:meshmore_sns_app/meshcore/chat_store.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/own_location.dart';
import 'package:meshmore_sns_app/places/place.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/storage_use_block.dart';

import '../meshcore/fake_transport.dart';

/// The storage block states what each store can prove, and its one destructive
/// action has to make its own copy true: the confirmation names both halves —
/// what this app kept and what the radio keeps — and the confirm stays disabled
/// until the word is typed.
///
/// Two properties are pinned here that are easy to get wrong. A store outside
/// the tree is absent rather than a zero that reads as "empty", because the
/// block's whole claim is that it states only what it can measure. And a
/// deletion repaints the counts on the same screen: a block that still says
/// "Places 2 of 500" after deleting them is the same lie as a snack that says
/// it worked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlaceStore places;
  late PositionRecorder trail;
  late MediaInterruptions media;
  late MeshcoreController mc;
  late FakeMeshcoreTransport fake;
  late ThemeController theme;

  Place place(String id) => Place(
        id: id,
        reporterName: "Ana",
        type: PlaceType.water,
        typeToken: PlaceType.water.token,
        label: "Water at the ford",
        latE6: 51500741,
        lonE6: -124596,
        decimals: 6,
        provenance: PlaceProvenance.received,
        ttl: PlaceTtl.d2,
        sentAt: DateTime.now(),
        expiresAt: DateTime.now().add(PlaceTtl.d2.life),
        lastSeen: DateTime.now(),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      "mm.paired.id": "AA:BB:CC:DD",
    });
    places = PlaceStore();
    trail = PositionRecorder(persist: false, autoTick: false);
    media = MediaInterruptions(initial: <int>{7, 9});
    fake = FakeMeshcoreTransport(connected: true);
    mc = MeshcoreController(transportFactory: () async => fake);
    theme = ThemeController();
  });

  tearDown(() {
    places.dispose();
    trail.dispose();
    media.dispose();
    mc.dispose();
  });

  /// Pumps the block with whichever stores the case is about.
  ///
  /// Every one is optional on purpose: the real app provides all of them, and a
  /// test that provides only some is how "absent, not zero" is proved.
  Future<void> pump(
    WidgetTester t, {
    bool withPlaces = true,
    bool withTrail = true,
    bool withMedia = true,
    bool withController = true,
  }) async {
    await theme.setPreset(MmThemePreset.air);
    await t.pumpWidget(MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        if (withController)
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        if (withPlaces) ChangeNotifierProvider<PlaceStore>.value(value: places),
        if (withTrail)
          ChangeNotifierProvider<PositionRecorder>.value(value: trail),
        if (withMedia)
          ChangeNotifierProvider<MediaInterruptions>.value(value: media),
      ],
      child: MaterialApp(
        locale: const Locale("en"),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: theme.theme,
        home: const Scaffold(body: StorageUseBlock()),
      ),
    ));
    await t.pump();
  }

  /// One channel line through the real inbound path, so what gets deleted is
  /// the controller's own history rather than a fixture.
  Future<void> withOneMessage(WidgetTester t) async {
    await mc.connect();
    fake.emit(selfInfoFrame());
    fake.emit(channelMsgFrame(text: "hello there"));
    await t.pumpAndSettle();
    expect(mc.allMessages, hasLength(1), reason: "the row has to exist first");
  }

  Future<void> openDialog(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey<String>("storage-clear-everything")));
    await t.pumpAndSettle();
    expect(find.text("Delete everything?"), findsOneWidget);
  }

  FilledButton confirmButton(WidgetTester t) => t.widget<FilledButton>(
      find.byKey(const ValueKey<String>("storage-clear-all-confirm")));

  testWidgets("without the map open it says so instead of showing zero",
      (WidgetTester t) async {
    await pump(t);
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(StorageUseBlock)));
    expect(find.text(l.storageMapsUnknown), findsOneWidget);
  });

  testWidgets("the sealed history size is published by the store",
      (WidgetTester t) async {
    await pump(t);
    ChatStore.bytes.value = 40 * 1024;
    await t.pump();
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(StorageUseBlock)));
    expect(find.text(l.storageHistory("40")), findsOneWidget,
        reason: "the number is the store's own record size, in KB");
    ChatStore.bytes.value = 0;
  });

  testWidgets("every store states its count and the bound it is held to",
      (WidgetTester t) async {
    places.upsert(place("aaaaaaaa"));
    places.upsert(place("bbbbbbbb"));
    trail.record(const OwnLocation(
        latitude: 51.5, longitude: -0.1, source: OwnLocationSource.phoneFix));
    await pump(t);

    expect(find.text("Places 2 of 500"), findsOneWidget);
    expect(find.text("Trail 1 points of 2000, seven days"), findsOneWidget,
        reason: "the count is the store's, not one the block invented");
    expect(find.text("Unfinished media transfers 2"), findsOneWidget);
  });

  testWidgets("a store outside the tree is absent rather than zero",
      (WidgetTester t) async {
    await pump(t, withPlaces: false, withTrail: false, withMedia: false);
    expect(find.textContaining("Places "), findsNothing);
    expect(find.textContaining("Trail "), findsNothing);
    expect(find.textContaining("Unfinished media"), findsNothing);
    expect(find.textContaining("Message history"), findsOneWidget,
        reason: "the sealed history publishes its own size, so it is always "
            "measurable");
  });

  testWidgets(
      "the destructive action is offered only where it can keep its "
      "promise", (WidgetTester t) async {
    await pump(t, withController: false);
    expect(find.byKey(const ValueKey<String>("storage-clear-everything")),
        findsNothing,
        reason: "without the controller it cannot delete the history its copy "
            "names, so it does not offer to");
  });

  testWidgets(
      "the confirm stays disabled until the word is typed, and a "
      "wrong word keeps it disabled", (WidgetTester t) async {
    await pump(t);
    await openDialog(t);
    expect(confirmButton(t).onPressed, isNull, reason: "nothing is typed yet");

    await t.enterText(
        find.byKey(const ValueKey<String>("storage-clear-all-field")),
        "delete");
    await t.pump();
    expect(confirmButton(t).onPressed, isNull,
        reason: "the word is DELETE, and case is part of the act");

    await t.enterText(
        find.byKey(const ValueKey<String>("storage-clear-all-field")),
        "DELETE");
    await t.pump();
    expect(confirmButton(t).onPressed, isNotNull);
  });

  testWidgets("cancelling deletes nothing", (WidgetTester t) async {
    places.upsert(place("aaaaaaaa"));
    await withOneMessage(t);
    await pump(t);
    final int historyBefore = mc.allMessages.length;

    await openDialog(t);
    await t.tap(find.text("Cancel"));
    await t.pumpAndSettle();

    expect(places.all, hasLength(1));
    expect(mc.allMessages, hasLength(historyBefore));
    expect(media.count, 2);
    expect(find.text("Places 1 of 500"), findsOneWidget);
  });

  testWidgets(
      "confirming deletes what the dialog lists, repaints the counts, "
      "and leaves the radio and the settings alone", (WidgetTester t) async {
    places.upsert(place("aaaaaaaa"));
    trail.record(const OwnLocation(
        latitude: 51.5, longitude: -0.1, source: OwnLocationSource.phoneFix));
    await withOneMessage(t);
    await pump(t);

    await openDialog(t);
    await t.enterText(
        find.byKey(const ValueKey<String>("storage-clear-all-field")),
        "DELETE");
    await t.pump();
    await t
        .tap(find.byKey(const ValueKey<String>("storage-clear-all-confirm")));
    // The action gives each store a bounded wait and reports either way, so a
    // host with no Keystore — where the sealed writes cannot land — still ends
    // with a sentence. Pumped in small steps and stopped the moment the snack
    // is there: a longer step would advance past the snack's own four seconds
    // and dismiss the very sentence being asserted.
    await t.pump();
    for (int i = 0; i < 120 && find.byType(SnackBar).evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 500));
    }

    // Two of the five steps cannot finish on a host without a Keystore (the
    // sealed history and the sealed places file), so the sentence names them
    // rather than claiming a clean delete. The happy-path wording is pinned by
    // the case below, which does not need a platform store.
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(StorageUseBlock)));
    expect(find.text(l.storageClearAllPartly(2, 5)), findsOneWidget,
        reason: "a delete that cannot finish still has to say so");
    expect(mc.allMessages, isEmpty,
        reason: "the controller's memory is the store's truth: clearing only "
            "the file would let the next message write it back");
    expect(places.all, isEmpty);
    expect(trail.rows, isEmpty);
    expect(media.count, 0);

    // The same screen, with no navigation: the counts are the proof the delete
    // landed, and a stale line here would be the lie the dialog exists to avoid.
    expect(find.text("Places 0 of 500"), findsOneWidget);
    expect(find.text("Trail 0 points of 2000, seven days"), findsOneWidget);
    expect(find.text("Unfinished media transfers 0"), findsOneWidget);

    final SharedPreferences p = await SharedPreferences.getInstance();
    expect(p.getString("mm.paired.id"), "AA:BB:CC:DD",
        reason: "the paired radio survives: it is not the app's data");
  });

  test("both halves of the answer are reachable", () {
    final AppLocalizations en = lookupAppLocalizations(const Locale("en"));
    expect(StorageUseBlock.clearEverythingMessage(en, 0, 5),
        "Deleted. The MeshCore radio and your settings are untouched.");
    expect(
        StorageUseBlock.clearEverythingMessage(en, 2, 5),
        "2 of 5 stores did not finish. What is left is listed here. The MeshCore radio "
        "and your settings are untouched.");
  });

  testWidgets("the block holds the floor on paper", (WidgetTester t) async {
    t.view.physicalSize = const Size(320, 780);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await pump(t);
    expect(t.takeException(), isNull);
  });
}
