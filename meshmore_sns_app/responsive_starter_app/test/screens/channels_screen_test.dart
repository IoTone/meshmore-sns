// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/bot/bot_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/channels_screen.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

Future<MeshcoreController> _ready(FakeMeshcoreTransport fake) async {
  final MeshcoreController ctrl = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await ctrl.connect();
  fake.emit(selfInfoFrame()); // → ready
  return ctrl;
}

// Provider sits *above* MaterialApp so dialogs (mounted in the root
// navigator) can also read the controller — matches the real app's
// MultiProvider-over-MaterialApp structure.
Widget _host(MeshcoreController mc) => MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        // The edit dialog embeds R59's BotSection.
        ChangeNotifierProvider<BotController>(create: (_) => BotController()),
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
        home: const ChannelsScreen(),
      ),
    );

void main() {
  testWidgets('the slot list is the radio\'s own count, not a hardcoded four',
      (WidgetTester t) async {
    // The screen exposed four slots whatever the board held, so a radio with
    // eight or forty had most of its channels unreachable from the only screen
    // that writes them. DEVICE_INFO reports max_group_channels, and the
    // controller's probe walks exactly that many.
    await t.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await _ready(fake);
    await t.pumpWidget(_host(mc));
    await t.pumpAndSettle();

    // Before the radio answers, the smallest board's four. Slot 0 is the
    // controller's seeded Public channel, so three of the four read empty.
    expect(find.text('— empty —'), findsNWidgets(3));

    fake.emit(deviceInfoFrame(maxChannels: 8));
    await t.pumpAndSettle();
    expect(find.text('— empty —'), findsNWidgets(7),
        reason: 'a radio that reports eight slots must show eight, one of '
            'which carries the Public channel');
    mc.dispose();
  });

  testWidgets(
      'a channel the radio lists stays reachable even if the count '
      'disagrees', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await _ready(fake);
    await t.pumpWidget(_host(mc));
    fake.emit(channelInfoFrame(idx: 3, name: 'Field'));
    fake.emit(deviceInfoFrame(maxChannels: 2));
    await t.pumpAndSettle();
    expect(find.text('Field'), findsOneWidget,
        reason: 'a slot that exists must not be hidden by a smaller count');
    mc.dispose();
  });

  testWidgets('edit slot via #hashtag sends SET_CHANNEL + lists it',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await _ready(fake);
    await t.pumpWidget(_host(mc));
    fake.emit(channelInfoFrame(idx: 0, name: 'Public'));
    await t.pumpAndSettle();

    expect(find.text('Public'), findsOneWidget); // slot 0
    expect(find.text('— empty —'), findsWidgets); // empty slots

    // Open the editor for slot 1 (empty → "Set").
    await t.tap(find.text('Set').first);
    await t.pumpAndSettle();
    expect(find.text('Channel 1'), findsOneWidget);

    await t.tap(find.text('#tag'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'e.g. #mygroup'), '#ops');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    // CMD_SET_CHANNEL opcode is 0x20.
    expect(fake.sent.any((f) => f.isNotEmpty && f[0] == 0x20), isTrue);
    // Name defaults to the hashtag itself; optimistic list update.
    expect(find.text('#ops'), findsOneWidget);
    mc.dispose();
  });

  testWidgets('a tag typed without # saves the canonical name and key',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await _ready(fake);
    await t.pumpWidget(_host(mc));
    fake.emit(channelInfoFrame(idx: 0, name: 'Public'));
    await t.pumpAndSettle();

    await t.tap(find.text('Set').first);
    await t.pumpAndSettle();
    await t.tap(find.text('#tag'));
    await t.pumpAndSettle();
    // No leading #: the firmware's hashtag channel is sha256("#name"), so
    // the screen must canonicalise rather than derive a second key.
    await t.enterText(
        find.widgetWithText(TextField, 'e.g. #mygroup'), 'emergency');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    // The name the radio is given is the canonical one, so the slot reads
    // back as the channel whose key it actually holds.
    expect(find.text('#emergency'), findsOneWidget);
    final Uint8List setChannel =
        fake.sent.firstWhere((Uint8List f) => f.isNotEmpty && f[0] == 0x20);
    expect(setChannel, containsAllInOrder('#emergency'.codeUnits));
    mc.dispose();
  });

  testWidgets('tapping a configured slot sets it active', (t) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await _ready(fake);
    await t.pumpWidget(_host(mc));
    fake.emit(channelInfoFrame(idx: 1, name: 'Ops'));
    await t.pumpAndSettle();

    expect(mc.activeChannel, 0);
    await t.tap(find.text('Ops'));
    await t.pumpAndSettle();
    expect(mc.activeChannel, 1);
    mc.dispose();
  });

  testWidgets('W2 the channel screen takes its text sizes from the ladder',
      (t) async {
    // Fourteen size literals became roles here: the two help blocks are
    // sizeBody (12), the slot's DEFAULT badge is sizeMicro (10), key
    // readouts are sizeSm/sizeBody in the mono face. Under SEELE the scale
    // is 1.0, so the header help and the badge keep the numbers they had.
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController ctrl = await _ready(fake);
    final MmType type = mmSkinFor(MmThemePreset.seele).type;
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_host(ctrl));
    await t.pump();

    // The rules moved behind one info action: the list is the answer, and the
    // two paragraphs that used to sit above it are one tap away.
    await t.tap(find.byKey(const ValueKey<String>('channels-info')));
    await t.pumpAndSettle();

    Text find1(String key) => t.widget<Text>(find.text(key));
    expect(
        find1('Channel 0 is the shared public one. A private group needs the '
                'same channel number, name and key on every radio.')
            .style
            ?.fontSize,
        type.sizeBody);
    expect(
        find1('Channel 0 is the shared public one. A private group needs the '
                'same channel number, name and key on every radio.')
            .style
            ?.fontSize,
        12);
    // The encryption panel is the second guaranteed block: 12 -> sizeBody
    // with the mono face on the key readouts it carries.
    expect(
        find1("Channel 0's key is public. Other channels use the key you set.")
            .style
            ?.fontSize,
        type.sizeBody);
    expect(
        find1("Channel 0's key is public. Other channels use the key you set.")
            .style
            ?.fontSize,
        12);

    ctrl.dispose();
  });
}
