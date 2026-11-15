// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/app/demo_mode.dart';
import 'package:meshmore_sns_app/field/position_history.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/maps/maps_controller.dart';
import 'package:meshmore_sns_app/media/media_journal.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/chat_store.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/notifications/channel_notification_prefs.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/places/place_store.dart';
import 'package:meshmore_sns_app/screens/app_settings_screen.dart';
import 'package:meshmore_sns_app/ui/mm_collapse_controller.dart';
import 'package:meshmore_sns_app/ui/mm_collapsible.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';
import 'package:meshmore_sns_app/util/prefs.dart';

import '../meshcore/fake_transport.dart';

/// App settings: the screen every other screen was tested against and this one
/// was not.
///
/// It is nearly six hundred lines and it carries four things that would not
/// survive a refactor silently, so each has a case here rather than a comment:
///
/// - storage: the block under the fold states what the app holds, and a store
///   that cannot measure itself is *absent* rather than shown as a zero,
///   because a zero reads as empty and this block only prints what it can prove;
/// - history export: the one backup row, wired to the passphrase dialog;
/// - radio access: the pairing PIN, which is a radio command (0x25) rather than
///   a setting, so it refuses whatever the firmware would refuse;
/// - terms: the privacy text, reachable again long after it was agreed to.
///
/// The storage-full state is not drawn on this screen. `Prefs.writeFailed` is
/// raised by the app's write path and rendered by the dashboard's degraded
/// banner; the flag itself is asserted at the bottom, because this screen is
/// where the action that relieves it lives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(Prefs.reset);
  tearDown(Prefs.reset);

  AppLocalizations strings(WidgetTester t) =>
      AppLocalizations.of(t.element(find.byType(AppSettingsScreen)));

  /// A folded group builds no children until it is opened, which is why these
  /// cases open the fold rather than reaching into it.
  ///
  /// By id, not by title: a section header is drawn through the skin's type
  /// rules, so its text on screen is upper case in most presets and the ARB
  /// string does not match it.
  Future<void> openGroup(WidgetTester t, String id) async {
    final Finder section = find.byWidgetPredicate(
        (Widget w) => w is MmCollapsibleSection && w.id == id);
    expect(section, findsOneWidget, reason: 'no group with id $id on screen');
    await t.tap(
        find.descendant(of: section, matching: find.byType(InkWell)).first);
    await t.pump();
  }

  group('storage', () {
    testWidgets('the airtime cutoff is a switch with the hour stated beside it',
      (WidgetTester t) async {
    final _Host h = await _pump(t);
    final Finder cutoff =
        find.byKey(const ValueKey<String>('settings-airtime-cutoff'));
    expect(cutoff, findsOneWidget,
        reason: 'the owner asked for a cutoff a reader can switch on');
    expect(find.byKey(const ValueKey<String>('settings-airtime-left')),
        findsOneWidget,
        reason: 'and the time left in the hour stated under it');
    expect(h.mc.airtimeCutoff, isTrue);
    await t.tap(cutoff);
    await t.pump();
    expect(h.mc.airtimeCutoff, isFalse,
        reason: 'the switch must reach the controller');
    await h.dispose(t);
  });

  testWidgets('a store that is not in the tree is absent, not a zero',
        (WidgetTester t) async {
      final _Host host = await _pump(t);
      final AppLocalizations l = strings(t);
      await openGroup(t, MmGroupIds.persStorage);

      // Maps: absent, so the block says so rather than "0.0 MB of …".
      expect(find.text(l.storageMapsUnknown), findsOneWidget);
      expect(find.textContaining('Cached tiles'), findsNothing);
      // Places, trail and media are watched stores: absent means no line at
      // all, because "Places 0 of 500" would read as "you have none" when the
      // truth is that this build cannot tell you.
      expect(find.textContaining('Places '), findsNothing);
      expect(find.textContaining('Trail '), findsNothing);
      expect(find.textContaining('Unfinished media'), findsNothing);
      await host.dispose(t);
    });

    testWidgets('a store that is in the tree states its own bound',
        (WidgetTester t) async {
      final _Host host = await _pump(t, withOptionalStores: true);
      final AppLocalizations l = strings(t);
      await openGroup(t, MmGroupIds.persStorage);

      expect(
          find.text(l.storagePlaces(0, PlaceStore.capacity)), findsOneWidget);
      expect(find.text(l.storageTrail(0, PositionHistoryStore.capacity)),
          findsOneWidget);
      expect(find.text(l.storageMedia(0)), findsOneWidget);
      expect(find.text(l.storageMapsUnknown), findsNothing);
      await host.dispose(t);
    });

    testWidgets('the history line follows the sealed store, not a constant',
        (WidgetTester t) async {
      final int before = ChatStore.bytes.value;
      ChatStore.bytes.value = 4096;
      final _Host host = await _pump(t);
      final AppLocalizations l = strings(t);
      await openGroup(t, MmGroupIds.persStorage);
      expect(find.text(l.storageHistory('4')), findsOneWidget);
      await host.dispose(t);
      ChatStore.bytes.value = before;
    });

    testWidgets('deleting everything is gated on the word the dialog names',
        (WidgetTester t) async {
      final _Host host = await _pump(t);
      final AppLocalizations l = strings(t);
      await openGroup(t, MmGroupIds.persStorage);

      await t
          .tap(find.byKey(const ValueKey<String>('storage-clear-everything')));
      await t.pumpAndSettle();

      final Finder confirm =
          find.byKey(const ValueKey<String>('storage-clear-all-confirm'));
      expect(confirm, findsOneWidget);
      expect(t.widget<FilledButton>(confirm).onPressed, isNull);
      expect(find.text(l.storageClearAllGoes), findsOneWidget);
      expect(find.text(l.storageClearAllStays), findsOneWidget);

      final Finder field =
          find.byKey(const ValueKey<String>('storage-clear-all-field'));
      await t.enterText(field, 'delete');
      await t.pump();
      expect(t.widget<FilledButton>(confirm).onPressed, isNull,
          reason: 'the word is upper case; a lower-case attempt stays refused');
      await t.enterText(field, 'DELETE');
      await t.pump();
      expect(t.widget<FilledButton>(confirm).onPressed, isNotNull);
      await host.dispose(t);
    });
  });

  group('history export', () {
    testWidgets(
        'the backup row opens the passphrase dialog, and cancelling '
        'writes nothing', (WidgetTester t) async {
      final _Host host = await _pump(t);
      final AppLocalizations l = strings(t);
      final Finder row =
          find.byKey(const ValueKey<String>('settings-export-history'));
      await t.ensureVisible(row);
      await t.pump();
      expect(find.text(l.settingsHistoryExportRow), findsOneWidget);
      expect(find.text(l.settingsHistoryExportSubtitle), findsOneWidget);

      await t.tap(row);
      await t.pumpAndSettle();
      expect(find.text(l.settingsHistoryExportTitle), findsOneWidget,
          reason: 'the row asks for a passphrase before it encodes anything');

      await t.tap(find.text(l.actionCancel));
      await t.pumpAndSettle();
      expect(find.text(l.settingsHistoryExportTitle), findsNothing);
      await host.dispose(t);
    });
  });

  group('radio access: the pairing PIN', () {
    testWidgets(
        'the current PIN comes from the radio, and no PIN reads as '
        'none', (WidgetTester t) async {
      final _Host bare = await _pump(t, blePin: 0);
      AppLocalizations l = strings(t);
      await openGroup(t, MmGroupIds.persSecurity);
      expect(find.text(l.settingsPinNone), findsOneWidget,
          reason: 'a radio with no PIN must not read as zero');
      await bare.dispose(t);

      final _Host set = await _pump(t, blePin: 482913);
      l = strings(t);
      await openGroup(t, MmGroupIds.persSecurity);
      expect(find.text('482913'), findsOneWidget);
      await set.dispose(t);
    });

    testWidgets('the setter refuses a PIN the firmware would refuse',
        (WidgetTester t) async {
      final _Host host = await _pump(t, blePin: 0);
      final AppLocalizations l = strings(t);
      await openGroup(t, MmGroupIds.persSecurity);
      final int before = host.fake.sent.length;

      await t.enterText(
          find.byKey(const ValueKey<String>('device-pin')), '12345');
      await t.tap(find.text(l.settingsPinSet));
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));

      expect(find.text(l.settingsPinBad), findsOneWidget,
          reason: 'a PIN is exactly six digits, and the screen says so');
      expect(host.fake.sent.length, before,
          reason: 'a refused PIN is never put on the wire');
      expect(
          host.fake.sent.where((Uint8List f) => f.isNotEmpty && f[0] == 0x25),
          isEmpty);
      await host.dispose(t);
    });

    testWidgets('a six-digit PIN is sent as SET_DEVICE_PIN',
        (WidgetTester t) async {
      final _Host host = await _pump(t, blePin: 0);
      final AppLocalizations l = strings(t);
      await openGroup(t, MmGroupIds.persSecurity);

      await t.enterText(
          find.byKey(const ValueKey<String>('device-pin')), '482913');
      await t.tap(find.text(l.settingsPinSet));
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));

      final List<Uint8List> pins = host.fake.sent
          .where((Uint8List f) => f.isNotEmpty && f[0] == 0x25)
          .toList(growable: false);
      expect(pins, hasLength(1), reason: 'one command, once');
      final Uint8List frame = pins.single;
      // The command is the opcode then a little-endian u32.
      final int sent =
          frame[1] | (frame[2] << 8) | (frame[3] << 16) | (frame[4] << 24);
      expect(sent, 482913);
      await host.dispose(t);
    });
  });

  group('terms', () {
    testWidgets('the privacy text moved to About, and is not here', (
      WidgetTester t,
    ) async {
      // It is a page you read, not a setting you change, so it lives beside what
      // the app is. This asserts the move rather than deleting the case: a row
      // that reappears here would be the same mistake twice.
      final _Host host = await _pump(t);
      final AppLocalizations l = strings(t);
      expect(find.text(l.termsSettingsRow), findsNothing);
      await host.dispose(t);
    });
  });

  group('the storage-full state', () {
    test('a write that did not land raises the flag, and it stays raised',
        () async {
      // The screen does not render this; the dashboard's degraded banner does.
      // The flag is what makes that banner appear, and the action that exists
      // to relieve it is on this screen, so the flag is asserted here.
      expect(Prefs.writeFailed.value, isFalse);
      expect(await Prefs.probeWrite(Future<bool>.value(false)), isFalse);
      expect(Prefs.writeFailed.value, isTrue);
      // Sticky for the session: a device with no room does not recover by
      // being asked again.
      expect(await Prefs.probeWrite(Future<bool>.value(true)), isTrue);
      expect(Prefs.writeFailed.value, isTrue);
    });
  });
}

/// Everything one pumped screen owns, so a case can dispose it inside its own
/// body. That matters: a controller timer still pending when the body returns
/// fails the test after the tree is gone, and a tear-down runs too late for
/// that check.
class _Host {
  _Host({
    required this.mc,
    required this.fake,
    required this.prefs,
    required this.tts,
    required this.locale,
    required this.places,
    required this.trail,
    required this.media,
    required this.maps,
  });

  final MeshcoreController mc;
  final FakeMeshcoreTransport fake;
  final NotificationPrefs prefs;
  final TtsController tts;
  final LocaleController locale;
  final PlaceStore places;
  final PositionRecorder trail;
  final MediaInterruptions media;
  final MapsController maps;

  Future<void> dispose(WidgetTester t) async {
    mc.dispose();
    prefs.dispose();
    tts.dispose();
    locale.dispose();
    places.dispose();
    trail.dispose();
    media.dispose();
    maps.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump();
  }
}

/// The screen's provider set. Copied from
/// `test/screens/app_settings_public_channel_test.dart` so the two hosts cannot
/// drift apart, which is how this screen went untested in the first place.
Future<_Host> _pump(
  WidgetTester t, {
  bool withOptionalStores = false,
  int blePin = 0,
}) async {
  await t.binding.setSurfaceSize(const Size(1000, 5000));
  addTearDown(() => t.binding.setSurfaceSize(null));

  final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
  final MeshcoreController mc = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await mc.connect();
  fake.emit(selfInfoFrame());
  fake.emit(deviceInfoFrame(blePin: blePin));

  final NotificationPrefs prefs = NotificationPrefs();
  final TtsController tts = TtsController();
  final LocaleController locale = LocaleController();
  final PlaceStore places = PlaceStore();
  final PositionRecorder trail =
      PositionRecorder(persist: false, autoTick: false);
  final MediaInterruptions media = MediaInterruptions();
  final MapsController maps = MapsController(appVersion: () => '1.0.0');

  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<NotificationPrefs>.value(value: prefs),
        ChangeNotifierProvider<TtsController>.value(value: tts),
        ChangeNotifierProvider<LocaleController>.value(value: locale),
        ChangeNotifierProvider<BlockStore>(create: (_) => BlockStore()),
        ChangeNotifierProvider<DemoMode>(create: (_) => DemoMode()),
        if (withOptionalStores) ...<ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<PlaceStore>.value(value: places),
          ChangeNotifierProvider<PositionRecorder>.value(value: trail),
          ChangeNotifierProvider<MediaInterruptions>.value(value: media),
          ChangeNotifierProvider<MapsController>.value(value: maps),
        ],
      ],
      child: Provider<PermissionsService>.value(
        value: NoopPermissionsService(),
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const AppSettingsScreen(),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 20));
  return _Host(
    mc: mc,
    fake: fake,
    prefs: prefs,
    tts: tts,
    locale: locale,
    places: places,
    trail: trail,
    media: media,
    maps: maps,
  );
}
