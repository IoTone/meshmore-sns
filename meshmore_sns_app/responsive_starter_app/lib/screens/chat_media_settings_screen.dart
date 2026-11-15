// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../meshcore/chat_store.dart';
import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import '../tts/tts_controller.dart';
import '../ui/mm_components.dart';
import '../ui/mm_scaffold.dart';
import 'photo_settings_screen.dart';
import 'voice_settings_screen.dart' show prettyVoiceName, voiceSettingsRows;

/// Chat and media: one page for everything a message is.
///
/// There were three pages — a chat menu that held a little, App settings that
/// held the photo rows, and a voice page — so "where do I change how long a
/// message is kept" had no answer, and the photo mode lived three taps from the
/// composer that uses it. A message, a photograph and a voice note are the same
/// decision from the reader's side: how much of what I have goes on the air.
///
/// Sections are Messages, Photos, Voice. Every one of them is *here*: nothing on
/// this page links to a second settings page for the same thing, which is what
/// makes one path possible to state.
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
            SizedBox(height: skin.space.sectionGap),
            MmSectionHeader(l.voiceSettingsTitle),
            const _VoiceSection(),
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

/// The voice rows, inline.
///
/// The same widget the voice page draws, so the two cannot disagree. The voice
/// screen still exists for a deep link from a diagnostic, but this page is the
/// one the settings hub opens.
class _VoiceSection extends StatefulWidget {
  const _VoiceSection();

  @override
  State<_VoiceSection> createState() => _VoiceSectionState();
}

class _VoiceSectionState extends State<_VoiceSection> {
  List<TtsVoice> _voices = const <TtsVoice>[];
  bool _loading = true;
  bool _onlyCurrent = true;
  final Map<String, bool> _offline = <String, bool>{};
  TtsController? _tts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final TtsController? tts = Provider.of<TtsController?>(context);
    if (identical(tts, _tts)) return;
    _tts = tts;
    _load();
  }

  Future<void> _load() async {
    final TtsController? tts = _tts;
    if (tts == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final List<TtsVoice> all = await tts.listVoices();
    if (!mounted) return;
    setState(() {
      _voices = all;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TtsController? tts = _tts;
    if (tts == null) {
      return Padding(
        padding: EdgeInsets.symmetric(
            horizontal: context.skin.space.screenEdge,
            vertical: context.skin.space.rowGap),
        child: Text(l.voiceUnavailable,
            style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }
    final String phoneLang = Localizations.localeOf(context).toLanguageTag();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: voiceSettingsRows(
        context: context,
        l: l,
        cs: cs,
        tc: tts,
        allVoices: _voices,
        onlyCurrent: _onlyCurrent,
        phoneLang: phoneLang,
        langOf: (String tag) => tag.replaceAll('_', '-').split('-').first,
        onOnlyCurrentChanged: (bool v) => setState(() => _onlyCurrent = v),
        loadingVoices: _loading,
        offline: _offline,
        prettyName: prettyVoiceName,
      ),
    );
  }
}
