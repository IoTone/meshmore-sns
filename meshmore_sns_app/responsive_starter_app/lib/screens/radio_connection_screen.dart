// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_scaffold.dart';
import '../ui/radio_connection_facts.dart';
import '../ui/radio_health_block.dart';

/// What the radio link is doing, and how to change it.
///
/// This screen exists because the page it was split out of answered two
/// questions at once. `diagnostics_screen.dart` led with connection facts and
/// then went on for six hundred lines about raw frames, fixture exports and the
/// M6 interop closure; a reader who tapped "Radio connection" in Settings landed
/// on a developer console with a connect button buried in the top third. The
/// facts and the four actions are here now, and the console keeps the frames.
///
/// Nothing on this screen needs a radio to be connected or a developer to read.
class RadioConnectionScreen extends StatelessWidget {
  const RadioConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsHubDiagnostics)),
      body: MmScaffold(
        child: ListView(
          children: <Widget>[
            const RadioConnectionFacts(),
            // The block carries its own title and its own Read action, so a
            // section header above it said "radio health" twice in the same
            // breath — the duplicated label rule the dashboard obeys.
            Padding(
              padding: EdgeInsets.fromLTRB(context.skin.space.screenEdge,
                  context.skin.space.step(3), context.skin.space.screenEdge, 0),
              child: const RadioHealthBlock(),
            ),
            // The door to the other half, at the bottom and named for what is
            // behind it. A developer console is not a continuation of a
            // connection screen; it is a different place, and it says so.
            Padding(
              // No horizontal padding: the ListTile already carries the page
              // edge, and a 2 dp wrapper put this row 2 dp right of every other
              // row on the screen.
              padding: EdgeInsets.symmetric(
                  vertical: context.skin.space.step(3)),
              // A navigating row, like every other row that leaves a settings
              // screen: [MmPickerTile] is for a row whose trailing slot states a
              // current choice, and this row states none.
              child: ListTile(
                key: const ValueKey<String>('connection-diagnostics-row'),
                leading: const Icon(Icons.memory),
                title: Text(l.connectionDiagnosticsRow),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/diagnostics'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
