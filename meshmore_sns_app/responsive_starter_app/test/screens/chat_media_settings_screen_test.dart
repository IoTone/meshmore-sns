// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/media/aeic_installer.dart';
import 'package:meshmore_sns_app/screens/chat_media_settings_screen.dart';
import 'package:meshmore_sns_app/theme/mm_skin.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';
import 'package:meshmore_sns_app/ui/mm_components.dart';

/// Chat & photos: one left margin for the whole page.
///
/// The page was assembled from rows written for App settings, where the list
/// supplies the page edge and every row carries `contentPadding: zero`. On its
/// own screen the list had no horizontal padding, so the rows sat on the
/// physical edge, the retention row kept ListTile's default 16 dp and the note
/// at the bottom added a third, which is the ragged margin the owner reported.
///
/// These cases pin the three numbers that make the margin one number: the list
/// owns the edge, every row is zero-padded, and the note adds nothing.
void main() {
  const List<LocalizationsDelegate<Object>> delegates =
      <LocalizationsDelegate<Object>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  Future<MmSkin> pump(WidgetTester t) async {
    final ThemeController theme = ThemeController();
    await t.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: ChangeNotifierProvider<AeicInstaller>(
          create: (_) => AeicInstaller(),
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: LocaleController.supported,
            localizationsDelegates: delegates,
            home: const ChatMediaSettingsScreen(),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return mmSkinFor(theme.preset);
  }

  testWidgets('the list owns the page edge, once', (WidgetTester t) async {
    final MmSkin skin = await pump(t);
    final ListView list = t.widget<ListView>(find.byType(ListView));
    expect(list.padding, skin.space.padScreen);
  });

  testWidgets('every row is zero-padded so the rows share one edge',
      (WidgetTester t) async {
    await pump(t);
    final List<ListTile> rows = t.widgetList<ListTile>(find.byType(ListTile)).toList();
    // The page has a retention row, a photo-mode row and the codec row; the
    // colour switch is a SwitchListTile, which is a ListTile subclass.
    expect(rows.length, greaterThanOrEqualTo(3));
    for (final ListTile row in rows) {
      expect(row.contentPadding, EdgeInsets.zero,
          reason: 'row "${row.key}" would sit off the page edge');
    }
  });

  testWidgets('the note lines up with the section headers', (WidgetTester t) async {
    await pump(t);
    final double headerLeft =
        t.getTopLeft(find.byType(MmSectionHeader).last).dx;
    final double noteLeft = t
        .getTopLeft(find.byKey(const ValueKey<String>('photo-public-note')))
        .dx;
    expect(noteLeft, headerLeft);
  });

  testWidgets('every row title starts in the same column', (WidgetTester t) async {
    await pump(t);
    final AppLocalizations l =
        AppLocalizations.of(t.element(find.byType(ChatMediaSettingsScreen)));
    // A row without a leading icon puts its title in the icon column, which is
    // 16 dp left of every title that has one. The colour switch shipped that
    // way: its title sat under the icons while the three rows around it sat
    // past them.
    final List<double> lefts = <double>[
      for (final String title in <String>[
        l.chatMediaRetentionTitle,
        l.photoModeTitle,
        l.settingsPhotoColorTitle,
        l.codecTitle,
      ])
        t.getTopLeft(find.text(title)).dx,
    ];
    expect(lefts.toSet().length, 1, reason: 'title columns: $lefts');
  });
}
