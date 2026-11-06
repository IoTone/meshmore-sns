// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/chat/export_passphrase_dialog.dart';
import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';

/// The one passphrase prompt, used to seal an export and to open one.
///
/// Two screens offer it — a conversation, and Settings for the whole history —
/// and the restore path reuses it with different words. The contract both rely
/// on is that it returns exactly what was typed, and that a dismissed dialog
/// returns nothing rather than an empty string, because an empty passphrase is
/// a refusal the export makes, not a value the prompt invents.
class _Host extends StatefulWidget {
  const _Host({this.title, this.confirmLabel});

  final String? title;
  final String? confirmLabel;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String? answer;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // A Builder so the dialog's context is below the Navigator the
      // MaterialApp installs: a State's own context sits above it.
      home: Builder(
        builder: (BuildContext inner) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final String? a = await showDialog<String>(
                context: inner,
                builder: (BuildContext d) => ExportPassphraseDialog(
                  l: AppLocalizations.of(d),
                  title: widget.title,
                  confirmLabel: widget.confirmLabel,
                ),
              );
              setState(() => answer = a);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('the typed passphrase is what comes back',
      (WidgetTester t) async {
    await t.pumpWidget(const _Host());
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    // The defaults, because this is the export case.
    expect(find.text('Passphrase for the exported file'), findsOneWidget);
    await t.enterText(
        find.byKey(const ValueKey<String>('chat-export-passphrase')),
        'hunter2');
    await t.tap(find.byKey(const ValueKey<String>('chat-export-confirm')));
    await t.pumpAndSettle();

    final _HostState host = t.state<_HostState>(find.byType(_Host));
    expect(host.answer, 'hunter2');
  });

  testWidgets('the caller can word it for a backup', (WidgetTester t) async {
    await t.pumpWidget(const _Host(
      title: 'Passphrase for the backup',
      confirmLabel: 'Export',
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    expect(find.text('Passphrase for the backup'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Export'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    final _HostState host = t.state<_HostState>(find.byType(_Host));
    expect(host.answer, isNull,
        reason: 'a dismissed prompt has no passphrase, not an empty one');
  });
}
