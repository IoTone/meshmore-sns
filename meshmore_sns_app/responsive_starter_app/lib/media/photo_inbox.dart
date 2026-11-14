// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../util/safe_notifier.dart';
import 'media_chunk.dart';
import 'media_inbox.dart';

/// One picture that arrived whole on a channel.
///
/// The bytes are kept as they travelled, not as decoded pixels: a 1600-byte
/// AVIF is 256×192 of RGBA once decoded, which is 196 KB, and a reader who looks
/// at one picture in ten would pay that for all ten. [MediaPhotoView] decodes
/// the one on screen.
final class ReceivedPhoto {
  const ReceivedPhoto({
    required this.payloadId,
    required this.channelIndex,
    required this.receivedAt,
    required this.bytes,
  });

  final int payloadId;
  final int channelIndex;
  final DateTime receivedAt;

  /// The wire payload: the encoded picture, exactly as it arrived.
  final Uint8List bytes;

  int get byteCount => bytes.length;

  @override
  String toString() =>
      'ReceivedPhoto($payloadId, channel $channelIndex, $byteCount B)';
}

/// The pictures this session has taken off the channels.
///
/// **This is the half that was missing.** A photo sent on a channel was
/// reassembled by [MediaInbox] and then dropped: the inbox hands a completed
/// payload to whoever claimed it, and nothing claimed an image. A voice note had
/// a home (`VoiceInbox`) because it has no surface waiting for it; a picture had
/// none, so the sender's receipt said "accepted" and the receiver saw nothing at
/// all — no row, no error, no trace. The place-photo path is a *pull* that asks
/// for one payload by id, which is a different thing and is not reachable from a
/// channel send.
///
/// So this is the same shape as the voice inbox, for the same reason: a bounded
/// list of the newest [capacity] pictures, per channel, kept for the life of the
/// process. Nothing is persisted — a picture is as durable as the session, which
/// the surface says — because the alternative is a sealed store full of images
/// for messages that are already spent.
final class PhotoInbox extends ChangeNotifier with SafeNotifier {
  PhotoInbox({
    required Stream<MediaInboxPayload> completed,
    this.capacity = 8,
  }) : _completed = completed;

  /// How many pictures the session keeps. Eight is a walk's worth of a channel
  /// and bounds the memory at about 13 KB of payload at the standard size.
  final int capacity;

  final Stream<MediaInboxPayload> _completed;
  final List<ReceivedPhoto> _photos = <ReceivedPhoto>[];
  StreamSubscription<MediaInboxPayload>? _subscription;

  /// Newest first.
  List<ReceivedPhoto> get photos => List<ReceivedPhoto>.unmodifiable(_photos);

  List<ReceivedPhoto> photosFor(int channelIndex) => <ReceivedPhoto>[
        for (final ReceivedPhoto p in _photos)
          if (p.channelIndex == channelIndex) p,
      ];

  int countFor(int channelIndex) {
    int n = 0;
    for (final ReceivedPhoto photo in _photos) {
      if (photo.channelIndex == channelIndex) n++;
    }
    return n;
  }

  ReceivedPhoto? photo(int payloadId) {
    for (final ReceivedPhoto p in _photos) {
      if (p.payloadId == payloadId) return p;
    }
    return null;
  }

  /// Starts reading completed payloads. Idempotent, so a rebuild cannot listen
  /// twice and file every picture twice with it.
  void start() {
    _subscription ??= _completed.listen(_onPayload);
  }

  void _onPayload(MediaInboxPayload payload) {
    // One inbox serves every media kind; a voice note is somebody else's row.
    if (payload.kind != MediaKind.image) return;
    if (photo(payload.payloadId) != null) return;
    if (payload.bytes.isEmpty) return;
    _photos.insert(
      0,
      ReceivedPhoto(
        payloadId: payload.payloadId,
        channelIndex: payload.channelIndex,
        receivedAt: payload.receivedAt,
        bytes: payload.bytes,
      ),
    );
    while (_photos.length > capacity) {
      _photos.removeLast();
    }
    notifyListeners();
  }

  /// Drops every picture. The storage block's "delete everything" calls this,
  /// so a clear that says it removed the media inbox removes what is on screen
  /// as well as what is on disk.
  void clear() {
    if (_photos.isEmpty) return;
    _photos.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    // Idempotent: a tab can be disposed while a transfer is still completing,
    // and a second dispose from a teardown must not assert.
    if (isDisposed) return;
    final StreamSubscription<MediaInboxPayload>? sub = _subscription;
    _subscription = null;
    if (sub != null) unawaited(sub.cancel());
    super.dispose();
  }
}
