// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/device_config_screen.dart';

import '../meshcore/fake_transport.dart';

/// The DEVICE read-only block on Device configuration had no test at all, and
/// the profile line is the one readout in it that carries a decision: the app
/// says a second radio profile exists and says what it costs, and offers no
/// switch, because the codec has no command that writes one.
///
/// These cases render the block in both states and in Japanese, because the
/// line is built by putting a duration into a localized template, which is the
/// shape that leaks English units into a translation.
void main() {
  const List<LocalizationsDelegate<Object>> delegates =
      <LocalizationsDelegate<Object>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  /// A `0x1B` channel datagram heard on the radio's second profile.
  Uint8List secondProfileFrame() => Uint8List.fromList(<int>[
        0x1B,
        0x20,
        kRxViaSecondaryTag,
        0x00,
        0x01,
        0xFF,
        0x0A,
        0x00,
        0x02,
        0xDE,
        0xAD,
      ]);

  /// Pumps the screen over a fake radio and returns both halves, so a case can
  /// choose whether a second-profile frame ever arrives and has to dispose the
  /// controller itself (a pending reconnect timer fails the test otherwise).
  Future<(FakeMeshcoreTransport, MeshcoreController)> pumpScreen(
    WidgetTester t, {
    required Locale locale,
  }) async {
    await t.binding.setSurfaceSize(const Size(900, 2600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: delegates,
      home: ChangeNotifierProvider<MeshcoreController>.value(
        value: mc,
        child: const DeviceConfigScreen(),
      ),
    ));
    await mc.connect();
    fake.emit(selfInfoFrame());
    fake.emit(deviceInfoFrame());
    await t.pumpAndSettle();
    return (fake, mc);
  }

  testWidgets(
      'with nothing heard on a second profile the block says so and '
      'offers no cost note', (WidgetTester t) async {
    final (FakeMeshcoreTransport _, MeshcoreController mc) =
        await pumpScreen(t, locale: const Locale('en'));
    expect(find.textContaining('second profile: nothing heard this session'),
        findsOneWidget);
    expect(find.byKey(const Key('device-radio2-note')), findsNothing,
        reason: 'the note explains a line that is otherwise absent');
    mc.dispose();
  });

  testWidgets(
      'a frame heard on the second profile states when, and states '
      'what the profile costs', (WidgetTester t) async {
    final (FakeMeshcoreTransport fake, MeshcoreController mc) =
        await pumpScreen(t, locale: const Locale('en'));
    fake.emit(secondProfileFrame());
    await t.pumpAndSettle();
    expect(find.textContaining('second profile: heard'), findsOneWidget);
    expect(find.byKey(const Key('device-radio2-note')), findsOneWidget);
    expect(
      find.textContaining("96-99 % of the MeshCore radio transmit time"),
      findsOneWidget,
      reason: 'the measured cost is the reason there is no switch here',
    );
    mc.dispose();
  });

  testWidgets('the Japanese block keeps its units in the translation',
      (WidgetTester t) async {
    final (FakeMeshcoreTransport fake, MeshcoreController mc) =
        await pumpScreen(t, locale: const Locale('ja'));
    fake.emit(secondProfileFrame());
    await t.pumpAndSettle();
    // "just now" comes from the shared relative-time ladder, so the sentence
    // carries no English unit.
    expect(find.textContaining('第2プロファイル: たった今受信'), findsOneWidget);
    expect(find.byKey(const Key('device-radio2-note')), findsOneWidget);
    mc.dispose();
  });

  testWidgets(
      'the whole readout block is translated, not just the profile '
      'line', (WidgetTester t) async {
    // The block used to be one interpolated string, so a Japanese build read
    // "firmware:", "max contacts:" and "battery:" in English. Every label is an
    // ARB key now; this case fails if any one of them is hardcoded again.
    final (FakeMeshcoreTransport fake, MeshcoreController mc) =
        await pumpScreen(t, locale: const Locale('ja'));
    fake.emit(deviceInfoFrame());
    await t.pumpAndSettle();

    for (final String label in <String>[
      'firmware:',
      'build:',
      'mfr:',
      'max contacts:',
      'channels:',
      'BLE pin:',
      'path hash:',
      'battery:',
      'airtime limit:',
      'repeat:',
    ]) {
      expect(find.textContaining(label), findsNothing,
          reason: '"$label" is an English label showing in a Japanese build');
    }
    // The values are still there, in Japanese.
    expect(find.textContaining('ファームウェア:'), findsOneWidget);
    expect(find.textContaining('最大コンタクト数:'), findsOneWidget);
    expect(find.textContaining('パスハッシュ:'), findsOneWidget);
    mc.dispose();
  });
}
