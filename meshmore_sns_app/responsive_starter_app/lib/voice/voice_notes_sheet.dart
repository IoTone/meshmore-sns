// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import 'voice_codec.dart';
import 'voice_inbox.dart';
import 'voice_payload.dart';
import 'voice_playback.dart';

/// The notes this session has taken off the current channel.
///
/// A surface of its own rather than rows in the timeline: the timeline is the
/// sealed history, one row per text message, and a voice payload is neither
/// text nor durable — it lives as long as the process. Putting it in the
/// timeline would mean either persisting 320 KB of PCM per note or showing a
/// row that is dead after a restart, and the second is worse than a sheet.
///
/// So the sheet states what it holds: the newest notes on this channel, kept
/// until the app closes, each playable from the bytes that arrived.
class VoiceNotesSheet extends StatefulWidget {
  const VoiceNotesSheet({
    super.key,
    required this.notes,
    required this.codec,
    this.playback,
  });

  /// The notes for the channel this sheet was opened from, newest first.
  final List<ReceivedVoice> notes;
  final VoiceCodec codec;
  final VoicePlayback? playback;

  static Future<void> show(
    BuildContext context, {
    required List<ReceivedVoice> notes,
    required VoiceCodec codec,
    VoicePlayback? playback,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => VoiceNotesSheet(
          notes: notes,
          codec: codec,
          playback: playback,
        ),
      );

  @override
  State<VoiceNotesSheet> createState() => _VoiceNotesSheetState();
}

class _VoiceNotesSheetState extends State<VoiceNotesSheet> {
  /// The payload id currently playing, if any.
  int? _playing;
  bool _decodeFailed = false;
  bool _playbackFailed = false;
  StreamSubscription<void>? _playedToEnd;

  @override
  void initState() {
    super.initState();
    _playedToEnd = widget.playback?.onComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
  }

  Future<void> _toggle(ReceivedVoice note) async {
    final VoicePlayback? playback = widget.playback;
    if (playback == null) return;
    setState(() {
      _decodeFailed = false;
      _playbackFailed = false;
    });
    if (_playing == note.payloadId) {
      await playback.stop();
      if (mounted) setState(() => _playing = null);
      return;
    }
    try {
      // The header is re-read here rather than stored, so a payload that was
      // accepted by this build is decoded at the width it names and nothing
      // else has to keep the mode in step with the bytes.
      final PackedVoice packed = VoicePayloadCodec.inspect(note.payload);
      final Uint8List pcm = widget.codec.decode(packed.bytes, mode: packed.mode);
      await playback.play(pcm);
      if (mounted) setState(() => _playing = note.payloadId);
    } on VoiceException {
      if (mounted) setState(() => _decodeFailed = true);
    } on VoicePlaybackException {
      if (mounted) setState(() => _playbackFailed = true);
    }
  }

  @override
  void dispose() {
    _playedToEnd?.cancel();
    unawaited(widget.playback?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final MaterialLocalizations material = MaterialLocalizations.of(context);
    return SafeArea(
      // Scrollable for the same reason the composer is: a note row at 200 %
      // text is two lines tall, and twelve of them are more than a sheet holds.
      child: SingleChildScrollView(
        padding: skin.space.pad(5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l.voiceNotesTitle,
              style: TextStyle(
                  color: skin.color.fg,
                  fontSize: skin.type.sizeLg,
                  fontWeight: FontWeight.w600),
            ),
            SizedBox(height: skin.space.step(2)),
            Text(
              l.voiceNotesSession,
              style: TextStyle(
                  color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
            ),
            SizedBox(height: skin.space.step(4)),
            if (_decodeFailed)
              Text(l.voiceNoteDecodeFailed,
                  key: const ValueKey<String>('voice-notes-decode-failed'),
                  style: TextStyle(
                      color: skin.color.alertInk, fontSize: skin.type.sizeSm)),
            if (_playbackFailed)
              Text(l.mediaDecodeFailed,
                  key: const ValueKey<String>('voice-notes-playback-failed'),
                  style: TextStyle(
                      color: skin.color.alertInk, fontSize: skin.type.sizeSm)),
            if (widget.notes.isEmpty)
              Text(
                l.voiceNotesEmpty,
                key: const ValueKey<String>('voice-notes-empty'),
                style: TextStyle(
                    color: skin.color.fgMuted, fontSize: skin.type.sizeBody),
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final ReceivedVoice note in widget.notes)
                    ListTile(
                      key: ValueKey<String>('voice-note-${note.payloadId}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: IconButton(
                        key: ValueKey<String>(
                            'voice-note-play-${note.payloadId}'),
                        tooltip: _playing == note.payloadId
                            ? l.voiceStop
                            : l.voiceNotePreview,
                        onPressed: widget.playback == null
                            ? null
                            : () => _toggle(note),
                        icon: Icon(_playing == note.payloadId
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline),
                      ),
                      title: Text(
                        '${note.duration.inSeconds} s · ${note.mode.label}',
                        style: TextStyle(
                            color: skin.color.fg,
                            fontSize: skin.type.sizeBody),
                      ),
                      subtitle: Text(
                        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(note.receivedAt))}'
                        ' · ${note.bytes} B',
                        style: TextStyle(
                            color: skin.color.fgMuted,
                            fontSize: skin.type.sizeSm,
                            fontFamily: skin.type.monoFamily),
                      ),
                    ),
                ],
              ),
            SizedBox(height: skin.space.step(4)),
            Align(
              alignment: Alignment.centerRight,
              child: MmAction(
                label: l.mediaClose,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
