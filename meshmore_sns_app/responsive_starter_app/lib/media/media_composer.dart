// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/channel_datagram.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import 'media_chunk.dart';
import 'media_journal.dart';
import 'media_photo.dart';
import 'media_send_policy.dart';
import 'media_sender.dart';
import 'media_transfer.dart';

/// Where a picture comes from: the camera, or the gallery.
///
/// A photo of the thing in front of you and a photo saved last week are two
/// intentions, and the platform asks for them with two different sources. The
/// composer offers both rather than guessing.
enum MediaPhotoOrigin { camera, gallery }

/// Where a picture comes from.
///
/// A seam rather than a direct plugin call: the platform picker is a
/// dependency with its own permissions and its own native library, and the
/// composer's behaviour (the cost, the refusals, the pacing) must be provable
/// without one. [isAvailable] is what lets the surface say "this build cannot
/// read a photo" instead of showing a button that does nothing.
abstract interface class MediaPhotoSource {
  bool get isAvailable;

  /// The picture the user chose, or null when they backed out. A failure to
  /// read one is [MediaPhotoSourceFailure], which is a different thing from
  /// choosing nothing.
  Future<MediaPhoto?> pick({MediaPhotoOrigin origin = MediaPhotoOrigin.gallery});
}

/// Why a chosen file did not become a picture.
///
/// The two are separate because the answers differ: an unreadable file is
/// worth retrying with another one, and an unsupported container means the
/// photo the user has cannot be sent at all, so the copy has to say what to
/// do instead.
enum MediaPhotoSourceProblem { unreadable, unsupportedFormat }

/// The source refused or could not read the picture.
final class MediaPhotoSourceFailure implements Exception {
  const MediaPhotoSourceFailure(
    this.reason, {
    this.problem = MediaPhotoSourceProblem.unreadable,
  });

  final String reason;
  final MediaPhotoSourceProblem problem;

  @override
  String toString() => 'MediaPhotoSourceFailure($reason)';
}

/// A source for a build with no platform photo reader.
///
/// It is a named state rather than a disabled button: the composer says the
/// build cannot read a photo, which is true, instead of failing on a tap. The
/// platform picker is a separate dependency with its own permissions and its
/// own native library, so it arrives as its own decision with its own 16 KB
/// check.
final class UnavailableMediaPhotoSource implements MediaPhotoSource {
  const UnavailableMediaPhotoSource();

  @override
  bool get isAvailable => false;

  @override
  Future<MediaPhoto?> pick(
          {MediaPhotoOrigin origin = MediaPhotoOrigin.gallery}) async =>
      null;
}

/// The source the chat surface uses until a platform picker is decided.
const MediaPhotoSource kNoMediaPhotoSource = UnavailableMediaPhotoSource();

/// The composer for one channel: choose a picture, read its cost, send it.
///
/// The order is deliberate. The channel rules run before the encoder, so a
/// Public channel answers instantly; the cost is shown before anything is
/// queued, because a photo is twenty datagrams and most of an hour's airtime
/// budget on the slow presets; and the send is paced by the engine, so the
/// progress line moves one chunk at a time rather than jumping.
class MediaComposer extends StatefulWidget {
  const MediaComposer({
    super.key,
    required this.service,
    required this.source,
    required this.channelPsk,
    required this.byteBudget,
    required this.sendBlob,
  });

  final MediaTransferService service;
  final MediaPhotoSource source;

  /// The channel's secret. Media is off on the well-known Public channel by
  /// default, and the rule is keyed on the secret rather than the name.
  final List<int>? channelPsk;

  /// Target bytes for the encoded picture. The plan reports when the encoder
  /// could not reach it rather than failing silently.
  final int byteBudget;

  /// The radio call for one datagram.
  final Future<ChannelDataSendResult> Function(Uint8List blob) sendBlob;

  /// Opens the composer; resolves to true when a picture was sent.
  static Future<bool?> show(
    BuildContext context, {
    required MediaTransferService service,
    required MediaPhotoSource source,
    required List<int>? channelPsk,
    required int byteBudget,
    required Future<ChannelDataSendResult> Function(Uint8List blob) sendBlob,
  }) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => MediaComposer(
          service: service,
          source: source,
          channelPsk: channelPsk,
          byteBudget: byteBudget,
          sendBlob: sendBlob,
        ),
      );

  @override
  State<MediaComposer> createState() => _MediaComposerState();
}

enum _Stage { idle, encoding, ready, sending, done, failed }

class _MediaComposerState extends State<MediaComposer> {
  _Stage _stage = _Stage.idle;
  MediaTransferPlan? _plan;
  MediaSendRefusal? _refusal;
  int _sent = 0;
  MediaReceipt? _receipt;
  String? _sourceProblem;
  Set<int> _lost = <int>{};

  /// The upload in flight, so closing the sheet stops it.
  ///
  /// A photo is twenty datagrams with a 350 ms pacing, and a radio that answers
  /// TABLE_FULL keeps them queued; leaving the loop running after the sheet is
  /// gone means the app transmits a datagram every two seconds for a picture
  /// nobody is watching any more.
  MediaUpload? _upload;

  /// Why the send stopped without losing a chunk: capacity never came back.
  MediaSendResult? _stalled;

  Future<void> _pick(MediaPhotoOrigin origin) async {
    if (!widget.source.isAvailable) {
      setState(() => _sourceProblem = 'unavailable');
      return;
    }
    MediaPhoto? photo;
    try {
      photo = await widget.source.pick(origin: origin);
    } on MediaPhotoSourceFailure catch (e) {
      if (mounted) {
        setState(() => _sourceProblem = switch (e.problem) {
              MediaPhotoSourceProblem.unsupportedFormat => 'unsupported',
              MediaPhotoSourceProblem.unreadable => 'failed',
            });
      }
      return;
    }
    if (photo == null) {
      if (mounted) Navigator.of(context).maybePop(false);
      return;
    }
    await _prepare(photo);
  }

  Future<void> _prepare(MediaPhoto photo) async {
    setState(() {
      _stage = _Stage.encoding;
      _sourceProblem = null;
      _refusal = null;
    });
    final MediaPreparation outcome = await widget.service.prepare(
      photo,
      channelPsk: widget.channelPsk,
      byteBudget: widget.byteBudget,
    );
    if (!mounted) return;
    switch (outcome) {
      case MediaPrepared(plan: final MediaTransferPlan plan):
        setState(() {
          _plan = plan;
          _stage = _Stage.ready;
        });
      case MediaRefused(refusal: final MediaSendRefusal refusal):
        setState(() {
          _refusal = refusal;
          _stage = _Stage.idle;
        });
    }
  }

  Future<void> _send() async {
    final MediaTransferPlan? plan = _plan;
    if (plan == null) return;
    setState(() {
      _stage = _Stage.sending;
      _sent = 0;
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
      // The sheet closed: there is no surface left to tell.
    } finally {
      _upload = null;
    }
  }

  @override
  void dispose() {
    _upload?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MediaInterruptions? interruptions =
        context.watch<MediaInterruptions?>();
    final bool interrupted = interruptions?.any ?? false;
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    // D8.1: who receives this is the radio's own flood scope, not a choice this
    // sheet invents. Null while the answer is unknown, '' when the radio says
    // none is set — both are stated rather than guessed.
    final String? scope = context.watch<MeshcoreController?>()?.floodScopeName;
    return SafeArea(
      child: Padding(
        padding: skin.space.pad(5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l.mediaComposerTitle,
              style: TextStyle(
                  color: skin.color.fg,
                  fontSize: skin.type.sizeLg,
                  fontWeight: FontWeight.w600),
            ),
            SizedBox(height: skin.space.step(2)),
            Text(
              scope == null
                  ? l.mediaReachUnknown
                  : scope.isEmpty
                      ? l.mediaReachNoScope
                      : l.mediaReachScope(scope),
              key: const ValueKey<String>('media-reach'),
              style: TextStyle(
                  color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
            ),
            SizedBox(height: skin.space.step(5)),
            if (_sourceProblem != null)
              _Note(
                skin: skin,
                text: switch (_sourceProblem) {
                  'unavailable' => l.mediaSourceUnavailable,
                  'unsupported' => l.mediaSourceUnsupportedFormat,
                  _ => l.mediaSourceFailed,
                },
              ),
            if (_refusal != null) _refusalNote(skin, l),
            if (interrupted) _interruptedNote(skin, l),
            if (_stage == _Stage.idle && _plan == null && _sourceProblem == null)
              Row(
                children: <Widget>[
                  FilledButton.icon(
                    key: const ValueKey<String>('media-pick-camera'),
                    onPressed: () => _pick(MediaPhotoOrigin.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(l.mediaPickCamera),
                  ),
                  SizedBox(width: skin.space.step(3)),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('media-pick-gallery'),
                    onPressed: () => _pick(MediaPhotoOrigin.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(l.mediaPickGallery),
                  ),
                ],
              ),
            if (_stage == _Stage.encoding)
              Text(l.mediaEncoding,
                  style: TextStyle(
                      color: skin.color.fgMuted,
                      fontSize: skin.type.sizeSm)),
            if (_plan != null && _stage != _Stage.done) _planBlock(skin, l),
            if (_stage == _Stage.sending)
              Text(l.mediaSendingProgress(_sent, _plan!.cost.chunks),
                  style: TextStyle(
                      color: skin.color.fgMuted,
                      fontSize: skin.type.sizeSm)),
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
              _Note(skin: skin, text: l.mediaSendFailed(_lost.length)),
            SizedBox(height: skin.space.step(4)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(false),
                  child: Text(l.mediaClose),
                ),
                SizedBox(width: skin.space.step(3)),
                if (_stage == _Stage.ready || _stage == _Stage.failed)
                  FilledButton(
                    onPressed: _send,
                    child: Text(_stage == _Stage.failed
                        ? l.mediaRetrySend
                        : l.mediaSend),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A transfer the last process left unfinished. Said once, on the surface
  /// where the user would retry, rather than silently dropped.
  Widget _interruptedNote(MmSkin skin, AppLocalizations l) => Padding(
        padding: EdgeInsets.only(bottom: skin.space.step(3)),
        child: Row(
          children: <Widget>[
            Icon(Icons.info_outline, size: 16, color: skin.color.fgMuted),
            SizedBox(width: skin.space.step(2)),
            Expanded(
              child: Text(
                l.mediaInterruptedEarlier,
                style: TextStyle(
                    color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
              ),
            ),
            MmAction(
              dense: true,
              label: l.mediaInterruptedDismiss,
              onPressed: () =>
                  context.read<MediaInterruptions?>()?.acknowledge(),
            ),
          ],
        ),
      );

  Widget _refusalNote(MmSkin skin, AppLocalizations l) => _Note(
        skin: skin,
        alert: true,
        text: switch (_refusal!) {
          MediaSendRefusal.mediaOffOnPublic => l.mediaOffOnPublic,
          MediaSendRefusal.payloadUnusable => l.mediaPayloadUnusable,
          MediaSendRefusal.channelUnknown => l.mediaChannelUnknown,
        },
      );

  Widget _planBlock(MmSkin skin, AppLocalizations l) {
    final MediaTransferPlan plan = _plan!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.mediaCostLine(plan.cost.chunks, _airtime(plan.cost.airtime)),
          style: TextStyle(
              color: skin.color.fg, fontSize: skin.type.sizeBody),
        ),
        if (!plan.withinBudget)
          _Note(skin: skin, alert: true, text: l.mediaOverBudget),
        SizedBox(height: skin.space.step(3)),
      ],
    );
  }

  Widget _receiptBlock(MmSkin skin, AppLocalizations l, MediaReceipt r) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.mediaReceiptLine(r.chunks, r.resends),
              style:
                  TextStyle(color: skin.color.fg, fontSize: skin.type.sizeBody)),
          Text(l.mediaAcceptedNotDelivered,
              style: TextStyle(
                  color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
        ],
      );
}

String _airtime(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds} ms';
  final double seconds = d.inMilliseconds / 1000;
  return seconds < 10
      ? '${seconds.toStringAsFixed(1)} s'
      : '${seconds.round()} s';
}

class _Note extends StatelessWidget {
  const _Note({required this.skin, required this.text, this.alert = false});

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

/// The photo kind this build sends, so a caller does not pick it per surface.
const MediaKind kMediaImageKind = MediaKind.image;
