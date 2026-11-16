// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/bundled_fonts.dart';

import 'package:meshmore_sns_app/docs/doc_section.dart';
import 'package:meshmore_sns_app/docs/docs_repository.dart';
import 'package:meshmore_sns_app/docs/markdown_view.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/screens/doc_reader_screen.dart';
import 'package:meshmore_sns_app/theme/theme_controller.dart';

import '../meshcore/fake_transport.dart';

/// The Docs reader renders the bundled markdown snapshots (offline, the
/// fetcher is stubbed to "no network"). It is a long scrolling page of
/// headings, tables and code, so it is the page most likely to overflow
/// on a narrow phone or at large text: this walks every section at the
/// sizes the overflow sweep uses, with the app's own fonts loaded.

/// Serves the bundled snapshot straight from disk and never refreshes, so
/// the test needs neither the network nor the asset bundle's isolate hop.
class _OfflineRepo extends DocsRepository {
  @override
  Future<DocContent> load(DocSection section) async => DocContent(
        section: section,
        markdown: File(DocSpec.of(section).assetPath).readAsStringSync(),
        origin: DocOrigin.bundled,
      );

  @override
  Future<DocContent?> refresh(DocSection section,
          {String? firmwareVersion, DateTime? now}) async =>
      null;
}

void main() {
  setUpAll(loadBundledFonts);

  const List<(double, double, double)> sizes = <(double, double, double)>[
    (320, 780, 1.0),
    (320, 780, 2.0),
    (393, 780, 2.0),
    (568, 320, 1.0),
  ];

  for (final DocSection s in DocSection.values) {
    for (final (double, double, double) z in sizes) {
      testWidgets('${s.name} reader at ${z.$1.toInt()}x${z.$2.toInt()} '
          'text x${z.$3}: no overflow', (WidgetTester t) async {
        t.view.physicalSize = Size(z.$1, z.$2);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final MeshcoreController mc = MeshcoreController(
            transportFactory: () async => FakeMeshcoreTransport());
        await t.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<MeshcoreController>.value(value: mc),
            ChangeNotifierProvider<ThemeController>(
                create: (_) => ThemeController()),
            Provider<DocsRepository>(
                create: (_) => _OfflineRepo()),
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
            builder: (BuildContext c, Widget? child) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(z.$3)),
                child: child!),
            home: DocReaderScreen(section: s),
          ),
        ));
        await t.pump();
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        // The snapshot actually loaded and rendered (not the spinner).
        expect(find.byType(MarkdownView), findsOneWidget);
        expect(t.takeException(), isNull);
        mc.dispose();
      });
    }
  }
}
