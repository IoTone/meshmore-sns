// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/mesh_network.dart';
import 'package:meshmore_sns_app/meshcore/mesh_network_store.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/network_detail_screen.dart';
import 'package:meshmore_sns_app/screens/networks_screen.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

const List<LocalizationsDelegate<Object>> _delegates =
    <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

MeshNetwork _private({List<NetworkMember> members = const <NetworkMember>[]}) =>
    MeshNetwork(
      id: 'n1',
      name: 'Camp',
      frequencyMhz: 912.5,
      bandwidthKhz: 62.5,
      spreadingFactor: 7,
      codingRate: 5,
      txPowerDbm: 14,
      pathHashSize: 2,
      members: members,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  late FakeMeshcoreTransport fake;
  late MeshcoreController mc;

  Future<void> pump(WidgetTester t, Widget home,
      {bool connect = true}) async {
    await t.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    fake = FakeMeshcoreTransport(connected: true);
    mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: _delegates,
      home: ChangeNotifierProvider<MeshcoreController>.value(
          value: mc, child: home),
    ));
    if (connect) {
      await mc.connect();
      fake.emit(selfInfoFrame());
    }
    await t.pumpAndSettle();
  }

  Future<void> end(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    mc.dispose();
  }

  testWidgets('empty list explains what a network is', (WidgetTester t) async {
    await pump(t, const NetworksScreen());
    expect(find.textContaining('A network is the radio settings'),
        findsOneWidget);
    await end(t);
  });

  testWidgets('creating a public network copies the preset and its hash size',
      (WidgetTester t) async {
    await pump(t, const NetworksScreen());
    await t.tap(find.byKey(const Key('network-new')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('network-name')), 'Town');
    await t.tap(find.byKey(const Key('network-preset')));
    await t.pumpAndSettle();
    await t.tap(find.text('Hungary').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('network-save')));
    await t.pumpAndSettle();

    final List<MeshNetwork> saved = await MeshNetworkStore.load();
    expect(saved, hasLength(1));
    expect(saved.single.name, 'Town');
    expect(saved.single.pathHashSize, 2,
        reason: 'Hungary lists a 2-byte hash size in the feed');
    expect(saved.single.isolatedFromPublicMesh, isFalse);
    // The list now says so in words, rather than calling it private.
    expect(find.textContaining('Shares the air with the public'),
        findsOneWidget);
    await end(t);
  });

  testWidgets('a name is required', (WidgetTester t) async {
    await pump(t, const NetworkEditScreen());
    await t.tap(find.byKey(const Key('network-save')));
    await t.pumpAndSettle();
    expect(find.text('Give the network a name.'), findsOneWidget);
    expect(await MeshNetworkStore.load(), isEmpty);
    await end(t);
  });

  testWidgets('a private frequency is saved, and is isolated',
      (WidgetTester t) async {
    await pump(t, const NetworkEditScreen());
    await t.enterText(find.byKey(const Key('network-name')), 'Camp');
    await t.tap(find.byKey(const Key('network-private')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('network-frequency')), '912.5');
    await t.tap(find.byKey(const Key('network-hash')).hitTestable().first);
    await t.tap(find.text('3'));
    await t.tap(find.byKey(const Key('network-save')));
    await t.pumpAndSettle();

    final MeshNetwork n = (await MeshNetworkStore.load()).single;
    expect(n.frequencyMhz, 912.5);
    expect(n.pathHashSize, 3);
    expect(n.isolatedFromPublicMesh, isTrue);
    await end(t);
  });

  testWidgets('a "private" frequency on a public preset is refused',
      (WidgetTester t) async {
    await pump(t, const NetworkEditScreen());
    await t.enterText(find.byKey(const Key('network-name')), 'Fake');
    await t.tap(find.byKey(const Key('network-private')));
    await t.pumpAndSettle();
    // 1 kHz off USA/Canada: the same channel to a receiver.
    await t.enterText(find.byKey(const Key('network-frequency')), '910.526');
    await t.tap(find.byKey(const Key('network-save')));
    await t.pumpAndSettle();
    expect(find.textContaining('belong to the public preset'), findsOneWidget);
    expect(await MeshNetworkStore.load(), isEmpty);
    await end(t);
  });

  testWidgets('apply asks first; cancel sends nothing',
      (WidgetTester t) async {
    await MeshNetworkStore.save(<MeshNetwork>[_private()]);
    await pump(t, const NetworkDetailScreen(id: 'n1'));
    final int before = fake.sent.length;

    await t.tap(find.byKey(const Key('network-apply')));
    await t.pumpAndSettle();
    expect(find.text('Apply Camp?'), findsOneWidget);
    expect(find.textContaining('stop hearing the public mesh'),
        findsOneWidget,
        reason: 'an isolated network must warn that the radio leaves the mesh');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(fake.sent.length, before);
    await end(t);
  });

  testWidgets('confirming apply writes exactly the network\'s wire frames',
      (WidgetTester t) async {
    final MeshNetwork n = _private();
    await MeshNetworkStore.save(<MeshNetwork>[n]);
    await pump(t, const NetworkDetailScreen(id: 'n1'));
    final int before = fake.sent.length;

    await t.tap(find.byKey(const Key('network-apply')));
    await t.pumpAndSettle();
    await t.tap(find.text('Apply').last);
    await t.pumpAndSettle();

    final List<Uint8List> wrote = fake.sent.sublist(before);
    final List<Uint8List> want = n.framesToApply();
    expect(wrote, hasLength(want.length));
    for (int i = 0; i < want.length; i++) {
      expect(wrote[i], want[i], reason: 'frame $i');
    }
    // Spot-check the bytes that matter, independent of framesToApply():
    // opcode 0x0B radio params (912500 kHz LE), 0x0C tx power, 0x3D hash.
    expect(wrote[0][0], 0x0B);
    expect(ByteData.sublistView(wrote[0]).getUint32(1, Endian.little), 912500);
    expect(wrote[1], <int>[0x0C, 14]);
    expect(wrote[2], <int>[0x3D, 0, 1], reason: 'size 2 is wire mode 1');
    await end(t);
  });

  testWidgets('apply is disabled with no radio', (WidgetTester t) async {
    await MeshNetworkStore.save(<MeshNetwork>[_private()]);
    await pump(t, const NetworkDetailScreen(id: 'n1'), connect: false);
    expect(
        t.widget<FilledButton>(find.byKey(const Key('network-apply'))).onPressed,
        isNull);
    expect(find.text('Connect a radio to apply.'), findsOneWidget);
    await end(t);
  });

  testWidgets('a network on a public tuple warns it is not private',
      (WidgetTester t) async {
    await MeshNetworkStore.save(<MeshNetwork>[
      MeshNetwork(
        id: 'n1',
        name: 'Pretend',
        frequencyMhz: 910.525,
        bandwidthKhz: 62.5,
        spreadingFactor: 7,
        codingRate: 5,
      ),
    ]);
    await pump(t, const NetworkDetailScreen(id: 'n1'));
    expect(
        t.widget<Text>(find.byKey(const Key('network-reach'))).data,
        contains('does not separate radios'));
    await end(t);
  });

  testWidgets('members come from known contacts and can be removed',
      (WidgetTester t) async {
    await MeshNetworkStore.save(<MeshNetwork>[_private()]);
    await pump(t, const NetworkDetailScreen(id: 'n1'));
    fake.emit(contactFrame(name: 'Alice', firstPubByte: 70));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('network-add-member')));
    await t.pumpAndSettle();
    await t.tap(find.text('Alice'));
    await t.pumpAndSettle();

    MeshNetwork saved = (await MeshNetworkStore.load()).single;
    expect(saved.members.map((NetworkMember m) => m.label), <String>['Alice']);
    expect(saved.members.single.publicKeyHex, hasLength(64));
    expect(find.text('Members (1)'), findsOneWidget);

    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    saved = (await MeshNetworkStore.load()).single;
    expect(saved.members, isEmpty);
    await end(t);
  });

  testWidgets('delete asks first, and removes only the saved network',
      (WidgetTester t) async {
    await MeshNetworkStore.save(<MeshNetwork>[_private()]);
    await pump(t, const NetworkDetailScreen(id: 'n1'));
    final int before = fake.sent.length;

    await t.tap(find.byKey(const Key('network-delete')));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(await MeshNetworkStore.load(), hasLength(1));

    await t.tap(find.byKey(const Key('network-delete')));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete').last);
    await t.pumpAndSettle();
    expect(await MeshNetworkStore.load(), isEmpty);
    expect(fake.sent.length, before, reason: 'delete must not touch the radio');
    await end(t);
  });
}
