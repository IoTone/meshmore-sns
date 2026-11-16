// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/docs_hub_screen.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';
import 'package:meshcore/meshcore.dart';

/// R74 — the Studio type rule: *words sans, machine data mono*.
///
/// Enforceable here: (1) which skins turn words sans (`MmType.wordsMono`);
/// (2) prose surfaces resolve sans under Studio and the skin's mono under
/// SEELE (docs hub as the probe); (3) a **ratchet** on literals: no file may
/// name a font family directly, so a new surface cannot pick a face of its
/// own — it reads `skin.type.monoFamily` like every other one does, and the
/// per-preset mapping in `mm_skin.dart` stays the only place a face is
/// chosen. NOT enforceable by test: whether a given run of text is data or
/// prose; that is a judgement recorded in `meshmore-sns-UX-spec.md`
/// ("Type rule").
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('the tool skins turn words sans; the others keep their mono', () {
    // R115 — the tool language is one rule for both grounds: words in the UI
    // face, mono for machine data. Every other skin sets words in mono by
    // design, which is that skin's character.
    for (final MmThemePreset p in MmThemePreset.values) {
      final MmType t = mmSkinFor(p).type;
      if (p == MmThemePreset.studio) {
        expect(t.wordsMono, isNull);
      } else {
        expect(t.wordsMono, t.monoFamily, reason: '$p');
      }
    }
  });

  Future<String?> docsTitleFamily(WidgetTester t, MmThemePreset p) async {
    await t.binding.setSurfaceSize(const Size(900, 1600));
    final ThemeController tc = ThemeController();
    await tc.setPreset(p);
    final MeshcoreController mc = MeshcoreController(
      transportFactory: () async => FakeMeshcoreTransport(connected: true),
      connection:
          MeshcoreConnection(handshakeTimeout: const Duration(seconds: 5)),
    );
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: tc),
        ChangeNotifierProvider<MeshcoreController>.value(value: mc),
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
          home: const DocsHubScreen(),
        ),
      ),
    ));
    await t.pump();
    // R85: the page heading is the app bar now, so the page's own prose
    // (the subtitle) carries the skin's type system.
    // R92 shortened the subtitle; it still has to carry the skin's type.
    final Finder f = find.textContaining('Protocol, firmware, app');
    final Text w = t.widget<Text>(f);
    final String? fam = DefaultTextStyle.of(t.element(f))
        .style
        .merge(w.style)
        .fontFamily;
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
    await t.binding.setSurfaceSize(null);
    return fam;
  }

  testWidgets('docs hub prose: sans under Studio, mono under SEELE',
      (WidgetTester t) async {
    final String seeleMono =
        mmSkinFor(MmThemePreset.seele).type.monoFamily;
    expect(await docsTitleFamily(t, MmThemePreset.studio), isNot(seeleMono));
    expect(await docsTitleFamily(t, MmThemePreset.seele), seeleMono);
  });

  test('no surface names a font family of its own', () {
    // The face is the preset's, decided once in `mm_skin.dart`; a literal in a
    // widget sets one skin's face on every skin. This used to be a per-file
    // ratchet (13 literals across 9 files when the mono face was one face);
    // now the count is zero and the rule is the count, which cannot drift.
    //
    // The rule matches every spelling a face can be named by, not only the one
    // the sweep happened to remove: `fontFamily: "X"` with double quotes,
    // `fontFamilyFallback:`, and the skin's own `monoFamily:`/`displayFamily:`/
    // `headingFamily:` keys. It used to skip `lib/theme/` entirely, which is
    // where the faces are actually named — so a widget placed there could
    // hardcode one. Only `mm_skin.dart` (the one place a face is chosen) and
    // `lib/gen/` (generated from ARB) are exempt now.
    // A quoted value after any `…Family:` key, on the same line and before the
    // next comma — so `fontFamily: 'X'` and
    // `fontFamilyFallback: <String>['X']` are both literals, while
    // `fontFamily: skin.type.monoFamily` is the reference the rule asks for and
    // is not. (Proved by planting each spelling and watching this fail.)
    final RegExp lit =
        RegExp(r'''[A-Za-z]*Family\w*\s*:\s*[^,\n]*['"]''');
    final List<String> named = <String>[];
    for (final FileSystemEntity e
        in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String path = e.path.replaceAll('\\', '/');
      // `mm_skin.dart` is the one place a face is chosen; `lib/gen/` is
      // generated from ARB. Nothing else may name one.
      if (path == 'lib/theme/mm_skin.dart' || path.startsWith('lib/gen/')) {
        continue;
      }
      final int n = lit.allMatches(e.readAsStringSync()).length;
      if (n > 0) named.add('$path names $n font family literals');
    }
    expect(named, isEmpty,
        reason: 'set words with skin.type.wordsMono, data with monoFamily');
  });
}
