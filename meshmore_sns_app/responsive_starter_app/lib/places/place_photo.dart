// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../media/media_codec.dart';
import '../media/media_inbox.dart';
import '../media/media_photo.dart';
import '../media/media_transfer.dart';
import 'place.dart';

/// The reference a place carries to its picture.
///
/// The place report itself is text and has no room for bytes, and the spec is
/// explicit that a photo is fetched on demand and may never be fetched
/// (`meshmore-places-spec.md` §3, §13). So a place carries a reference — a
/// content hash, so the same picture is never stored twice, and the payload id
/// the media path uses.
final class PlacePhotoRef {
  const PlacePhotoRef({required this.contentHash, required this.payloadId});

  final String contentHash;
  final int payloadId;

  @override
  bool operator ==(Object other) =>
      other is PlacePhotoRef &&
      other.contentHash == contentHash &&
      other.payloadId == payloadId;

  @override
  int get hashCode => Object.hash(contentHash, payloadId);
}

/// A picture that was fetched for a place.
final class PlacePhoto {
  const PlacePhoto({
    required this.placeId,
    required this.ref,
    required this.photo,
    required this.fetchedAt,
  });

  final String placeId;
  final PlacePhotoRef ref;
  final MediaPhoto photo;
  final DateTime fetchedAt;
}

/// What the detail sheet says about a place's picture: bytes or no bytes.
///
/// A reference without bytes is not an error and must not read like one — the
/// photo may simply never have been fetched, which the spec calls out as the
/// normal case.
enum PlacePhotoState { present, notFetched }

/// The fetched pictures, keyed by place.
///
/// **A photo never extends a place's life.** The picture is a convenience on
/// top of the claim; the TTL belongs to the claim and to nothing else, and an
/// expired place takes its photo with it.
final class PlacePhotos {
  PlacePhotos({required DateTime Function() clock}) : _clock = clock;

  final DateTime Function() _clock;
  final Map<String, PlacePhoto> _byPlace = <String, PlacePhoto>{};

  PlacePhotoState stateFor(Place place) =>
      _byPlace.containsKey(place.id) ? PlacePhotoState.present : PlacePhotoState.notFetched;

  PlacePhoto? photoFor(Place place) => _byPlace[place.id];

  void keep(Place place, PlacePhoto photo) {
    _byPlace[place.id] = photo;
  }

  /// Drops the pictures of places that are no longer live. Called with the
  /// live set, so the store cannot outgrow the places it belongs to.
  int prune(Iterable<Place> live) {
    final Set<String> keep = <String>{
      for (final Place p in live)
        if (p.isLiveAt(_clock())) p.id,
    };
    final List<String> gone = <String>[
      for (final String id in _byPlace.keys)
        if (!keep.contains(id)) id,
    ];
    for (final String id in gone) {
      _byPlace.remove(id);
    }
    return gone.length;
  }
}

/// Why a fetch ended without a picture.
enum PlacePhotoFetchFailure {
  /// Nothing came back inside the window. The normal outcome on a busy mesh.
  timedOut,

  /// The payload arrived but the codec refused it.
  unreadable,

  /// There was no reference to ask about.
  noReference,
}

/// Builds the fetch for one place over the app's single inbound consumer.
///
/// The download is the inbox's, never a second one: two reassemblers would each
/// hold half the chunks and neither would complete. A place with no reference
/// gets null rather than a fetch that has nothing to ask for, which is the
/// state every place is in until the report carries one.
PlacePhotoFetch? placePhotoFetchFrom({
  required MediaInbox inbox,
  required Place place,
  required PlacePhotoRef? ref,
  required PlacePhotos photos,
  required DateTime Function() clock,
  required Future<void> Function() sendAsk,
  Future<void> Function(Uint8List request)? sendRequest,
}) {
  final PlacePhotoRef? reference = ref;
  if (reference == null) return null;
  return PlacePhotoFetch(
    place: place,
    ref: reference,
    download: inbox.download,
    codec: inbox.codec,
    photos: photos,
    clock: clock,
    sendAsk: sendAsk,
    sendRequest: sendRequest,
  );
}

/// One fetch: ask, take datagrams, decode, keep.
///
/// The caller feeds every inbound datagram to [accept]; the fetch resolves when
/// the payload completes, when the deadline passes, or when the codec refuses
/// it. A fetch is per place and short-lived, so nothing here is a long-running
/// listener.
final class PlacePhotoFetch {
  PlacePhotoFetch({
    required this.place,
    required this.ref,
    required this.download,
    required this.codec,
    required this.photos,
    required this.clock,
    required this.sendAsk,
    this.sendRequest,
    this.timeout = const Duration(seconds: 90),
  });

  final Place place;
  final PlacePhotoRef? ref;
  final MediaDownload download;
  final MediaCodec codec;
  final PlacePhotos photos;
  final DateTime Function() clock;

  /// Sends the ask. The wire form is the caller's: a text line naming the
  /// place, or a datagram, whichever the channel can carry.
  final Future<void> Function() sendAsk;

  final Duration timeout;

  /// Sends the missing-chunk request datagram. Null when the surface cannot
  /// send, in which case the progress view offers no ask.
  final Future<void> Function(Uint8List request)? sendRequest;

  /// The live progress of the transfer, so a surface can show what arrived
  /// without polling.
  final ValueNotifier<MediaDownloadProgress?> progress =
      ValueNotifier<MediaDownloadProgress?>(null);

  final Completer<PlacePhoto?> _done = Completer<PlacePhoto?>();

  PlacePhotoFetchFailure? _failure;

  PlacePhotoFetchFailure? get failure => _failure;

  /// True once the fetch is over, by any path.
  bool get finished => _done.isCompleted;

  /// Takes one inbound datagram. Returns what the download made of it, so a
  /// surface sharing this stream can keep its own accounting.
  MediaIntake accept(List<int> blob) {
    final MediaIntake intake = download.accept(blob);
    final PlacePhotoRef? reference = ref;
    if (reference != null) {
      progress.value = download.progressFor(reference.payloadId);
    }
    if (intake == MediaIntake.complete && !_done.isCompleted) {
      unawaited(_finish());
    }
    return intake;
  }

  /// Asks for the chunks that are still missing. Returns how many the request
  /// named, so the copy can say it rather than leaving the user guessing.
  Future<int> askForMissing() async {
    final PlacePhotoRef? reference = ref;
    final Future<void> Function(Uint8List)? send = sendRequest;
    if (reference == null || send == null) return 0;
    final Uint8List? request = download.requestBytesFor(reference.payloadId);
    if (request == null) return 0;
    final List<int> missing =
        download.progressFor(reference.payloadId)?.missing ?? <int>[];
    await send(request);
    return missing.length;
  }

  /// Releases the notifier. A fetch is short-lived, so its owner disposes it
  /// when the sheet closes rather than keeping a listener on a dead transfer.
  void dispose() {
    progress.dispose();
  }

  Future<PlacePhoto?> run() async {
    final PlacePhotoRef? reference = ref;
    if (reference == null) {
      _failure = PlacePhotoFetchFailure.noReference;
      _done.complete(null);
      return _done.future;
    }
    await sendAsk();
    final PlacePhoto? photo =
        await _done.future.timeout(timeout, onTimeout: () {
      _failure = PlacePhotoFetchFailure.timedOut;
      if (!_done.isCompleted) _done.complete(null);
      return null;
    });
    return photo;
  }

  Future<void> _finish() async {
    final PlacePhotoRef? reference = ref;
    if (reference == null) {
      _done.complete(null);
      return;
    }
    final Uint8List? payload = download.payloadFor(reference.payloadId);
    if (payload == null) {
      _done.complete(null);
      return;
    }
    try {
      final MediaPhoto image = await codec.decode(payload);
      if (!place.isLiveAt(clock())) {
        // The claim expired while the picture was arriving. The photo goes
        // with it: an expired place does not become fresh by gaining a photo.
        download.forget(reference.payloadId);
        _done.complete(null);
        return;
      }
      final PlacePhoto photo = PlacePhoto(
        placeId: place.id,
        ref: reference,
        photo: image,
        fetchedAt: clock(),
      );
      photos.keep(place, photo);
      download.forget(reference.payloadId);
      _done.complete(photo);
    } on MediaCodecException {
      _failure = PlacePhotoFetchFailure.unreadable;
      _done.complete(null);
    }
  }
}
