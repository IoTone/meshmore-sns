// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../legal/terms_controller.dart';
import '../meshcore/chat_store.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';

/// The terms and privacy page, in two modes.
///
/// [gate] is the first-use gate: the app does not open until the current text
/// has been agreed to, and the only other way out is to leave the app. The
/// read-only mode is the same text reached from Settings later, so the copy
/// can be checked at any time without a way to un-agree retroactively.
///
/// Every statement here is a fact about this build: there is no account, no
/// server and no analytics; the radio is the only path off the device apart
/// from map packs the user turns on and files the user exports. If a feature
/// changes one of those facts, this page and [TermsController.currentVersion]
/// change with it.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key, this.gate = true});

  final bool gate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final TermsController terms = context.watch<TermsController>();

    final List<(String, String)> sections = <(String, String)>[
      (l.termsSectionLocal, l.termsLocalBody),
      (l.termsSectionLeaves, l.termsLeavesBody),
      (l.termsSectionPermissions, l.termsPermissionsBody),
      (l.termsSectionRetention, l.termsRetentionBody(ChatStore.cap)),
      (l.termsSectionChanges, l.termsChangesBody),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l.termsTitle),
        automaticallyImplyLeading: !gate,
      ),
      body: MmScaffold(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: <Widget>[
                  Text(
                    l.termsLead,
                    style: TextStyle(
                      color: skin.color.fg,
                      fontSize: skin.type.sizeBodyLg,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: skin.space.step(5)),
                  for (final (String title, String body) in sections) ...<
                      Widget>[
                    MmSectionHeader(title),
                    Text(
                      body,
                      style: TextStyle(
                        color: skin.color.fgMuted,
                        fontSize: skin.type.sizeBody,
                        height: 1.55,
                      ),
                    ),
                    SizedBox(height: skin.space.step(5)),
                  ],
                  Text(
                    l.termsVersion(TermsController.currentVersion),
                    style: TextStyle(
                      color: skin.color.fgMuted,
                      fontSize: skin.type.sizeSm,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: gate
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          l.termsGateNote,
                          style: TextStyle(
                            color: skin.color.fgMuted,
                            fontSize: skin.type.sizeSm,
                          ),
                        ),
                        SizedBox(height: skin.space.step(3)),
                        // OverflowBar stacks the two actions when 200 %
                        // text leaves no room for them side by side; a Row
                        // overflowed by 392 px at 320 dp.
                        OverflowBar(
                          alignment: MainAxisAlignment.end,
                          overflowAlignment: OverflowBarAlignment.end,
                          spacing: skin.space.step(3),
                          children: <Widget>[
                            TextButton(
                              onPressed: () => SystemNavigator.pop(),
                              child: Text(l.termsExit),
                            ),
                            FilledButton(
                              key: const ValueKey<String>('terms-accept'),
                              onPressed: terms.accepted
                                  ? null
                                  : () =>
                                      context.read<TermsController>().accept(),
                              child: Text(l.termsAccept),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        terms.acceptedVersion == null
                            ? l.termsNotAccepted
                            : l.termsAcceptedVersion(terms.acceptedVersion!),
                        style: TextStyle(
                          color: skin.color.fgMuted,
                          fontSize: skin.type.sizeSm,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
