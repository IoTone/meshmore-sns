// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/app/degraded_state.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/dashboards/dashboard_host.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/util/prefs.dart';

import '../meshcore/fake_transport.dart';

/// What each dashboard layout says, over one controller state.
///
/// Six layouts render the same [DashboardModel][], and four of them were covered
/// only by the overflow sweep in `a11y_floors_test.dart` — which proves they do
/// not overflow and nothing about what they tell a reader. The table below is
/// the fact itself: each preset's own idiom for the same number, and which of
/// the shared sections that skin carries. Changing one skin's copy is a change
/// to this table, and that is the point: a difference gets recorded instead of
/// being discovered on a phone.
///
/// The pump is the one `dashboard_host_test.dart` uses (ThemeController and
/// MeshcoreController over a fake transport). It is local because that file's
/// helper is private; a third dashboard test should adopt this one.
class _Layout {
  const _Layout({
    required this.name,
    required this.preset,
    required this.peers,
    this.hasFeed = true,
    this.hasLocationTile = false,
  });

  final String name;
  final MmThemePreset preset;

  /// How this skin writes the peers-in-range count. Five put the bare numeral
  /// in a `Text`; Recon writes `seen/known`; the radar puts the label and the
  /// number in one `RichText` cell, which is why the finder differs rather than
  /// the assertion.
  final Finder Function(AppLocalizations l, int peers, int known) peers;

  /// Whether the recent-activity feed is on this layout at all.
  final bool hasFeed;

  /// Whether this layout carries the LOCATION tile. Observed rather than
  /// promised: the radar, gauge, colour-block and codec skins are field
  /// instruments and never carried it; only SEELE and Studio do
  /// (`dashboard_host_test.dart` records the same split).
  final bool hasLocationTile;
}

Finder _numeral(AppLocalizations l, int peers, int known) =>
    find.text('$peers');
Finder _seenOfKnown(AppLocalizations l, int peers, int known) =>
    find.text('$peers/$known');
Finder _railCell(AppLocalizations l, int peers, int known) =>
    find.textContaining('${l.dashPeers} $peers', findRichText: true);

const List<_Layout> _layouts = <_Layout>[
  _Layout(name: 'nerv', preset: MmThemePreset.nerv, peers: _numeral),
  _Layout(name: 'agHud', preset: MmThemePreset.agHud, peers: _numeral),
  _Layout(
      name: 'hyperlocal', preset: MmThemePreset.hyperlocal, peers: _railCell),
  _Layout(
    name: 'drPop',
    preset: MmThemePreset.drPop,
    peers: _numeral,
    hasFeed: false,
  ),
  _Layout(
    name: 'recon',
    preset: MmThemePreset.recon,
    peers: _seenOfKnown,
    hasFeed: false,
  ),
  _Layout(
    name: 'studio',
    preset: MmThemePreset.studio,
    peers: _numeral,
    hasLocationTile: true,
  ),
  _Layout(
    name: 'seele',
    preset: MmThemePreset.seele,
    peers: _numeral,
    hasLocationTile: true,
  ),
];

/// The fixture's fix, as the tile prints it (five decimal places).
const String _kLatFmt = '38.92005';

const List<LocalizationsDelegate<Object>> _delegates =
    <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// Pumps the dashboard under [preset] over [mc], with motion reduced so a skin
/// that animates continuously (the radar sweep, the gauge) can settle.
Future<void> _pumpDashboard(
  WidgetTester t,
  MeshcoreController mc, {
  required MmThemePreset preset,
}) async {
  await t.binding.setSurfaceSize(const Size(1100, 2600));
  addTearDown(() => t.binding.setSurfaceSize(null));
  // Unmount first: pumping a second MaterialApp over the first updates the
  // existing element tree, so two layouts with the same collapsible-group id
  // are briefly mounted together and the duplicate-id guard in
  // `ui/mm_collapsible.dart` prints a warning that is about this test's
  // swapping, not about the app.
  await t.pumpWidget(const SizedBox());
  final ThemeController tc = ThemeController();
  await tc.setReduceMotion(true);
  await tc.setPreset(preset);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<ThemeController>.value(value: tc),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: LocaleController.supported,
        localizationsDelegates: _delegates,
        home: const Scaffold(body: DashboardHost()),
      ),
    ),
  );
  await _settle(t);
}

/// Two frames instead of `pumpAndSettle`.
///
/// A busy link makes several skins animate — a spinner while reconnecting, a
/// pulse on the alert slab — so settling is not something this file can ask for.
/// Two pumps flush the frame that the state change queued, which is all these
/// assertions need; the reduce-motion flag above only stops the ambient sweeps.
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

/// The localizations the layouts render with, for the copy this file asserts on.
Future<AppLocalizations> _localizations(WidgetTester t) async {
  late AppLocalizations l;
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: _delegates,
      home: Builder(builder: (BuildContext c) {
        l = AppLocalizations.of(c);
        return const SizedBox();
      }),
    ),
  );
  return l;
}

/// A connected controller that has heard three nodes and one channel line.
///
/// The nodes are heard now, so all three are in range — a contact whose advert
/// is old is known but not in range, which is the distinction the count is for.
/// The channel line lands in the recent feed with a text nothing else draws.
Future<MeshcoreController> _readyController(
  WidgetTester t,
  FakeMeshcoreTransport fake,
) async {
  final MeshcoreController mc = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await mc.connect();
  fake.emit(selfInfoFrameAt(lat: 38.920045, lon: -104.772826));
  final int nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  for (int i = 0; i < 3; i++) {
    fake.emit(contactFrame(
        name: 'HEARD$i', firstPubByte: 0x40 + i, lastAdvertTs: nowUnix));
  }
  fake.emit(channelMsgFrame(text: 'hello-feed'));
  await t.pump();
  return mc;
}

/// Brings the link back to `ready` after a case dropped it, so the next preset
/// starts from the same state.
Future<void> _makeReady(
  WidgetTester t,
  FakeMeshcoreTransport fake,
) async {
  fake.setConnected(true);
  fake.emit(selfInfoFrame());
  await _settle(t);
}

/// Drains the timers a connected controller and the skins leave behind, then
/// disposes it. Called in-body: a pending periodic timer fails the test before
/// a teardown would get the chance to cancel it.
Future<void> _finish(WidgetTester t, MeshcoreController mc) async {
  mc.dispose();
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets(
      'every layout states the count, the link and its own sections '
      'for one state', (WidgetTester t) async {
    final AppLocalizations l = await _localizations(t);
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await _readyController(t, fake);

    for (final _Layout layout in _layouts) {
      await _pumpDashboard(t, mc, preset: layout.preset);
      final String why = 'on ${layout.name}';

      expect(layout.peers(l, 3, 3), findsWidgets,
          reason: 'the peers count is not on screen $why');
      expect(
          find.textContaining(l.statusLinked, findRichText: true), findsWidgets,
          reason: 'a ready link is not stated $why');

      if (layout.hasFeed) {
        expect(find.textContaining('hello-feed'), findsWidgets,
            reason: 'the recent feed is missing $why');
      } else {
        // Observed, not promised. No register row decides that drPop and Recon
        // carry no feed, so the absence is recorded here; wiring one into
        // either skin means changing this row.
        expect(find.textContaining('hello-feed'), findsNothing,
            reason: '${layout.name} was recorded as carrying no feed');
      }

      expect(find.text('LOCATION'),
          layout.hasLocationTile ? findsWidgets : findsNothing,
          reason: 'the location tile does not match the recorded table $why');
      if (layout.hasLocationTile) {
        // A fix exists and it came from the radio, so the tile states both the
        // position and where it came from; a coordinate with no source is the
        // thing the device-first model exists to avoid.
        expect(find.textContaining(_kLatFmt), findsWidgets,
            reason: 'the fix is not on the tile $why');
        expect(find.textContaining(l.locationSourceDevice), findsWidgets,
            reason: 'the tile does not say where the fix came from $why');
      }
    }

    await _finish(t, mc);
  });

  testWidgets('a link that drops is stated in words, not left as linked',
      (WidgetTester t) async {
    final AppLocalizations l = await _localizations(t);
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await _readyController(t, fake);

    for (final _Layout layout in _layouts) {
      await _pumpDashboard(t, mc, preset: layout.preset);
      await _makeReady(t, fake);
      expect(
          find.textContaining(l.statusLinked, findRichText: true), findsWidgets,
          reason: 'the case needs a live link to drop, on ${layout.name}');

      fake.setConnected(false);
      await _settle(t);
      expect(find.textContaining(l.statusReconnecting, findRichText: true),
          findsWidgets,
          reason: 'a dropped link is not stated on ${layout.name}');
      expect(
          find.textContaining(l.statusLinked, findRichText: true), findsNothing,
          reason: '${layout.name} still says ${l.statusLinked} after the link '
              'dropped');
    }

    await _finish(t, mc);
  });

  testWidgets('a link that never came up is stated as lost, not as linked',
      (WidgetTester t) async {
    final AppLocalizations l = await _localizations(t);
    // The transport cannot be acquired at all: the controller's own failure
    // path, which is what "no radio in reach" looks like.
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => throw StateError('no radio in reach'),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await mc.connect();
    expect(mc.state, MeshcoreConnectionState.failed);

    for (final _Layout layout in _layouts) {
      await _pumpDashboard(t, mc, preset: layout.preset);
      expect(find.textContaining(l.statusLinkLost, findRichText: true),
          findsWidgets,
          reason: 'a failed link is not stated on ${layout.name}');
      expect(
          find.textContaining(l.statusLinked, findRichText: true), findsNothing,
          reason: '${layout.name} claims a link that does not exist');
    }

    await _finish(t, mc);
  });

  testWidgets(
      'the degraded banner is above every layout, so a storage-full warning '
      'is not one preset\'s secret', (WidgetTester t) async {
    // APP-N4: one banner, built from what the surface can observe. It used to
    // be built inside the SEELE monolith, so a storage-full warning appeared on
    // one of the seven presets and on none of the others. The observation is
    // hoisted to `DashboardHost`, and this case runs every preset to prove it
    // arrived.
    final AppLocalizations l = await _localizations(t);
    final String storageFull =
        DegradedState(const <DegradedMode>{DegradedMode.storageFull}).text(l);
    expect(storageFull, isNotEmpty, reason: 'no copy to assert on');

    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await mc.connect();
    Prefs.writeFailed.value = true;
    addTearDown(() => Prefs.writeFailed.value = false);

    for (final _Layout layout in _layouts) {
      await _pumpDashboard(t, mc, preset: layout.preset);
      expect(find.text(storageFull), findsWidgets,
          reason: '${layout.name} must not hide a storage-full warning');
    }

    await _finish(t, mc);
  });
}
