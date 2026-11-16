// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore/meshcore.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/ble_connector.dart';
import 'package:meshmore_sns_app/meshcore/failure.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/meshcore/pair_scanner.dart';
import 'package:meshmore_sns_app/perms/permissions_service.dart';
import 'package:meshmore_sns_app/screens/pair_radio_screen.dart';

import '../meshcore/fake_transport.dart';

const List<LocalizationsDelegate<Object>> _delegates =
    <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// The platform, scripted. Every failure the flow has to explain is a method
/// on this class, so the screen's five paths cost no hardware.
class _FakeScanner implements PairScanner {
  _FakeScanner({this.now = AdapterState.on});

  AdapterState now;
  int stops = 0;

  final StreamController<AdapterState> _adapter =
      StreamController<AdapterState>.broadcast();
  final List<StreamController<List<PairHit>>> _scans =
      <StreamController<List<PairHit>>>[];

  @override
  Future<AdapterState> adapterNow() async => now;

  @override
  Stream<AdapterState> get adapter => _adapter.stream;

  @override
  Stream<List<PairHit>> scan(
      {Duration timeout = const Duration(seconds: 12)}) {
    final StreamController<List<PairHit>> c =
        StreamController<List<PairHit>>();
    _scans.add(c);
    return c.stream;
  }

  @override
  Future<void> stopScan() async => stops++;

  int get scanCount => _scans.length;

  void hear(List<PairHit> hits) {
    if (_scans.isEmpty || _scans.last.isClosed) return;
    _scans.last.add(hits);
  }

  void finishScan() {
    if (_scans.isEmpty || _scans.last.isClosed) return;
    _scans.last.close();
  }

  void adapterChanged(AdapterState s) {
    now = s;
    _adapter.add(s);
  }
}

/// Pumps until [finder] matches or the budget runs out. The screen has
/// indefinite progress indicators while it scans, so `pumpAndSettle` is not
/// available: each step is driven explicitly.
Future<void> _pumpUntil(WidgetTester t, Finder finder,
    {int max = 40}) async {
  for (int i = 0; i < max; i++) {
    await t.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
}

Future<MeshcoreController> _pumpScreen(
  WidgetTester t,
  _FakeScanner scanner, {
  PermissionsService? perms,
  FakeMeshcoreTransport? transport,
  List<int>? openFailures,
}) async {
  int opens = 0;
  final MeshcoreController ctrl = MeshcoreController(
    transportFactory: () async {
      opens++;
      if (openFailures != null && opens <= openFailures.first) {
        throw BleConnectException(FailureCause.pairingFailed);
      }
      return transport ?? FakeMeshcoreTransport(connected: true);
    },
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  addTearDown(ctrl.dispose);
  await t.pumpWidget(MultiProvider(
    providers: <SingleChildWidget>[
      ChangeNotifierProvider<MeshcoreController>.value(value: ctrl),
      Provider<PermissionsService>.value(
          value: perms ?? NoopPermissionsService()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: _delegates,
      home: PairRadioScreen(
        scanner: scanner,
        scanWindow: const Duration(milliseconds: 50),
      ),
    ),
  ));
  // `_begin` runs from a post-frame callback and then awaits the permission
  // check and the adapter; each await is one pump.
  for (int i = 0; i < 4; i++) {
    await t.pump(Duration.zero);
  }
  return ctrl;
}

void main() {
  testWidgets('a refused permission is explained, not shown as an empty list',
      (WidgetTester t) async {
    final _FakeScanner scanner = _FakeScanner();
    await _pumpScreen(t, scanner,
        perms: NoopPermissionsService(ble: false));

    expect(find.text('Bluetooth permission'), findsOneWidget,
        reason: 'the first step is the permission, before any scan');
    await t.tap(find.text('Allow Bluetooth'));
    await _pumpUntil(
        t, find.textContaining('Bluetooth permission was refused'));
    expect(
      find.textContaining('Bluetooth permission was refused'),
      findsOneWidget,
      reason: 'a refused prompt has to say what to do; it cannot look like a '
          'scan that found nothing',
    );
    expect(scanner.scanCount, 0,
        reason: 'nothing may scan before the permission is held');
  });

  testWidgets('an adapter that is off waits and then continues by itself',
      (WidgetTester t) async {
    final _FakeScanner scanner = _FakeScanner(now: AdapterState.off);
    await _pumpScreen(t, scanner);

    expect(find.text('Bluetooth is off'), findsOneWidget);
    expect(scanner.scanCount, 0);

    // The user walks to the OS and switches it on; the flow must not make
    // them come back to a button that may already be off screen.
    scanner.adapterChanged(AdapterState.on);
    await _pumpUntil(t, find.text('Looking for MeshCore radios'));
    expect(find.text('Looking for MeshCore radios'), findsOneWidget);
    expect(scanner.scanCount, 1);
  });

  testWidgets('a scan that hears nothing says so and offers another',
      (WidgetTester t) async {
    final _FakeScanner scanner = _FakeScanner();
    await _pumpScreen(t, scanner);
    await _pumpUntil(t, find.text('Looking for MeshCore radios'));

    scanner.hear(const <PairHit>[]);
    scanner.finishScan();
    await _pumpUntil(t, find.textContaining('No MeshCore radio answered'));

    expect(find.textContaining('No MeshCore radio answered'), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget,
        reason: 'an empty result is a state with an action, not a dead end');
  });

  testWidgets('picking a radio ends on the radio that actually answered',
      (WidgetTester t) async {
    final _FakeScanner scanner = _FakeScanner();
    final FakeMeshcoreTransport transport =
        FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl =
        await _pumpScreen(t, scanner, transport: transport);
    await _pumpUntil(t, find.text('Looking for MeshCore radios'));

    scanner.hear(const <PairHit>[
      PairHit(remoteId: 'AA:BB:CC', name: 'MeshCore-Ridge', rssi: -61),
    ]);
    await _pumpUntil(t, find.text('MeshCore-Ridge'));
    expect(find.text('MeshCore-Ridge'), findsOneWidget);

    await t.tap(find.text('MeshCore-Ridge'));
    // The open attaches the transport; the handshake proves the link.
    for (int i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
      if (transport.sent.isNotEmpty) break;
    }
    expect(transport.sent, isNotEmpty,
        reason: 'the flow must open the radio it was asked to open');
    transport.emit(selfInfoFrame());
    await _pumpUntil(t, find.text('MeshCore radio connected'));

    expect(find.text('MeshCore radio connected'), findsOneWidget);
    expect(find.textContaining('answered'), findsOneWidget,
        reason: 'the confirmation names the radio that answered, so the user '
            'knows which one they got');
    expect(scanner.stops, greaterThan(0),
        reason: 'the scan stops before an open, not after it');

    // A ready radio owns poll timers; parking the link keeps the harness free
    // of a pending timer, which is a test artefact and not a screen fault.
    await ctrl.disconnect();
    await t.pump();
    // The post-handshake drain watchdog is a 20 s controller timer; let it
    // lapse here rather than leave the harness reporting it as the screen's.
    await t.pump(const Duration(seconds: 21));
  });

  testWidgets('an open that fails names the reason and returns to the list',
      (WidgetTester t) async {
    final _FakeScanner scanner = _FakeScanner();
    final MeshcoreController ctrl =
        await _pumpScreen(t, scanner, openFailures: <int>[1]);
    await _pumpUntil(t, find.text('Looking for MeshCore radios'));

    scanner.hear(const <PairHit>[
      PairHit(remoteId: 'AA:BB:CC', name: 'MeshCore-Ridge', rssi: -61),
    ]);
    await _pumpUntil(t, find.text('MeshCore-Ridge'));
    await t.tap(find.text('MeshCore-Ridge'));
    await _pumpUntil(t, find.textContaining('pairing did not complete'));

    expect(find.textContaining('pairing did not complete'), findsOneWidget,
        reason: 'a failed open is the catalogue\'s pairing cause, with its '
            'next action');
    expect(find.text('MeshCore-Ridge'), findsOneWidget,
        reason: 'the list comes back so the user can pick another radio');

    // The failed open arms the reconnect backoff; dropping the link cancels it.
    await ctrl.disconnect();
    await t.pump();
    // The post-handshake drain watchdog is a 20 s controller timer; let it
    // lapse here rather than leave the harness reporting it as the screen's.
    await t.pump(const Duration(seconds: 21));
  });

  testWidgets('leaving mid-scan stops the scan', (WidgetTester t) async {
    final _FakeScanner scanner = _FakeScanner();
    await _pumpScreen(t, scanner);
    await _pumpUntil(t, find.text('Looking for MeshCore radios'));
    expect(scanner.scanCount, 1);
    expect(scanner.stops, 0);

    // Replace the tree: the screen is disposed while its scan is open, which
    // is what a back gesture does.
    await t.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await t.pump(Duration.zero);

    expect(scanner.stops, greaterThan(0),
        reason: 'a scan that outlives its screen burns the radio; the screen '
            'stops it on the way out');
  });
}
