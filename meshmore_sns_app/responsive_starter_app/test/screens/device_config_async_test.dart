// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/device_config_screen.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

/// A transport whose writes can be held, to stand in for a slow BLE write.
class _GatedTransport extends FakeMeshcoreTransport {
  _GatedTransport() : super(connected: true);
  Completer<void>? gate;

  @override
  Future<void> send(Uint8List frame) async {
    final Completer<void>? g = gate;
    if (g != null) await g.future;
    return super.send(frame);
  }
}

void main() {
  // Every Device configuration action awaits a BLE write and then toasts.
  // Leaving the screen while the write is in flight used to toast through
  // the dead State's context (`ScaffoldMessenger.of(context)` on a
  // deactivated element). Diagnostics' own `_toast` already had the guard.
  testWidgets('a toast after the screen is gone does not throw',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final _GatedTransport fake = _GatedTransport();
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ChangeNotifierProvider<MeshcoreController>.value(
        value: mc,
        child: const DeviceConfigScreen(),
      ),
    ));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();

    await t.enterText(
        find.widgetWithText(TextField, 'Advert name'), 'gone-soon');
    fake.gate = Completer<void>();
    await t.tap(find.text('Set name'));
    await t.pump();

    // The user leaves while the write is still in flight.
    await t.pumpWidget(const SizedBox.shrink());
    fake.gate!.complete();
    await t.pump();
    await t.pump();

    expect(t.takeException(), isNull);
    mc.dispose();
  });
}
