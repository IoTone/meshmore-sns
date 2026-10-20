// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_connection.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/chat_screen.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/tts/tts_controller.dart';

import '../meshcore/fake_transport.dart';
import 'chat_screen_test.dart' show FakeTtsSpeaker;

const String _mono = 'JetBrains Mono';

/// R71 — the type rule on the chat surface: under Studio the message body
/// and the sender are sans and visibly ranked, the timestamp is mono, and
/// the unexplained `«` direction glyph is gone. The terminal presets keep
/// their all-mono log.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<MeshcoreController> pump(
      WidgetTester t, MmThemePreset preset, FakeMeshcoreTransport fake) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final ThemeController tc = ThemeController();
    await tc.setPreset(preset);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => fake,
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    final TtsController tts = TtsController(speaker: FakeTtsSpeaker());
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: tc),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
        ChangeNotifierProvider<TtsController>.value(value: tts),
      ],
      child: Builder(
        builder: (BuildContext c) => MaterialApp(
          theme: c.read<ThemeController>().theme,
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: ChatScreen()),
        ),
      ),
    ));
    await mc.connect();
    fake.emit(selfInfoFrame());
    await t.pump();
    fake.emit(channelMsgFrame(text: 'MikeP: a long line of ordinary prose'));
    await t.pump();
    return mc;
  }

  String? family(WidgetTester t, Finder f) {
    final Text w = t.widget<Text>(f);
    final BuildContext ctx = t.element(f);
    return DefaultTextStyle.of(ctx).style.merge(w.style).fontFamily;
  }

  testWidgets('Studio: body and sender sans, ranked; time mono; no « glyph',
      (WidgetTester t) async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await pump(t, MmThemePreset.studio, fake);

    final Finder body = find.byKey(const ValueKey<String>('studio-msg-body'));
    final Finder sender =
        find.byKey(const ValueKey<String>('studio-msg-sender'));
    expect(body, findsOneWidget);
    expect(t.widget<Text>(body).data, 'a long line of ordinary prose');
    expect(t.widget<Text>(sender).data, 'MikeP');
    expect(family(t, body), isNot(_mono));
    expect(family(t, sender), isNot(_mono));
    // Hierarchy: the sender is smaller, heavier and dimmer than the body.
    final TextStyle b = t.widget<Text>(body).style!;
    final TextStyle s = t.widget<Text>(sender).style!;
    expect(s.fontSize!, lessThan(b.fontSize!));
    expect(s.fontWeight, FontWeight.w600);
    expect(s.color, isNot(b.color));
    // Time is machine data: mono.
    final Finder time = find.textContaining(RegExp(r'^\d\d:\d\d$'));
    expect(time, findsOneWidget);
    expect(family(t, time), _mono);
    expect(find.textContaining('«'), findsNothing);
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('SEELE keeps its all-mono terminal log and the « marker',
      (WidgetTester t) async {
    final FakeMeshcoreTransport fake = FakeMeshcoreTransport(connected: true);
    final MeshcoreController mc = await pump(t, MmThemePreset.seele, fake);
    final Finder body =
        find.text('MikeP: a long line of ordinary prose');
    expect(body, findsOneWidget);
    expect(family(t, body), _mono);
    expect(find.textContaining('«'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('studio-msg-body')), findsNothing);
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
