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

const String _mono = 'JetBrains Mono';

/// R74 — the Studio type rule: *words sans, machine data mono*.
///
/// Enforceable here: (1) which skins turn words sans (`MmType.wordsMono`);
/// (2) prose surfaces resolve sans under Studio and unchanged mono under
/// SEELE (docs hub as the probe); (3) a **ratchet**: the number of literal
/// `fontFamily: 'JetBrains Mono'` per file may not grow, so new prose
/// cannot silently be set in mono. NOT enforceable by test: whether a
/// given literal is data or prose; that is a judgement recorded in
/// `meshmore-sns-UX-spec.md` ("Type rule").
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('the tool skins turn words sans; the others keep their mono', () {
    // R115 — the tool language is one rule for both grounds: words in the UI
    // face, mono for machine data. Every other skin sets words in mono by
    // design, which is that skin's character.
    for (final MmThemePreset p in MmThemePreset.values) {
      final MmType t = mmSkinFor(p).type;
      if (<MmThemePreset>[
        MmThemePreset.studio,
        MmThemePreset.studioLight,
      ].contains(p)) {
        expect(t.wordsMono, isNull);
      } else {
        expect(t.wordsMono, t.monoFamily, reason: '$p');
        expect(t.wordsMono, _mono, reason: '$p');
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
    expect(await docsTitleFamily(t, MmThemePreset.studio), isNot(_mono));
    expect(await docsTitleFamily(t, MmThemePreset.seele), _mono);
  });

  test('literal JetBrains Mono per file may not grow (ratchet)', () {
    // Baseline after R74. Files of the six older presets' own dashboards
    // are exempt (their identity is mono). Lower a number when a literal
    // is removed; never raise one.
    const Map<String, int> baseline = <String, int>{
      'lib/bot/bot_scope_config.dart': 1,
      'lib/bot/bot_section.dart': 1,
      'lib/bot/bot_tag.dart': 1,
      'lib/screens/battery_screen.dart': 3,
      'lib/screens/dashboard_screen.dart': 7,
      'lib/screens/dashboards/my_pubkey_line.dart': 1,
      'lib/screens/device_contacts_screen.dart': 1,
      'lib/screens/device_manager_sheet.dart': 3,
      'lib/screens/diagnostics_screen.dart': 3,
      'lib/screens/dm_screen.dart': 1,
      'lib/screens/doc_reader_screen.dart': 1,
      'lib/screens/elevation_profile_view.dart': 8,
      'lib/screens/fabric_survey_view.dart': 1,
      'lib/screens/globe_view.dart': 3,
      'lib/screens/location_settings_screen.dart': 1,
      'lib/screens/meshbook_view.dart': 3,
      'lib/screens/mesh_tree_view.dart': 3,
      'lib/screens/sns_cells_view.dart': 2,
      'lib/screens/voice_settings_screen.dart': 2,
      'lib/splash/branded_splash_screen.dart': 1,
    };
    const Set<String> exempt = <String>{
      'lib/screens/dashboards/hyperlocal_dashboard.dart',
      'lib/screens/dashboards/aghud_dashboard.dart',
      'lib/screens/dashboards/drpop_dashboard.dart',
      'lib/screens/dashboards/recon_dashboard.dart',
      'lib/screens/dashboards/nerv_dashboard.dart',
      'lib/shell/boot_overlay.dart',
      'lib/licenses/asset_licenses.dart',
    };
    final RegExp lit = RegExp(r"fontFamily:\s*'JetBrains Mono'");
    final List<String> grew = <String>[];
    for (final FileSystemEntity e
        in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String path = e.path.replaceAll('\\', '/');
      if (path.startsWith('lib/gen/') ||
          path.startsWith('lib/theme/') ||
          exempt.contains(path)) {
        continue;
      }
      final int n = lit.allMatches(e.readAsStringSync()).length;
      if (n > (baseline[path] ?? 0)) {
        grew.add('$path has $n, baseline ${baseline[path] ?? 0}');
      }
    }
    expect(grew, isEmpty,
        reason: 'set words with skin.type.wordsMono, data with monoFamily');
  });
}
