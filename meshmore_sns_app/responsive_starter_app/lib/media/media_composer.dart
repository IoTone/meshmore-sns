// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';
import '../meshcore/channel_datagram.dart';
import '../theme/mm_skin.dart';
import 'media_chunk.dart';
import 'media_photo.dart';
import 'media_send_policy.dart';
import 'media_sender.dart';
import 'media_transfer.dart';

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
  Future<MediaPhoto?> pick();
}

/// The source refused or could not read the picture.
final class MediaPhotoSourceFailure implements Exception {
  const MediaPhotoSourceFailure(this.reason);

  final String reason;

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
  Future<MediaPhoto?> pick() async => null;
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

  @override
  void initState() {
    super.initState();
    // The sheet exists to send a photo, so it asks for one immediately; a
    // second tap to reach a picker behind a sheet is one tap too many.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  Future<void> _pick() async {
    if (!widget.source.isAvailable) {
      setState(() => _sourceProblem = 'unavailable');
      return;
    }
    MediaPhoto? photo;
    try {
      photo = await widget.source.pick();
    } on MediaPhotoSourceFailure {
      if (mounted) setState(() => _sourceProblem = 'failed');
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
    });
    final MediaUpload upload = widget.service.upload(plan);
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
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
            SizedBox(height: skin.space.step(5)),
            if (_sourceProblem != null)
              _Note(
                skin: skin,
                text: _sourceProblem == 'unavailable'
                    ? l.mediaSourceUnavailable
                    : l.mediaSourceFailed,
              ),
            if (_refusal != null) _refusalNote(skin, l),
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
            if (_stage == _Stage.failed)
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
