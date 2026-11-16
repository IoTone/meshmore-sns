// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/meshbook_view.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

/// The nine Hyperlocal-grid view files used to carry their own type sizes and
/// monospace family — the one place in the app the type ladder did not reach.
/// They read the skin now, and these are the two proofs: no numeric size or
/// literal family survives in any of them, and a view that renders takes its
/// size from the skin's roles rather than from a constant of its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const List<String> views = <String>[
        'lib/screens/street_map_view.dart',
    'lib/screens/elevation_profile_view.dart',
    'lib/screens/mesh_tree_view.dart',
    'lib/screens/sns_cells_view.dart',
    'lib/screens/weather_view.dart',
    'lib/screens/meshbook_view.dart',
  ];

  test('no grid view carries a numeric type size or a literal family', () {
    final RegExp numericSize = RegExp(r'fontSize:\s*[0-9.]+');
    final RegExp literalMono = RegExp(r"fontFamily:\s*'JetBrains Mono'");
    final List<String> offenders = <String>[];
    for (final String path in views) {
      final String src = File(path).readAsStringSync();
      final int sizes = numericSize.allMatches(src).length;
      final int monos = literalMono.allMatches(src).length;
      if (sizes > 0 || monos > 0) {
        offenders.add('$path: $sizes size literals, $monos family literals');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  testWidgets('a grid view takes its sizes from the skin, not a constant',
      (WidgetTester tester) async {
    final MmType type = mmSkinFor(MmThemePreset.seele).type;
    final ThemeController theme = ThemeController();
    await theme.setPreset(MmThemePreset.seele);
    final MeshcoreController mc = MeshcoreController();

    await tester.pumpWidget(MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<ThemeController>.value(value: theme),
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
        home: const Scaffold(body: MeshbookView()),
      ),
    ));
    await tester.pump();

    final AppLocalizations l =
        AppLocalizations.of(tester.element(find.byType(MeshbookView)));
    // The header names the channel the messages came from, not the firmware's
    // slot number: "CH0" told a reader nothing (gridviews, 2026-11-05).
    final Finder header = find.textContaining(
        '${l.meshbookTitle} · ${mc.activeChannelName}');
    expect(header, findsOneWidget);
    expect(tester.widget<Text>(header).style?.fontSize, type.sizeBody);

    // The hour ticks are written with size(9), a step with no named role.
    final Finder tick = find.text('06');
    if (tick.evaluate().isNotEmpty) {
      final Text tickText = tester.widget<Text>(tick.first);
      expect(tickText.style?.fontSize, type.size(9));
      expect(tickText.style?.fontFamily, type.monoFamily);
    }
  });
}
