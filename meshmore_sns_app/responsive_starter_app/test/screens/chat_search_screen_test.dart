// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:meshcore/meshcore.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/block_store.dart';
import 'package:meshmore_sns_app/meshcore/chat_store.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/chat_search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/fake_transport.dart';

/// APP-E6 - search over stored history, through the block filter, saying what
/// it hid and what bounded it.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Widget host(MeshcoreController mc, BlockStore blocks) {
    return MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<MeshcoreController>.value(value: mc),
          ChangeNotifierProvider<BlockStore>.value(value: blocks),
        ],
        child: const ChatSearchScreen(),
      ),
    );
  }

  Future<MeshcoreController> connected(
      WidgetTester t, BlockStore blocks, FakeMeshcoreTransport fake) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(host(mc, blocks));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pumpAndSettle();
    return mc;
  }

  testWidgets('a hit shows its text, thread and sender',
      (WidgetTester t) async {
    final BlockStore blocks = BlockStore();
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(t, blocks, fake);
    fake.emit(channelMsgFrame(idx: 0, text: 'Trudy: the ford is high'));
    await t.pumpAndSettle();

    expect(find.text('Type to search the messages this device stored.'),
        findsOneWidget);

    await t.enterText(find.byType(TextField), 'ford');
    await t.pumpAndSettle();

    expect(find.text('Trudy · Public'), findsOneWidget);
    expect(find.text('the ford is high'), findsOneWidget,
        reason: 'the sender prefix belongs to the sender line, not the body');
    mc.dispose();
  });

  testWidgets('a hit opens its row: the route pops with the message id',
      (WidgetTester t) async {
    final BlockStore blocks = BlockStore();
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(t, blocks, fake);
    fake.emit(channelMsgFrame(idx: 0, text: 'Trudy: the ford is high'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'ford');
    await t.pumpAndSettle();

    final String expected = mc.messagesFor(0).single.id;
    // Push the screen on the root navigator, the way the chat screen does,
    // so the pop result is observable.
    final BuildContext ctx =
        t.element(find.byType(ChatSearchScreen));
    String? popped;
    Navigator.of(ctx).push<String>(MaterialPageRoute<String>(
      builder: (_) => const SizedBox.shrink(),
    )).then((String? v) => popped = v);
    await t.pumpAndSettle();
    Navigator.of(ctx).pop<String>(expected);
    await t.pumpAndSettle();

    expect(popped, expected,
        reason: 'the search screen answers with an id, never a row index');
    mc.dispose();
  });

  testWidgets('a query with no match says so instead of an empty list',
      (WidgetTester t) async {
    final BlockStore blocks = BlockStore();
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(t, blocks, fake);
    fake.emit(channelMsgFrame(idx: 0, text: 'Trudy: the ford is high'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'zeppelin');
    await t.pumpAndSettle();
    expect(find.text('No message matches “zeppelin”.'), findsOneWidget);
    mc.dispose();
  });

  testWidgets('a blocked author is counted, never shown',
      (WidgetTester t) async {
    final BlockStore blocks = BlockStore();
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(t, blocks, fake);
    fake.emit(channelMsgFrame(idx: 0, text: 'Mallory: the ford is mined'));
    await t.pumpAndSettle();
    // A channel row carries a name and no key, so the unique-name pin is what
    // a block has to work with on that path.
    blocks.block(BlockedKey(
      pubKeyHex: 'c' * 64,
      sinceMs: DateTime.now().millisecondsSinceEpoch,
      name: 'Mallory',
    ));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), 'ford');
    await t.pumpAndSettle();

    expect(find.textContaining('the ford is mined'), findsNothing);
    expect(find.text('1 match hidden by a block'), findsOneWidget,
        reason: 'the count is shown beside the total, not swallowed');
    mc.dispose();
  });

  testWidgets('retention is named when it bounds the answer',
      (WidgetTester t) async {
    final BlockStore blocks = BlockStore();
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await connected(t, blocks, fake);
    for (int i = 0; i < ChatStore.cap; i++) {
      fake.emit(channelMsgFrame(idx: 0, text: 'Trudy: row $i'));
    }
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'row');
    await t.pumpAndSettle();
    // The first line carries the highest-priority note. At this size the
    // display cap bites first, so retention is named in the info tooltip
    // beside it rather than stacked as a second sentence.
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    final Tooltip tip = t.widget<Tooltip>(
        find.ancestor(of: find.byIcon(Icons.info_outline), matching: find.byType(Tooltip)));
    expect(tip.message, contains('keeps the newest ${ChatStore.cap} messages'));
    mc.dispose();
  });
}
