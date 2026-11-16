// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';
import '../ui/mm_components.dart';
import '../theme/mm_skin.dart';
import 'media_codec.dart';
import 'media_photo.dart';
import 'media_receive_view.dart';
import 'photo_inbox.dart';

/// The pictures this session has taken off the current channel.
///
/// A surface of its own rather than rows in the timeline, for the reason the
/// voice notes sheet gives: the timeline is the sealed history, one row per text
/// message, and a picture payload is neither text nor durable — it lives as long
/// as the process. Putting it in the timeline would mean either persisting an
/// image per message or showing a row that is dead after a restart.
///
/// Each picture is decoded when it is shown, from the bytes that arrived, and a
/// payload this build cannot decode says so in its own row rather than taking
/// the sheet down with it.
class ReceivedPhotosSheet extends StatefulWidget {
  const ReceivedPhotosSheet({
    super.key,
    required this.photos,
    required this.codec,
    this.foreign = 0,
  });

  /// The pictures for the channel this sheet was opened from, newest first.
  final List<ReceivedPhoto> photos;
  final MediaCodec codec;

  /// Pictures that arrived in a codec this build does not carry (AEIC, MeshCore
  /// Open's neural codec). Counted rather than dropped silently: a reader who
  /// sees nothing at all cannot tell "nobody sent a picture" from "this build
  /// cannot open the one that arrived".
  final int foreign;

  static Future<void> show(
    BuildContext context, {
    required List<ReceivedPhoto> photos,
    required MediaCodec codec,
    int foreign = 0,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ReceivedPhotosSheet(
            photos: photos, codec: codec, foreign: foreign),
      );

  @override
  State<ReceivedPhotosSheet> createState() => _ReceivedPhotosSheetState();
}

class _ReceivedPhotosSheetState extends State<ReceivedPhotosSheet> {
  /// Decoded pictures, by payload id. Decoding is a native call, so it happens
  /// once per picture and not once per rebuild.
  final Map<int, MediaPhoto> _decoded = <int, MediaPhoto>{};
  final Set<int> _failed = <int>{};

  @override
  void initState() {
    super.initState();
    for (final ReceivedPhoto photo in widget.photos) {
      _decode(photo);
    }
  }

  Future<void> _decode(ReceivedPhoto photo) async {
    try {
      final MediaPhoto decoded = await widget.codec.decode(photo.bytes);
      if (mounted) setState(() => _decoded[photo.payloadId] = decoded);
    } catch (_) {
      // A payload this build cannot read is one row's problem, not the sheet's.
      if (mounted) setState(() => _failed.add(photo.payloadId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final MaterialLocalizations material = MaterialLocalizations.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: skin.space.pad(5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l.mediaReceivedTitle,
              style: TextStyle(
                  color: skin.color.fg,
                  fontSize: skin.type.sizeLg,
                  fontWeight: FontWeight.w600),
            ),
            SizedBox(height: skin.space.step(2)),
            Text(
              l.mediaReceivedKept(widget.photos.length),
              style: TextStyle(
                  color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
            ),
            // A picture in a codec this build does not carry is named here
            // rather than dropped: the count existed and no screen read it, so
            // an AEIC picture arriving looked exactly like nobody sending one.
            if (widget.foreign > 0) ...<Widget>[
              SizedBox(height: skin.space.step(2)),
              Text(
                l.mediaReceivedForeign(widget.foreign),
                key: const ValueKey<String>('received-photos-foreign'),
                style: TextStyle(
                    color: skin.color.fgMuted, fontSize: skin.type.sizeSm),
              ),
            ],
            SizedBox(height: skin.space.step(4)),
            for (final ReceivedPhoto photo in widget.photos)
              Padding(
                key: ValueKey<String>('received-photo-${photo.payloadId}'),
                padding: EdgeInsets.only(bottom: skin.space.step(4)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      material.formatTimeOfDay(
                          TimeOfDay.fromDateTime(photo.receivedAt)),
                      style: TextStyle(
                          color: skin.color.fgMuted,
                          fontSize: skin.type.sizeSm),
                    ),
                    SizedBox(height: skin.space.step(1)),
                    if (_failed.contains(photo.payloadId))
                      Text(l.mediaDecodeFailed,
                          style: TextStyle(
                              color: skin.color.alertInk,
                              fontSize: skin.type.sizeSm))
                    else if (_decoded[photo.payloadId] case final MediaPhoto p)
                      MediaPhotoView(photo: p)
                    else
                      SizedBox(
                        height: skin.space.step(9) * 5,
                        child: Center(
                          child: SizedBox(
                            width: skin.type.sizeLg,
                            height: skin.type.sizeLg,
                            child:
                                const CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: MmAction(
                key: const ValueKey<String>('received-photos-close'),
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
