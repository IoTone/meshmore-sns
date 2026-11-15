// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/app/demo_mode.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/notifications/channel_notification_prefs.dart';
import 'package:meshmore_sns_app/perms/battery_exemption.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/screens/app_settings_screen.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';
import 'package:meshmore_sns_app/util/prefs.dart';

import '../meshcore/fake_transport.dart';

/// `docs/MISSING-WORK.md` §9 — the one app-side piece of the "I get no
/// notifications" question.
///
/// The background switch is a preference. Whether Android honours it is a fact
/// the app could not read, so a reader whose OEM stopped the service had
/// nothing to look at. The row states the problem, offers the one-tap request,
/// and says nothing at all when there is nothing to say: exempt is the promise
/// holding, and unavailable is a platform that cannot answer, which must not be
/// painted as a warning that may be false.
class _FakeExemption implements BatteryExemptionService {
  _FakeExemption(this.state);

  BatteryExemption state;
  int reads = 0;
  int requests = 0;

  @override
  Future<BatteryExemption> read() async {
    reads++;
    return state;
  }

  @override
  Future<bool> request() async {
    requests++;
    return true;
  }
}

/// The screen's provider set, and the teardown that stops the controller's
/// timers: a pending timer is a test failure, so the host is disposed inside
/// the test body rather than in a tear-down.
class _Host {
  _Host({
    required this.mc,
    required this.prefs,
    required this.tts,
    required this.locale,
    required this.exemption,
  });

  final MeshcoreController mc;
  final NotificationPrefs prefs;
  final TtsController tts;
  final LocaleController locale;
  final _FakeExemption exemption;

  Future<void> dispose(WidgetTester t) async {
    mc.dispose();
    prefs.dispose();
    tts.dispose();
    locale.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Prefs.reset();
    // The background preference is persisted, and a test platform with no
    // store would silently drop the write and read the default back.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(Prefs.reset);

  Future<_Host> pump(
    WidgetTester t, {
    required BatteryExemption state,
    bool backgroundOn = true,
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
    fake.emit(deviceInfoFrame());

    final _FakeExemption exemption = _FakeExemption(state);
    final NotificationPrefs prefs = NotificationPrefs();
    final TtsController tts = TtsController();
    final LocaleController locale = LocaleController();

    await t.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<NotificationPrefs>.value(value: prefs),
          ChangeNotifierProvider<TtsController>.value(value: tts),
          ChangeNotifierProvider<LocaleController>.value(value: locale),
          ChangeNotifierProvider<BlockStore>(create: (_) => BlockStore()),
          ChangeNotifierProvider<DemoMode>(create: (_) => DemoMode()),
        ],
        child: Provider<PermissionsService>.value(
          value: NoopPermissionsService(),
          child: Provider<BatteryExemptionService>.value(
            value: exemption,
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
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    // Set explicitly in both directions, and only after the first frames: the
    // controller reads the stored preference once, asynchronously, at
    // construction, and a read that lands after this call would overwrite it.
    await mc.setBackgroundKeepaliveEnabled(backgroundOn);
    await t.pump();
    return _Host(
      mc: mc,
      prefs: prefs,
      tts: tts,
      locale: locale,
      exemption: exemption,
    );
  }

  final Finder row =
      find.byKey(const ValueKey<String>('settings-battery-exemption'));

  testWidgets('an optimised app is told, and the offer opens the OS request',
      (WidgetTester t) async {
    final _Host h = await pump(t, state: BatteryExemption.optimised);

    expect(row, findsOneWidget);
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(AppSettingsScreen)));
    expect(find.text(l.settingsBatteryOptimisedTitle), findsOneWidget);
    expect(find.text(l.settingsBatteryOptimisedSub), findsOneWidget);

    await t.tap(find.text(l.settingsBatteryAllow));
    await t.pump();
    expect(h.exemption.requests, 1,
        reason: 'the action must reach the OS request');
    expect(h.exemption.reads, greaterThan(1),
        reason: 'the answer is read again rather than assumed');
    await h.dispose(t);
  });

  testWidgets('an exempt app is not warned about', (WidgetTester t) async {
    final _Host h = await pump(t, state: BatteryExemption.exempt);
    expect(row, findsNothing,
        reason: 'exempt is the promise holding, so there is nothing to say');
    await h.dispose(t);
  });

  testWidgets('a platform that cannot answer is not painted as a warning',
      (WidgetTester t) async {
    final _Host h = await pump(t, state: BatteryExemption.unavailable);
    expect(row, findsNothing);
    await h.dispose(t);
  });

  testWidgets('with the background link off there is no promise to warn about',
      (WidgetTester t) async {
    final _Host h =
        await pump(t, state: BatteryExemption.optimised, backgroundOn: false);
    expect(row, findsNothing);
    await h.dispose(t);
  });
}
