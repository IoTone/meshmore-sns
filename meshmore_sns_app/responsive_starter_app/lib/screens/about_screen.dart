// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state_model.dart';
import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_scaffold.dart';

/// R85 - the information page. It used to be its own top-level view; the
/// shell is now the six things a person actually switches between, and the
/// static pages are rows in the Settings hub: Settings > Information (this
/// page, with Licences) and, beside it, Settings > Docs (R86).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AppState app = context.watch<AppState>();
    final MmSkin skin = context.skin;
    return Scaffold(
      appBar: AppBar(title: Text(l.tabAbout)),
      body: MmScaffold(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: <Widget>[
            Text('MESHMORE SNS',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 22,
                    letterSpacing: 4,
                    color: skin.color.fg)),
            const SizedBox(height: 4),
            // The EN + JP subtitles are rendered as a pair regardless of
            // the active locale: the brand is bilingual.
            Text(l.aboutSubtitleEn,
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: skin.color.fgMuted)),
            const SizedBox(height: 2),
            Text(l.aboutSubtitleJa,
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: skin.color.fgMuted)),
            const SizedBox(height: 14),
            Text(l.aboutVersion(app.getAppVersion()),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: skin.color.fgMuted)),
            const SizedBox(height: 20),
            Text(
              '${l.aboutDescription}\n'
              '${l.aboutCopyright}\n'
              '${l.aboutLicense}',
              textAlign: TextAlign.center,
              style: TextStyle(color: skin.color.fgMuted, height: 1.5),
            ),
            const SizedBox(height: 18),
            Text(l.aboutMadeWith,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: skin.color.fgMuted,
                    fontStyle: FontStyle.italic)),
            // No "Terms & Conditions" line until U5 actually builds a terms
            // page: the string said "wired in U5" and was visibly a note to
            // self on a shipped About page (seen on the device).
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: l.appName,
                applicationVersion: l.aboutVersion(app.getAppVersion()),
                applicationLegalese: l.aboutCopyright,
              ),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: Text(l.aboutLicensesButton),
            ),
            const SizedBox(height: 10),
            Text(l.aboutAttributions,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: skin.color.fgMuted, fontSize: 10.5, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
