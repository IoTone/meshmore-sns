// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:meshcore/meshcore.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/channel_create_sheet.dart';

import '../meshcore/fake_transport.dart';

/// Making a channel, as a reader does it: name it, say who may read it, done.
///
/// The only way to make one used to be a list of numbered slots with "Set" on
/// each, opening a dialog that asked for a name and then one of four key
/// sources — and *defaulted to the public key*, so naming a channel and pressing
/// save produced a channel every radio in range could read, with nothing on
/// screen saying so. These cases pin the two things that fix it: the choice is
/// stated as a consequence, and the safe answer is the default.
Future<MeshcoreController> _ready(FakeMeshcoreTransport fake) async {
  final MeshcoreController ctrl = MeshcoreController(
    transportFactory: () async => fake,
    connection:
        MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
  );
  await ctrl.connect();
  fake.emit(selfInfoFrame());
  return ctrl;
}

Widget _host(MeshcoreController mc) => MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
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
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    ChannelCreateSheet.show(ctx, controller: mc),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester t, MeshcoreController mc) async {
  await t.pumpWidget(_host(mc));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a name alone makes a channel only its own name can open',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await _ready(fake);
    fake.emit(channelInfoFrame(idx: 0, name: 'Public'));
    await t.pumpAndSettle();

    await _open(t, mc);
    await t.enterText(
        find.byKey(const ValueKey<String>('channel-create-name')), 'basecamp');
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('channel-create-save')));
    await t.pumpAndSettle();

    // The safe answer is the default: the key comes from the name, not from the
    // well-known public key.
    expect(mc.channels.any((MapEntry<int, String> e) => e.value == '#basecamp'),
        isTrue,
        reason: 'the channel was not created, or not under its canonical name');
    final List<int> psk = mc.channelPsk(1)!;
    expect(psk, isNot(equals(kPublicChannelPsk)),
        reason: 'a named channel was quietly keyed with the public key');
    expect(psk,
        equals(MeshcoreChannelCrypto.channelPskFromHashtag('basecamp')));
    // It lands in the first free slot and is the one being read.
    expect(mc.channels.any((MapEntry<int, String> e) => e.key == 1), isTrue);
    expect(mc.activeChannel, 1,
        reason: 'a channel just created and not selected is one to go looking for');
    expect(fake.sent.any((List<int> f) => f.isNotEmpty && f[0] == 0x20), isTrue,
        reason: 'CMD_SET_CHANNEL was never sent');
    mc.dispose();
  });

  testWidgets('the public key is reachable, but only by asking for it',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await _ready(fake);
    await t.pumpWidget(_host(mc));
    fake.emit(channelInfoFrame(idx: 0, name: 'Public'));
    await t.pumpAndSettle();
    await _open(t, mc);

    await t.tap(find.byKey(const ValueKey<String>('channel-create-public')));
    await t.pump();
    await t.enterText(
        find.byKey(const ValueKey<String>('channel-create-name')), 'Town Hall');
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('channel-create-save')));
    await t.pumpAndSettle();

    // A public-keyed channel keeps the name as typed: there is no `#` form to
    // canonicalise, and prefixing one would claim a derived key it does not have.
    expect(mc.channels.any((MapEntry<int, String> e) => e.value == 'Town Hall'),
        isTrue);
    expect(mc.channelPsk(1), equals(kPublicChannelPsk));
    mc.dispose();
  });

  testWidgets('an empty name is refused, and nothing is written',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await _ready(fake);
    await t.pumpWidget(_host(mc));
    fake.emit(channelInfoFrame(idx: 0, name: 'Public'));
    await t.pumpAndSettle();
    await _open(t, mc);

    await t.tap(find.byKey(const ValueKey<String>('channel-create-save')));
    await t.pumpAndSettle();
    expect(find.text('New channel'), findsOneWidget,
        reason: 'the sheet stays open so the reader can fix the name');
    expect(fake.sent.any((List<int> f) => f.isNotEmpty && f[0] == 0x20), isFalse,
        reason: 'a nameless channel was sent to the radio');
    mc.dispose();
  });

  testWidgets('a radio with no free slot says so instead of failing silently',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await _ready(fake);
    await t.pumpWidget(_host(mc));
    // Every slot the smallest board has, occupied.
    for (int i = 0; i < 4; i++) {
      fake.emit(channelInfoFrame(idx: i, name: 'ch$i'));
    }
    await t.pumpAndSettle();
    await _open(t, mc);

    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(ChannelCreateSheet)));
    expect(find.text(l.channelCreateNoSlot), findsWidgets);
    final MmActionProbe save =
        MmActionProbe(find.byKey(const ValueKey<String>('channel-create-save')));
    expect(save.enabled(t), isFalse,
        reason: 'a create button that can only fail is worse than a disabled one');
    mc.dispose();
  });

  testWidgets('closing the sheet puts the keyboard away with it',
      (WidgetTester t) async {
    // The name field is autofocused, so the keyboard is up over the thread the
    // reader is dropped into. The handset showed half a screen of keyboard with
    // nothing focused behind it after this sheet closed.
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await _ready(fake);
    await t.pumpWidget(_host(mc));
    fake.emit(channelInfoFrame(idx: 0, name: 'Public'));
    await t.pumpAndSettle();
    await _open(t, mc);
    await t.enterText(
        find.byKey(const ValueKey<String>('channel-create-name')), 'basecamp');
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('channel-create-save')));
    await t.pumpAndSettle();
    // No field left behind, so nothing can hold the keyboard open: the sheet is
    // gone, and its name field was the only text field on screen.
    expect(find.byKey(const ValueKey<String>('channel-create-sheet')),
        findsNothing);
    expect(find.byType(EditableText), findsNothing,
        reason: 'a field nobody is looking at still holds the keyboard open');
    mc.dispose();
  });

  testWidgets('a name already in the list is refused before the tap',
      (WidgetTester t) async {
    // Two channels with one name and one derived key are the same conversation
    // split across two rows, and nothing on screen says which row is which.
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await _ready(fake);
    await t.pumpWidget(_host(mc));
    fake.emit(channelInfoFrame(idx: 0, name: 'Public'));
    fake.emit(channelInfoFrame(idx: 1, name: '#basecamp'));
    await t.pumpAndSettle();
    await _open(t, mc);

    // "basecamp" and "#basecamp" are one name, in the form the key uses.
    await t.enterText(
        find.byKey(const ValueKey<String>('channel-create-name')), 'basecamp');
    await t.pump();
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(ChannelCreateSheet)));
    expect(find.text(l.channelCreateExists('#basecamp')), findsOneWidget);
    expect(MmActionProbe(find.byKey(const ValueKey<String>('channel-create-save')))
        .enabled(t), isFalse);
    mc.dispose();
  });

  testWidgets('the sheet holds a 320 dp phone at 200 % text',
      (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await _ready(fake);
    await t.pumpWidget(_host(mc));
    fake.emit(channelInfoFrame(idx: 0, name: 'Public'));
    await t.pumpAndSettle();
    await _open(t, mc);
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey<String>('channel-create-name')),
        findsOneWidget);
    mc.dispose();
  });
}

/// Reads whether an `MmAction` is pressable without importing the widget.
///
/// The button's contract is "no onPressed, no pressable" — the same rule the
/// disabled state is drawn from — so the probe asks the `IconButton`/`InkWell`
/// the action builds rather than reaching for the action's own field.
class MmActionProbe {
  MmActionProbe(this.finder);
  final Finder finder;

  bool enabled(WidgetTester t) {
    final Iterable<Element> found = finder.evaluate();
    if (found.isEmpty) return false;
    final Widget w = found.first.widget;
    final Object? handler = switch (w) {
      final IconButton b => b.onPressed,
      final InkWell b => b.onTap,
      final TextButton b => b.onPressed,
      _ => null,
    };
    return handler != null;
  }
}
