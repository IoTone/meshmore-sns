// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../media/media_chunk.dart';
import '../media/media_send_policy.dart';
import '../media/media_sender.dart';
import '../media/media_transfer.dart';
import '../meshcore/channel_datagram.dart';
import '../meshcore/meshcore_controller.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import 'voice_capture.dart';
import 'voice_codec.dart';
import 'voice_payload.dart';
import 'voice_playback.dart';

/// Records a note, states what it costs, and sends it.
///
/// The order is the photo composer's and for the same reasons: the channel
/// rules run before the codec, the cost is stated before anything is queued,
/// and the engine paces the chunks so the progress line moves one datagram at a
/// time. Two things are voice's own:
///
/// * **The 20-second ceiling is stated before the microphone opens**, and the
///   take says so when the ceiling is what ended it. A recording that stops by
///   itself is otherwise indistinguishable from a button that was ignored.
/// * **The mode is chosen before the frames exist and can be changed after**,
///   because the same 20 seconds costs 1,750 bytes at 700C and 3,250 at 1300,
///   and that is the one decision a sender cannot make from a label alone. The
///   take is kept so switching re-encodes from the same PCM rather than asking
///   the user to speak again.
class VoiceComposer extends StatefulWidget {
  const VoiceComposer({
    super.key,
    required this.service,
    required this.capture,
    required this.codec,
    required this.channelPsk,
    required this.sendBlob,
    this.playback,
    this.initialMode = VoiceMode.narrowband,
  });

  /// The transfer engine. Its codec is the image one and is not used here, but
  /// the estimator, the clock, the pacing and the Public gate are the same
  /// rules a photo spends, so a second engine would be a second set of them.
  final MediaTransferService service;

  final VoiceCapture capture;
  final VoiceCodec codec;

  /// The channel's secret. Media is off on the well-known Public channel by
  /// default, and the rule is keyed on the secret rather than the name.
  final List<int>? channelPsk;

  /// The radio call for one datagram.
  final Future<ChannelDataSendResult> Function(Uint8List blob) sendBlob;

  /// Used for the preview. Null hides the preview rather than showing a control
  /// that cannot act.
  final VoicePlayback? playback;

  final VoiceMode initialMode;

  /// Opens the sheet; resolves to true when a note was sent.
  static Future<bool?> show(
    BuildContext context, {
    required MediaTransferService service,
    required VoiceCapture capture,
    required VoiceCodec codec,
    required List<int>? channelPsk,
    required Future<ChannelDataSendResult> Function(Uint8List blob) sendBlob,
    VoicePlayback? playback,
    VoiceMode initialMode = VoiceMode.narrowband,
  }) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => VoiceComposer(
          service: service,
          capture: capture,
          codec: codec,
          channelPsk: channelPsk,
          sendBlob: sendBlob,
          playback: playback,
          initialMode: initialMode,
        ),
      );

  @override
  State<VoiceComposer> createState() => _VoiceComposerState();
}

enum _Stage { idle, recording, encoding, ready, sending, done, failed }

class _VoiceComposerState extends State<VoiceComposer> {
  _Stage _stage = _Stage.idle;
  late VoiceMode _mode = widget.initialMode;

  /// Null until the answer has come back, so the sheet does not say "no codec"
  /// for the frame before the platform answers.
  ///
  /// There is no microphone probe here on purpose: `record`'s own permission
  /// check asks the OS, and asking it when the sheet opens turns "I might send
  /// a note" into a permission prompt. The prompt belongs to the Record tap,
  /// where the user has already said what they want.
  bool? _codecReady;

  /// The take, kept after encoding so a mode change re-encodes it rather than
  /// asking for a second recording.
  VoiceRecording? _recording;
  PackedVoice? _packed;
  MediaTransferPlan? _plan;
  MediaSendRefusal? _refusal;
  VoiceException? _voiceFailure;
  VoiceCaptureRefusal? _captureFailure;
  VoicePlaybackFailure? _playbackFailure;
  bool _tooShort = false;
  bool _linkFailed = false;

  /// Set when the send stopped on capacity rather than on a lost chunk.
  MediaSendResult? _stalled;

  /// The upload in flight, so closing the sheet stops it instead of leaving a
  /// datagram going out every two seconds for a note nobody is watching.
  MediaUpload? _upload;

  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  int _sent = 0;
  MediaReceipt? _receipt;
  Set<int> _lost = <int>{};
  bool _playing = false;
  StreamSubscription<void>? _playedToEnd;

  @override
  void initState() {
    super.initState();
    _probe();
    _playedToEnd = widget.playback?.onComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  void _probe() {
    setState(() => _codecReady = widget.codec.isAvailable);
  }

  Future<void> _start() async {
    setState(() {
      _stage = _Stage.recording;
      _elapsed = Duration.zero;
      _captureFailure = null;
      _voiceFailure = null;
      _tooShort = false;
      _refusal = null;
      _plan = null;
      _packed = null;
      _receipt = null;
      _lost = <int>{};
      _linkFailed = false;
      _stalled = null;
    });
    // The elapsed time is the ticker's own count rather than a wall-clock
    // difference: the timer is what the surface can act on, it advances under a
    // test's fake clock like it does on a phone, and the recorder's own timer —
    // not this one — is what ends the audio.
    int ticks = 0;
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      ticks++;
      final Duration elapsed = const Duration(milliseconds: 200) * ticks;
      setState(() => _elapsed = elapsed);
      // The recorder stops itself at the ceiling and tells nobody: its own
      // timer ends the take quietly. Without this the sheet stays on
      // "Recording" past the limit with the audio already finished, and the
      // only way to get the note is to press Stop on a recording that ended
      // itself. A device run found it — the counter read 28 s past a 20 s
      // ceiling. The grace lets the capture's own stop land first, so this
      // call finds the finished take rather than racing it.
      if (elapsed >= widget.capture.limit + const Duration(milliseconds: 400)) {
        unawaited(_stop());
      }
    });
    try {
      await widget.capture.start();
    } on VoiceCaptureException catch (e) {
      _ticker?.cancel();
      _ticker = null;
      if (!mounted) return;
      setState(() {
        _captureFailure = e.refusal;
        _stage = _Stage.idle;
      });
    }
  }

  Future<void> _stop() async {
    if (_stage != _Stage.recording) return;
    // Claimed before the first await, so the ceiling and a tap cannot both
    // enter the stop path.
    setState(() => _stage = _Stage.encoding);
    _ticker?.cancel();
    _ticker = null;
    // The capture owns the ceiling and its own stop; this waits for whichever
    // stop is in flight rather than racing it, which is what makes a take that
    // the ceiling ended come back with its audio instead of empty.
    final VoiceRecording take = await widget.capture.stop();
    if (!mounted) return;
    _recording = take;
    _elapsed = take.duration;
    await _encode();
  }

  /// Turns the take into a plan, or says why it could not.
  Future<void> _encode() async {
    final VoiceRecording? take = _recording;
    if (take == null) return;
    final Uint8List pcm = voicePcmWholeFrames(take.pcm, _mode);
    final int frames = pcm.length ~/ _mode.pcmBytesPerFrame;
    if (frames < kVoiceMinFrames) {
      setState(() {
        _stage = _Stage.idle;
        _tooShort = true;
        _recording = null;
        _packed = null;
        _plan = null;
      });
      return;
    }
    setState(() {
      _stage = _Stage.encoding;
      _plan = null;
      _refusal = null;
      _voiceFailure = null;
    });
    final PackedVoice packed;
    try {
      packed = widget.codec.encode(pcm, mode: _mode);
    } on VoiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _voiceFailure = e;
        _stage = _Stage.idle;
      });
      return;
    }
    final MediaPreparation outcome = await widget.service.prepareVoice(
      voice: packed,
      channelPsk: widget.channelPsk,
    );
    if (!mounted) return;
    switch (outcome) {
      case MediaPrepared(plan: final MediaTransferPlan plan):
        setState(() {
          _packed = packed;
          _plan = plan;
          _stage = _Stage.ready;
        });
      case MediaRefused(refusal: final MediaSendRefusal refusal):
        // The take is kept: the refusal names a rule about the channel, and
        // throwing the recording away would make the user speak again to send
        // the same words somewhere else.
        setState(() {
          _packed = packed;
          _refusal = refusal;
          _stage = _Stage.ready;
        });
    }
  }

  Future<void> _setMode(VoiceMode mode) async {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    if (_recording != null) await _encode();
  }

  Future<void> _preview() async {
    final PackedVoice? packed = _packed;
    final VoicePlayback? playback = widget.playback;
    if (packed == null || playback == null) return;
    if (_playing) {
      await playback.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    try {
      final Uint8List pcm =
          widget.codec.decode(packed.bytes, mode: packed.mode);
      await playback.play(pcm);
      if (mounted) setState(() => _playing = true);
    } on VoiceException catch (e) {
      if (mounted) setState(() => _voiceFailure = e);
    } on VoicePlaybackException catch (e) {
      if (mounted) setState(() => _playbackFailure = e.failure);
    }
  }

  Future<void> _send() async {
    final MediaTransferPlan? plan = _plan;
    if (plan == null) return;
    setState(() {
      _stage = _Stage.sending;
      _sent = 0;
      _lost = <int>{};
      _linkFailed = false;
      _stalled = null;
    });
    final MediaUpload upload = widget.service.upload(plan);
    _upload = upload;
    try {
      final MediaReceipt receipt = await upload.run((Uint8List blob) async {
        final ChannelDataSendResult result = await widget.sendBlob(blob);
        if (mounted) setState(() => _sent = upload.sent);
        return result;
      });
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _stage = _Stage.done;
      });
    } on MediaUploadFailed catch (e) {
      if (!mounted) return;
      setState(() {
        _lost = e.lost;
        _stage = _Stage.failed;
      });
    } on MediaUploadStalled catch (e) {
      if (!mounted) return;
      setState(() {
        _stalled = e.reason;
        _stage = _Stage.failed;
      });
    } on MediaUploadCancelled {
      // The sheet closed: nothing to report to a surface that is gone.
    } catch (_) {
      // The engine re-throws the radio's own error after a run of failures: the
      // link is gone, and the chunks that were never acknowledged are the whole
      // of what did not go out.
      if (!mounted) return;
      setState(() {
        _linkFailed = true;
        _stage = _Stage.failed;
      });
    } finally {
      _upload = null;
    }
  }

  Future<void> _discard() async {
    _ticker?.cancel();
    _ticker = null;
    await widget.capture.cancel();
    await widget.playback?.stop();
    if (!mounted) return;
    setState(() {
      _stage = _Stage.idle;
      _recording = null;
      _packed = null;
      _plan = null;
      _refusal = null;
      _voiceFailure = null;
      _tooShort = false;
      _elapsed = Duration.zero;
      _playing = false;
      _receipt = null;
      _lost = <int>{};
      _linkFailed = false;
      _stalled = null;
    });
  }

  /// What the take costs so far, from its length rather than from an encode:
  /// a note being recorded has no frames yet, and a person watching the clock
  /// is watching exactly the number that decides the chunk count.
  int get _liveBytes =>
      VoicePayloadCodec.headerBytes + _mode.packedBytesFor(_elapsed);

  int get _liveDatagrams =>
      (_liveBytes + MediaChunkCodec.maxDataBytes - 1) ~/
      MediaChunkCodec.maxDataBytes;

  @override
  void dispose() {
    _upload?.cancel();
    _ticker?.cancel();
    _playedToEnd?.cancel();
    // The capture and the player are the caller's: a sheet closes, a
    // microphone does not stay open, and the shared objects are not disposed
    // here because the next sheet will use them.
    if (_stage == _Stage.recording) {
      unawaited(widget.capture.cancel());
    }
    unawaited(widget.playback?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final String? scope = context.watch<MeshcoreController?>()?.floodScopeName;
    final bool canRecord = _codecReady == true;
    return SafeArea(
      // Scrollable, because a sheet is the one surface that cannot grow: at
      // 320 dp and 200 % text the four footer controls and the copy above them
      // do not fit, and content that overflows a sheet is clipped rather than
      // scrolled. The footer scrolls with the rest; a control that is off the
      // bottom of a scroll view can still be reached, one clipped by the sheet
      // cannot.
      child: SingleChildScrollView(
        padding: skin.space.pad(5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l.voiceTitle,
              style: TextStyle(
                  color: skin.color.fg,
                  fontSize: skin.type.sizeLg,
                  fontWeight: FontWeight.w600),
            ),
            SizedBox(height: skin.space.step(2)),
            Text(
              // The ceiling is stated before the microphone opens, which is why
              // it is here and not in the recording state.
              l.voiceLimit,
              key: const ValueKey<String>('voice-limit'),
              style:
                  TextStyle(color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
            ),
            SizedBox(height: skin.space.step(2)),
            Text(
              scope == null
                  ? l.mediaReachUnknown
                  : scope.isEmpty
                      ? l.mediaReachNoScope
                      : l.mediaReachScope(scope),
              key: const ValueKey<String>('voice-reach'),
              style:
                  TextStyle(color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
            ),
            SizedBox(height: skin.space.step(5)),
            if (_codecReady == false)
              _Note(skin: skin, text: l.voiceNoCodec, alert: true),
            if (_captureFailure != null)
              _Note(
                skin: skin,
                alert: true,
                text: switch (_captureFailure!) {
                  VoiceCaptureRefusal.permissionDenied => l.voiceNoMicrophone,
                  VoiceCaptureRefusal.pcmUnsupported => l.voiceNoMicrophone,
                },
              ),
            if (_voiceFailure != null) _Note(
                skin: skin,
                alert: true,
                text: _voiceFailure!.failure == VoiceFailure.modeUnavailable
                    ? l.voiceNoCodec
                    : l.mediaDecodeFailed),
            if (_playbackFailure != null)
              _Note(skin: skin, alert: true, text: l.mediaDecodeFailed),
            if (_tooShort)
              _Note(skin: skin, text: l.voiceNoteTooShort),
            if (_recording?.stoppedAtCeiling ?? false)
              _Note(
                skin: skin,
                // A take the ceiling ended says so, because a recording that
                // stopped by itself is otherwise indistinguishable from a
                // button that was ignored.
                text: l.voiceStoppedAtLimit,
                key: const ValueKey<String>('voice-stopped-at-limit'),
              ),
            if (_refusal != null) _refusalNote(skin, l),
            ..._modeRow(skin, l),
            if (_stage == _Stage.recording)
              Text(
                l.voiceRecording(_elapsed.inSeconds, _liveBytes, _liveDatagrams),
                key: const ValueKey<String>('voice-elapsed'),
                style:
                    TextStyle(color: skin.color.fg, fontSize: skin.type.sizeBody),
              ),
            if (_stage == _Stage.encoding)
              Text(l.mediaEncoding,
                  style: TextStyle(
                      color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
            if (_plan != null && _stage != _Stage.done) _planBlock(skin, l),
            if (_stage == _Stage.sending)
              Text(l.mediaSendingProgress(_sent, _plan!.cost.chunks),
                  key: const ValueKey<String>('voice-progress'),
                  style: TextStyle(
                      color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
            if (_stage == _Stage.done && _receipt != null)
              _receiptBlock(skin, l, _receipt!),
            if (_stage == _Stage.failed && _stalled != null)
              _Note(
                skin: skin,
                alert: true,
                text: _stalled == MediaSendResult.budgetRefused
                    ? l.mediaStalledAirtime
                    : l.mediaStalledTableFull,
              ),
            if (_stage == _Stage.failed && _stalled == null)
              _Note(
                  skin: skin,
                  alert: true,
                  text: l.mediaSendFailed(
                      _linkFailed ? (_plan?.cost.chunks ?? 0) : _lost.length)),
            SizedBox(height: skin.space.step(4)),
            // An OverflowBar, not a Row: this sheet carries up to four
            // controls and a 320 dp screen at 200 % text has room for none of
            // them side by side. When they do not fit it stacks them, which is
            // the one shape a bottom sheet can always draw.
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: skin.space.step(3),
              overflowSpacing: skin.space.step(2),
              children: <Widget>[
                if (_stage == _Stage.idle)
                  FilledButton.icon(
                    key: const ValueKey<String>('voice-record'),
                    onPressed: canRecord ? _start : null,
                    icon: const Icon(Icons.mic_none_outlined),
                    label: Text(l.voiceRecord),
                  ),
                if (_stage == _Stage.recording)
                  FilledButton.icon(
                    key: const ValueKey<String>('voice-stop'),
                    onPressed: _stop,
                    icon: const Icon(Icons.stop),
                    label: Text(l.voiceStop),
                  ),
                if (_stage == _Stage.ready && _packed != null)
                  OutlinedButton.icon(
                    key: const ValueKey<String>('voice-preview'),
                    onPressed: widget.playback == null ? null : _preview,
                    icon: Icon(_playing ? Icons.stop : Icons.play_arrow_outlined),
                    label:
                        Text(_playing ? l.voiceNotePlaying : l.voiceNotePreview),
                  ),
                if (_stage == _Stage.ready && _packed != null)
                  MmAction(
                    key: const ValueKey<String>('voice-discard'),
                    label: l.voiceDiscard,
                    onPressed: _discard,
                  ),
                MmAction(
                  label: l.mediaClose,
                  onPressed: () => Navigator.of(context).maybePop(false),
                ),
                if (_stage == _Stage.ready && _plan != null)
                  FilledButton(
                    key: const ValueKey<String>('voice-send'),
                    onPressed: _send,
                    child: Text(l.voiceNoteSend),
                  ),
                if (_stage == _Stage.failed && _plan != null)
                  FilledButton(
                    key: const ValueKey<String>('voice-retry'),
                    onPressed: _send,
                    child: Text(l.mediaRetrySend),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The mode picker. Two options, each with its own cost, and both read from
  /// the mode itself rather than from a table this file would have to keep in
  /// step with the codec.
  List<Widget> _modeRow(MmSkin skin, AppLocalizations l) {
    final bool locked = _stage == _Stage.sending || _stage == _Stage.done;
    final List<(VoiceMode, String)> options = <(VoiceMode, String)>[
      (VoiceMode.narrowband, l.voiceModeNarrow),
      (VoiceMode.standard, l.voiceModeStandard),
    ];
    return <Widget>[
      Text(l.voiceModeTitle,
          style: TextStyle(color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
      SizedBox(height: skin.space.step(2)),
      Wrap(
        spacing: skin.space.step(2),
        children: <Widget>[
          for (final (VoiceMode mode, String label) in options)
            MmChoiceChip(
              key: ValueKey<String>('voice-mode-${mode.wireId}'),
              label: Text(label),
              selected: _mode == mode,
              onSelected: locked ? null : (_) => _setMode(mode),
            ),
        ],
      ),
      SizedBox(height: skin.space.step(4)),
    ];
  }

  Widget _refusalNote(MmSkin skin, AppLocalizations l) => _Note(
        skin: skin,
        alert: true,
        text: switch (_refusal!) {
          MediaSendRefusal.mediaOffOnPublic => l.mediaOffOnPublic,
          MediaSendRefusal.payloadUnusable => l.mediaPayloadUnusable,
          MediaSendRefusal.channelUnknown => l.mediaChannelUnknown,
          MediaSendRefusal.fullPictureOnChannel => l.mediaFullPictureOnChannel,
        },
      );

  Widget _planBlock(MmSkin skin, AppLocalizations l) {
    final MediaTransferPlan? plan = _plan;
    final PackedVoice? packed = _packed;
    if (plan == null || packed == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.voiceCost(
            plan.cost.chunks,
            plan.cost.airtime.inSeconds,
            packed.mode.label,
          ),
          key: const ValueKey<String>('voice-cost'),
          style: TextStyle(color: skin.color.fg, fontSize: skin.type.sizeBody),
        ),
        SizedBox(height: skin.space.step(3)),
      ],
    );
  }

  Widget _receiptBlock(MmSkin skin, AppLocalizations l, MediaReceipt r) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.mediaReceiptLine(r.chunks, r.resends),
              key: const ValueKey<String>('voice-receipt'),
              style:
                  TextStyle(color: skin.color.fg, fontSize: skin.type.sizeBody)),
          Text(l.mediaAcceptedNotDelivered,
              style: TextStyle(
                  color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
        ],
      );
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.skin, required this.text, this.alert = false});

  final MmSkin skin;
  final String text;
  final bool alert;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: skin.space.step(3)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(alert ? Icons.error_outline : Icons.info_outline,
                size: skin.type.sizeLg,
                color: alert ? skin.color.alert : skin.color.fgMuted),
            SizedBox(width: skin.space.step(2)),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: alert ? skin.color.alert : skin.color.fgMuted,
                      fontSize: skin.type.sizeSm)),
            ),
          ],
        ),
      );
}
