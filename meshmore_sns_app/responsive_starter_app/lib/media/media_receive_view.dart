// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../gen/app_localizations.dart';
import '../theme/mm_skin.dart';
import 'media_photo.dart';
import 'media_transfer.dart';

/// One inbound transfer as a surface shows it: how much arrived, what is
/// missing, and whether the ask went out.
///
/// The wording matters more than the bar. "Waiting for 3 packets" tells the
/// listener the transfer is alive; "incomplete" would read as failed, and for a
/// broadcast there is no failure to report — only an absence.
class MediaReceiveView extends StatelessWidget {
  const MediaReceiveView({
    super.key,
    required this.progress,
    this.requested,
    this.onAskForMissing,
  });

  final MediaDownloadProgress progress;

  /// How many packets a request covered, once one went out.
  final int? requested;

  /// Sends the request datagram. Null while the surface cannot send (no link),
  /// in which case the surface says so rather than showing a dead button.
  final Future<void> Function()? onAskForMissing;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (progress.complete)
          Text(l.mediaReceiveComplete,
              style: TextStyle(
                  color: skin.color.ok, fontSize: skin.type.sizeBody))
        else ...<Widget>[
          Text(
            l.mediaReceiveWaiting(
                progress.received, progress.count, progress.missing.length),
            style:
                TextStyle(color: skin.color.fg, fontSize: skin.type.sizeSm),
          ),
          SizedBox(height: skin.space.step(2)),
          ClipRect(
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 4,
              backgroundColor: skin.color.surfaceAlt,
              valueColor: AlwaysStoppedAnimation<Color>(skin.color.accent),
            ),
          ),
          SizedBox(height: skin.space.step(3)),
          if (requested != null)
            Text(l.mediaReceiveRequested(requested!),
                style: TextStyle(
                    color: skin.color.fgMuted, fontSize: skin.type.sizeSm))
          else if (onAskForMissing != null)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => onAskForMissing!(),
                child: Text(l.mediaReceiveAsk),
              ),
            ),
        ],
      ],
    );
  }
}

/// A decoded picture on screen.
///
/// The codec hands over straight RGBA, which is not what the engine wants to
/// upload — `ui.PixelFormat.rgba8888` is premultiplied — so the conversion
/// happens here, once, at the display boundary.
class MediaPhotoView extends StatefulWidget {
  const MediaPhotoView({super.key, required this.photo, this.height = 180});

  final MediaPhoto photo;
  final double height;

  @override
  State<MediaPhotoView> createState() => _MediaPhotoViewState();
}

class _MediaPhotoViewState extends State<MediaPhotoView> {
  ui.Image? _image;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(MediaPhotoView old) {
    super.didUpdateWidget(old);
    if (old.photo != widget.photo) {
      _image?.dispose();
      _image = null;
      _failed = false;
      _decode();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    final MediaPhoto premultiplied = widget.photo.premultiplied();
    try {
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
          premultiplied.rgba);
      final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: premultiplied.width,
        height: premultiplied.height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final ui.Codec codec = await descriptor.instantiateCodec();
      final ui.FrameInfo frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MmSkin skin = context.skin;
    final ui.Image? image = _image;
    if (_failed) {
      return Text(l.mediaDecodeFailed,
          style: TextStyle(color: skin.color.alert, fontSize: skin.type.sizeSm));
    }
    if (image == null) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: SizedBox(
            width: skin.type.sizeLg,
            height: skin.type.sizeLg,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Semantics(
      label: l.mediaPhotoSemantics,
      image: true,
      child: SizedBox(
        height: widget.height,
        child: RawImage(
          image: image,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
