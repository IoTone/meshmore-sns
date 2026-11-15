// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../meshcore/chat_store.dart';
import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';
import 'photo_settings_screen.dart';

/// Chat and photos: one page for what a message is and what a picture costs.
///
/// The photo rows used to live in App settings, three rows between the location
/// row and the system group, which is where a preference goes when nobody has
/// decided where it belongs. History retention had no home at all. Both are the
/// same question from the reader's side — how much of what I have goes out — so
/// they are one page, and App settings points here rather than repeating it.
///
/// Sections are Messages and Photos. Nothing on this page links to a second
/// settings page for the same thing, which is what makes one path possible to
/// state.
///
/// What is deliberately NOT here: the spoken-voice settings (rate, pitch, which
/// engine). Those are how the app *reads to you*, not what a message costs to
/// send, and they belong with the other reading and sound preferences.
class ChatMediaSettingsScreen extends StatelessWidget {
  const ChatMediaSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    return Scaffold(
      appBar: AppBar(title: Text(l.chatMediaTitle)),
      body: MmScaffold(
        child: ListView(
          padding: EdgeInsets.only(bottom: skin.space.sectionGap * 2),
          children: <Widget>[
            MmSectionHeader(l.chatMediaMessages),
            const _RetentionRow(),
            SizedBox(height: skin.space.sectionGap),
            MmSectionHeader(l.photoSettingsTitle),
            const PhotoModeTile(),
            const PhotoColorSwitch(),
            const AeicCodecRow(),
            Padding(
              padding: EdgeInsets.fromLTRB(skin.space.screenEdge, 0,
                  skin.space.screenEdge, skin.space.rowGap),
              child: Text(
                l.mediaOffOnPublic,
                key: const ValueKey<String>('photo-public-note'),
                style: TextStyle(
                    color: skin.color.fgMuted,
                    fontSize: skin.type.sizeSm,
                    height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How much history this app keeps, as a fact rather than a setting.
///
/// The cap is the store's own, so the page cannot promise a number the store
/// does not honour. A slider here would be a second place the number lives.
class _RetentionRow extends StatelessWidget {
  const _RetentionRow();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListTile(
      key: const ValueKey<String>('chat-media-retention'),
      dense: true,
      leading: const Icon(Icons.history),
      title: Text(l.chatMediaRetentionTitle),
      subtitle: Text(l.chatMediaRetentionBody(ChatStore.cap),
          style: TextStyle(color: cs.onSurfaceVariant)),
    );
  }
}
