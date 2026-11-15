// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../gen/app_localizations.dart';
import '../meshcore/meshcore_controller.dart';
import '../meshcore/airtime_meter.dart';
import '../meshcore/channel_datagram.dart';
import '../theme/mm_skin.dart';
import '../ui/mm_components.dart';
import 'media_chunk.dart';
import 'media_journal.dart';
import 'media_offer.dart';
import 'aeic/aeic_chunk.dart';
import 'aeic/onnx_codec.dart' show AeicUnavailable;
import 'aeic_codec_service.dart';
import 'media_mode.dart';
import 'media_photo.dart';
import 'mp1.dart';
import 'media_prefs.dart';
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
  Future<MediaPhoto?> pick(
      {MediaPhotoOrigin origin = MediaPhotoOrigin.gallery});
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
    required this.offers,
    this.sendDatagram,
    this.aeic,
    this.senderPrefix,
  });

  final MediaTransferService service;
  final MediaPhotoSource source;

  /// The channel's secret. Media is off on the well-known Public channel by
  /// default, and the rule is keyed on the secret rather than the name.
  final List<int>? channelPsk;

  /// Target bytes for the encoded picture. The plan reports when the encoder
  /// could not reach it rather than failing silently.
  final int byteBudget;

  /// The radio call for the one preview datagram.
  ///
  /// A picture is announced, not uploaded: this is the only thing that reaches
  /// the channel, and it is one datagram. The pixels wait in [offers] until
  /// somebody asks for them, and then travel as a direct record the firmware
  /// will not flood.
  final Future<ChannelDataSendResult> Function(Uint8List blob) sendBlob;

  /// Where the full payload waits to be served, with a TTL.
  final MediaOfferStore offers;

  /// The channel-datagram call with an explicit data type, for the neural mode.
  ///
  /// Null when the caller has no radio: the mode then refuses rather than
  /// pretending. It is separate from [sendBlob] because AEIC travels under its
  /// own data type (0xAE1C) and a preview under MeshPix's (0xFF50).
  final Future<ChannelDataSendResult> Function(int dataType, Uint8List blob)?
      sendDatagram;

  /// The codec behind the neural mode. Null in a build without it.
  final AeicCodecService? aeic;

  /// Two bytes of this node's public key, which every AEIC chunk carries.
  final int? senderPrefix;

  /// Opens the composer; resolves to true when a picture was sent.
  static Future<bool?> show(
    BuildContext context, {
    required MediaTransferService service,
    required MediaPhotoSource source,
    required List<int>? channelPsk,
    required int byteBudget,
    required Future<ChannelDataSendResult> Function(Uint8List blob) sendBlob,
    required MediaOfferStore offers,
    Future<ChannelDataSendResult> Function(int, Uint8List)? sendDatagram,
    AeicCodecService? aeic,
    int? senderPrefix,
  }) =>
      showModalBottomSheet<bool>(
        context: context,
        // A grip and a close button, the two ways out every other sheet in this
        // app offers. The sheet had neither: it could only be dismissed by
        // swiping a region that did not look draggable, which reads as a sheet
        // that is stuck.
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => MediaComposer(
          service: service,
          source: source,
          channelPsk: channelPsk,
          byteBudget: byteBudget,
          sendBlob: sendBlob,
          offers: offers,
          sendDatagram: sendDatagram,
          aeic: aeic,
          senderPrefix: senderPrefix,
        ),
      );

  @override
  State<MediaComposer> createState() => _MediaComposerState();
}

enum _Stage { idle, encoding, ready, sending, done, failed }

class _MediaComposerState extends State<MediaComposer> {
  _Stage _stage = _Stage.idle;
  MediaTransferPlan? _plan;
  MediaPhoto? _photo;
  static int _offerId = 1;
  MediaSendRefusal? _refusal;
  int _sent = 0;
  MediaReceipt? _receipt;
  String? _sourceProblem;
  final Set<int> _lost = <int>{};

  /// The photo mode at the moment the composer opened. Read once so the line the
  /// reader sees and the behaviour of the send cannot disagree if the preference
  /// changes behind the sheet. Null until the preference has been read, which is
  /// the same answer as the default.
  MediaMode? _modeRead;
  MediaMode get _mode => _modeRead ?? MediaMode.onRequest;

  @override
  void initState() {
    super.initState();
    // The read that makes the setting real. Without it `_modeRead` stayed null
    // for the life of the sheet, so every send took the on-request path and the
    // line under the picture named a mode the reader had not chosen.
    MediaModePrefs.photoMode().then((MediaMode m) {
      if (mounted) setState(() => _modeRead = m);
    });
  }

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
    // `_pick` awaits the platform picker before calling this, and the sheet can
    // be dismissed while the picker is up.
    if (!mounted) return;
    setState(() {
      _stage = _Stage.encoding;
      _photo = photo;
      _sourceProblem = null;
      _refusal = null;
    });
    // Grey unless the owner asked for colour: two of the three channels a
    // colour picture spends are the cheapest third of the data to give up, and
    // this is the one place that decides it for every send.
    final bool color = await MediaPrefs.colorPhotos();
    if (!mounted) return;
    final MediaPreparation outcome = await widget.service.prepare(
      photo,
      channelPsk: widget.channelPsk,
      byteBudget: widget.byteBudget,
      grayscale: !color,
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
    final MediaPhoto? photo = _photo;
    if (plan == null || photo == null) return;
    // What the reader chose in Settings → Chat & photos decides how far the
    // pixels go.
    // Preview-only means the preview *is* the picture: the payload is not held,
    // so no request can pull the full one later. The neural mode goes its own way
    // below, because it does not use this framing at all.
    final MediaMode mode = _mode;
    if (mode == MediaMode.neural) {
      await _sendNeural(photo);
      return;
    }
    // The id travels in the preview and comes back in a request, so it has to
    // be unique among the offers this session is holding.
    final int id = _offerId++;
    final Uint8List? preview = encodeMp1Preview(
      photo,
      transferId: id,
      upgradeChunks: plan.cost.chunks,
    );
    if (preview == null) {
      // The preview ladder could not fit 163 bytes: the picture is too busy for
      // a palette this small. That is a refusal, not a crash.
      setState(() {
        _refusal = MediaSendRefusal.payloadUnusable;
        _stage = _Stage.ready;
      });
      return;
    }
    setState(() {
      _stage = _Stage.sending;
      _sent = 0;
      _stalled = null;
    });
    try {
      final ChannelDataSendResult result = await widget.sendBlob(preview);
      if (!mounted) return;
      if (!result.accepted) {
        setState(() {
          _stalled = MediaSendResult.refused;
          _stage = _Stage.failed;
        });
        return;
      }
      // Preview only: nothing is held, so the one datagram is the whole send.
      if (mode == MediaMode.preview) {
        setState(() => _stage = _Stage.done);
        return;
      }
      // The pixels are held, not sent. Fifteen minutes is long enough for a
      // reader who saw the preview to tap it and short enough that a phone is
      // not holding a picture it will never send again.
      widget.offers.add(MediaOffer(
        id: id,
        payload: plan.payload,
        chunkCount: plan.cost.chunks,
        createdAt: DateTime.now(),
      ));
      setState(() => _stage = _Stage.done);
    } on AirtimeRefused {
      if (!mounted) return;
      setState(() {
        _stalled = MediaSendResult.budgetRefused;
        _stage = _Stage.failed;
      });
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
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l.mediaComposerTitle,
                    style: TextStyle(
                        color: skin.color.fg,
                        fontSize: skin.type.sizeLg,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('media-close'),
                  tooltip: l.mediaClose,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            SizedBox(height: skin.space.step(3)),
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
            if (_stage == _Stage.idle &&
                _plan == null &&
                _sourceProblem == null)
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
                      color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
            _modeLine(skin, l),
            if (_plan != null && _stage != _Stage.done) _planBlock(skin, l),
            // Who receives it is the radio's flood scope, and it belongs beside
            // the cost: the two together are the whole decision. It used to be
            // the first line of the sheet, above the buttons, where it read as a
            // disclaimer rather than as part of the price.
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
            if (_stage == _Stage.sending)
              Text(l.mediaSendingProgress(_sent, _plan!.cost.chunks),
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
          MediaSendRefusal.fullPictureOnChannel => l.mediaFullPictureOnChannel,
        },
      );

  /// What the reader's photo mode means for this send, and the way to change it.
  ///
  /// The mode lives in Settings → Chat & photos, which is one screen away, and a
  /// reader who has just taken a picture should not have to leave the composer to
  /// find out that the pixels are not going anywhere.
  /// Encode with the neural codec and put the stream on the channel.
  ///
  /// The bitstream is about 156 bytes, so it is one or two data chunks plus one
  /// parity chunk: the whole picture is on the air in two or three datagrams,
  /// which is why this mode exists at all. The chunk framing names the source
  /// aspect ratio so the receiver can letterbox the 512-square back to the shape
  /// the photo actually had.
  Future<void> _sendNeural(MediaPhoto photo) async {
    final AeicCodecService? codec = widget.aeic;
    final Future<ChannelDataSendResult> Function(int, Uint8List)? send =
        widget.sendDatagram;
    if (codec == null || send == null) {
      setState(() {
        _refusal = MediaSendRefusal.payloadUnusable;
        _stage = _Stage.ready;
      });
      return;
    }
    setState(() {
      _stage = _Stage.sending;
      _sent = 0;
      _stalled = null;
    });
    try {
      final DateTime started = DateTime.now();
      final Uint8List bitstream =
          await codec.encodeRgb(photo.rgba, photo.width, photo.height);
      final AeicChunkSet set = buildAeicChunks(
        payload: bitstream,
        metadata: AeicStreamMetadata(
          rate: AeicRate.standard,
          aspectCode: aeicAspectCodeFor(photo.width, photo.height),
        ),
        // Two bytes of the local key: a receiver keys its reassembly on this and
        // the sender can be named from it. Zero is the honest answer when the
        // radio has not reported a key yet, and it matches no real sender.
        senderPrefix: widget.senderPrefix ?? 0,
        imageId: _nextImageId(),
      );
      var sent = 0;
      for (final Uint8List blob in set.blobs) {
        final ChannelDataSendResult result =
            await send(kAeicImageDataType, blob);
        if (!result.accepted) {
          if (!mounted) return;
          setState(() {
            _stalled = MediaSendResult.refused;
            _stage = _Stage.failed;
          });
          return;
        }
        sent++;
        if (mounted) setState(() => _sent = sent);
      }
      if (!mounted) return;
      setState(() {
        _receipt = MediaReceipt(
          chunks: sent,
          resends: 0,
          elapsed: DateTime.now().difference(started),
        );
        _stage = _Stage.done;
      });
    } on AeicUnavailable {
      if (!mounted) return;
      setState(() {
        _refusal = MediaSendRefusal.payloadUnusable;
        _stage = _Stage.ready;
      });
    } on AirtimeRefused {
      if (!mounted) return;
      setState(() {
        _stalled = MediaSendResult.budgetRefused;
        _stage = _Stage.failed;
      });
    }
  }

  /// Eight bits of image id, so a receiver can tell two streams on one channel
  /// apart. Wrapping is fine: the reassembly key also carries the sender and the
  /// channel, and entries expire after a minute.
  static int _imageIdCounter = 1;
  int _nextImageId() => (_imageIdCounter++) & 0xFF;

  Widget _modeLine(MmSkin skin, AppLocalizations l) {
    final MediaMode mode = _mode;
    final String text = mode == MediaMode.preview
        ? l.photoModeLinePreview
        : l.photoModeLine(_modeLabel(l, mode), mode.bytes);
    // One line for the fact, then the link on its own line. Side by side, the
    // link took a third of the width and the mode wrapped under it, which read
    // as a button sitting on top of a sentence.
    return Padding(
      padding: EdgeInsets.only(bottom: skin.space.step(2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(text,
              key: const ValueKey<String>('photo-mode-line'),
              style: TextStyle(
                  color: skin.color.fgMuted, fontSize: skin.type.sizeSm)),
          Align(
            alignment: Alignment.centerRight,
            child: MmAction(
              key: const ValueKey<String>('photo-mode-settings'),
              dense: true,
              label: l.photoModeSettings,
              onPressed: () => context.push('/settings/chat'),
            ),
          ),
        ],
      ),
    );
  }

  String _modeLabel(AppLocalizations l, MediaMode m) => switch (m) {
        MediaMode.preview => l.photoModePreview,
        MediaMode.onRequest => l.photoModeOnRequest,
        MediaMode.neural => l.codecTitle,
      };

  Widget _planBlock(MmSkin skin, AppLocalizations l) {
    final MediaTransferPlan plan = _plan!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.mediaCostLine(plan.cost.chunks, _airtime(plan.cost.airtime)),
          style: TextStyle(color: skin.color.fg, fontSize: skin.type.sizeBody),
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
              style: TextStyle(
                  color: skin.color.fg, fontSize: skin.type.sizeBody)),
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
