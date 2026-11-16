// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/chat_message.dart';
import 'package:meshmore_sns_app/screens/delivery_status_icon.dart';

/// Five delivery states, five glyphs, five words.
///
/// The glyph is the whole statement a recipient's answer makes, and it had no
/// test: a state that shared another state's glyph or its label would read as
/// the same fact in two different situations. `deliveryLabel` exists so the
/// glyph's tooltip and the actions sheet cannot drift apart, which is only true
/// if they come from one function.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester t, MessageDelivery d) async {
    await t.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: Center(child: DeliveryStatusIcon(d))),
    ));
    await t.pump();
  }

  testWidgets('each state has its own glyph and its own label',
      (WidgetTester t) async {
    final Map<MessageDelivery, (IconData, String)> seen =
        <MessageDelivery, (IconData, String)>{};
    for (final MessageDelivery d in MessageDelivery.values) {
      await pump(t, d);
      final AppLocalizations l = AppLocalizations.of(
          t.element(find.byType(DeliveryStatusIcon)));
      final Icon icon = t.widget<Icon>(find.byType(Icon));
      final String label = deliveryLabel(l, d);
      expect(label, isNotEmpty);
      // The tooltip is the same word the actions sheet writes out.
      expect(find.byTooltip(label), findsOneWidget);
      for (final MapEntry<MessageDelivery, (IconData, String)> e
          in seen.entries) {
        expect(icon.icon, isNot(e.value.$1),
            reason: '${d.name} shares a glyph with ${e.key.name}');
        expect(label, isNot(e.value.$2),
            reason: '${d.name} shares a label with ${e.key.name}');
      }
      seen[d] = (icon.icon!, label);
    }
    expect(seen.length, 5, reason: 'every state is covered');
  });

  testWidgets('every state says something in Japanese too', (WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      locale: const Locale('ja'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: DeliveryStatusIcon(MessageDelivery.unknown)),
    ));
    await t.pump();
    final AppLocalizations l = AppLocalizations.of(
        t.element(find.byType(DeliveryStatusIcon)));
    final String label = deliveryLabel(l, MessageDelivery.unknown);
    expect(label, isNotEmpty);
    expect(RegExp(r'^[\x00-\x7F]+$').hasMatch(label), isFalse,
        reason: 'a Japanese label that is still English is not translated');
  });
}
