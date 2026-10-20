// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshmore_sns_app/gen/app_localizations.dart';
import 'package:meshmore_sns_app/l10n/locale_controller.dart';
import 'package:meshmore_sns_app/meshcore/meshcore_controller.dart';
import 'package:meshmore_sns_app/shell/boot_overlay.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.log);
  final List<String> log;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.log.add('init');
  }

  @override
  void dispose() {
    widget.log.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('shell');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // R68 — dismissing the overlay used to swap Stack -> bare child, which
  // unmounted the shell and built a second one: every screen's State was
  // created twice at launch (and, once screens carry unique ids, tripped
  // their duplicate-id assertion in debug builds).
  testWidgets('dismissing the overlay keeps the shell mounted (one State)',
      (WidgetTester t) async {
    final List<String> log = <String>[];
    final MeshcoreController mc = MeshcoreController();
    await t.pumpWidget(
      ChangeNotifierProvider<MeshcoreController>.value(
        value: mc,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: LocaleController.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: BootOverlay(child: _Probe(log)),
        ),
      ),
    );
    expect(log, <String>['init']);
    // No paired radio and not connecting: quiescent, so it dismisses.
    await t.pumpAndSettle();
    expect(find.text('shell'), findsOneWidget);
    expect(log, <String>['init'],
        reason: 'the shell must not be rebuilt as a second State');
    mc.dispose();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
