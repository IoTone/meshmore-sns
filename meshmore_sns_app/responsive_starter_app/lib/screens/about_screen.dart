// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/issue_report.dart';
import '../app_state_model.dart';
import '../gen/app_localizations.dart';
import '../meshcore/meshcore_controller.dart';
import '../perms/first_run_controller.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';

/// R85 - the information page. It used to be its own top-level view; the
/// shell is now the six things a person actually switches between, and the
/// static pages are rows in the Settings hub: Settings > Information (this
/// page, with Licences) and, beside it, Settings > Docs (R86).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  /// Opens the tracker with what the app already knows. Read, not watched: the
  /// page does not need to rebuild when a radio connects.
  Future<void> _reportProblem(BuildContext context) async {
    final MeshcoreController mc = context.read<MeshcoreController>();
    final AppState app = context.read<AppState>();
    final IssueReport report = IssueReport(
      appVersion: app.getAppVersion(),
      platform: kIsWeb
          ? 'web'
          : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      radioName: mc.selfInfo?.name,
      radioModel: mc.deviceInfo?.manufacturer,
      radioFirmware: mc.deviceInfo?.firmwareVersion,
      mtu: mc.mtu,
    );
    await launchUrl(report.toUri(), mode: LaunchMode.externalApplication);
  }

  /// The project's own page for this app.
  ///
  /// The owner's ruling of 2026-11-06 replaced the copyright notice with a door
  /// to the project, and this is that door. The URL is the app's page on the
  /// Offline SNS site rather than its root, because the root describes four
  /// projects and this screen is about one of them.
  static final Uri _projectSite =
      Uri.parse('https://offlinesns.pages.dev/en/tboc/meshmore-sns/#/');

  Future<void> _openProjectSite(BuildContext context) async {
    await launchUrl(_projectSite, mode: LaunchMode.externalApplication);
  }

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
            Text(l.appName.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: skin.type.sizeXl,
                    letterSpacing: 4,
                    color: skin.color.fg)),
            const SizedBox(height: 4),
            // The EN + JP subtitles are rendered as a pair regardless of
            // the active locale: the brand is bilingual.
            Text(l.aboutSubtitleEn,
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: skin.type.sizeBodyLg, color: skin.color.fgMuted)),
            const SizedBox(height: 2),
            Text(l.aboutSubtitleJa,
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: skin.type.sizeBodyLg, color: skin.color.fgMuted)),
            SizedBox(height: skin.space.rowInset),
            Text(l.aboutVersion(app.getAppVersion()),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: skin.type.sizeBody, color: skin.color.fgMuted)),
            const SizedBox(height: 20),
            Text(
              // The copyright line is gone by the owner's ruling of
              // 2026-11-06: an About page that opens with a corporate notice
              // and no door to the project is a dead end. The licence stays,
              // because it is a fact about what the user may do with the app,
              // and the project site below is the door.
              '${l.aboutDescription}\n'
              '${l.aboutLicense}',
              textAlign: TextAlign.center,
              style: TextStyle(color: skin.color.fgMuted, height: 1.5),
            ),
            SizedBox(height: skin.space.rowGap),
            MmAction(
              key: const ValueKey<String>('about-project-site'),
              icon: Icons.public,
              label: l.aboutProjectSite,
              onPressed: () => _openProjectSite(context),
            ),
            SizedBox(height: skin.space.screenEdge),
            Text(l.aboutMadeWith,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: skin.color.fgMuted,
                    fontStyle: FontStyle.italic)),
            // The terms and privacy text lives here, beside what the app is,
            // because that is where a reader looks for it. It was on App
            // settings, which is a page for things you change.
            SizedBox(height: skin.space.screenEdge),
            // R10 — the only route a defect has to a person who can fix it:
            // there is no crash reporter and no analytics. The issue is
            // assembled on the phone, redacted, and sent only if the user sends
            // it in the tracker.
            MmAction(
              key: const ValueKey<String>('about-terms'),
              icon: Icons.privacy_tip_outlined,
              label: l.termsSettingsRow,
              onPressed: () => context.push('/settings/terms'),
            ),
            SizedBox(height: skin.space.rowGap),
            MmAction(
              icon: Icons.bug_report_outlined,
              label: l.aboutReportProblem,
              onPressed: () => _reportProblem(context),
            ),
            const SizedBox(height: 4),
            Text(
              l.aboutReportProblemSub,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: skin.type.size(10.5), color: skin.color.fgMuted),
            ),
            SizedBox(height: skin.space.rowGap),
            // Moved out of App settings: replaying the first-run screens is a
            // support action, not a setting.
            MmAction(
              icon: Icons.refresh,
              label: l.aboutReplayIntro,
              onPressed: context.watch<FirstRunController>().done
                  ? () => context.read<FirstRunController>().reset()
                  : null,
            ),
            SizedBox(height: skin.space.rowGap),
            // The app's own credits screen, not Flutter's licence page: that
            // page groups by package and knows nothing about the native
            // libraries, the fonts or the map data, which are the components
            // with real obligations.
            MmAction(
              icon: Icons.description_outlined,
              label: l.aboutLicensesButton,
              onPressed: () => context.push('/settings/credits'),
            ),
            SizedBox(height: skin.space.rowGap),
            Text(l.aboutAttributions,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: skin.color.fgMuted,
                    fontSize: skin.type.size(10.5),
                    height: 1.4)),
          ],
        ),
      ),
    );
  }
}
