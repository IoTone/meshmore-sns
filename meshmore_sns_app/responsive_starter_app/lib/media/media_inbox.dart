// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore/meshcore.dart';

import '../meshcore/channel_datagram.dart';
import 'media_chunk.dart';
import 'media_codec.dart';
import 'media_transfer.dart';

/// A payload that arrived whole.
///
/// The bytes are the reassembled payload, not a chunk: whatever owns the
/// payload's meaning decodes them. Nothing here knows what a photo is. The
/// layer that does sits above this one, and the dependency must not point the
/// other way, or a place's meaning would live in the media path.
final class MediaInboxPayload {
  const MediaInboxPayload({
    required this.payloadId,
    required this.kind,
    required this.channelIndex,
    required this.receivedAt,
    required this.bytes,
  });

  final int payloadId;
  final MediaKind kind;
  final int channelIndex;
  final DateTime receivedAt;
  final Uint8List bytes;

  @override
  String toString() =>
      'MediaInboxPayload($payloadId, ${kind.name}, ${bytes.length} B)';
}

/// What one inbound datagram did.
///
/// A refusal and a foreign type are different answers — one is a datagram this
/// build cannot use, the other is a datagram for another layer — and so is a
/// duplicate, which is normal traffic because the radio retries.
enum MediaInboxOutcome {
  completed,
  chunk,
  request,
  duplicate,
  refused,
  foreignType,
  foreignChannel,

  /// Room had to be made: a seventeenth transfer evicted an older one, which
  /// will now never complete. Reported rather than swallowed, because the
  /// other side is waiting on a payload this phone stopped tracking.
  evicted,
}

/// The app's one inbound consumer of media datagrams.
///
/// The radio delivers `0x1B` channel datagrams to the controller; every media
/// payload is one of them, and before this class nothing subscribed, so a
/// picture could be sent and never reassembled. One inbox, one subscription,
/// one reassembler: two consumers would each hold half the chunks.
///
/// The hand-off is a claim. A surface that is waiting for one payload registers
/// its id and gets the bytes when the last chunk lands; a payload nobody
/// claimed still reassembles and still reports completion, because a picture
/// arriving for a place the user closed is not an error.
final class MediaInbox {
  MediaInbox({
    required Stream<ChannelDatagram> datagrams,
    required this.codec,
    required DateTime Function() clock,
    this.dataType = kChannelDataTypeDev,
    this.channelIndex,
    this.onCompleted,
    MediaDownload? download,
  })  : _datagrams = datagrams,
        _clock = clock,
        download = download ?? MediaDownload();

  /// The app-data type a media payload travels in. The `0xFFxx` band exists
  /// because the firmware forwards a type it does not know, so a new type is
  /// safe before any allocation.
  final int dataType;

  /// When set, only this channel slot is read. Null reads every slot: a photo
  /// can arrive on a channel the reader is not looking at, and dropping it
  /// there would make the fetch look like a loss.
  final int? channelIndex;

  /// Called for every payload that completes, claimed or not.
  final void Function(MediaInboxPayload payload)? onCompleted;

  final MediaDownload download;
  final MediaCodec codec;

  final Stream<ChannelDatagram> _datagrams;
  final DateTime Function() _clock;
  final Map<int, void Function(MediaInboxPayload)> _claims =
      <int, void Function(MediaInboxPayload)>{};
  final StreamController<MediaInboxPayload> _completed =
      StreamController<MediaInboxPayload>.broadcast();

  StreamSubscription<ChannelDatagram>? _subscription;
  MediaInboxOutcome? _lastOutcome;
  int _foreignType = 0;
  int _refused = 0;
  int _completedCount = 0;

  /// Payloads that arrived whole, for a surface that watches rather than
  /// claims.
  Stream<MediaInboxPayload> get completed => _completed.stream;

  MediaInboxOutcome? get lastOutcome => _lastOutcome;

  /// Datagrams whose type is not [dataType]: another layer's traffic.
  int get foreignDatagrams => _foreignType;

  /// Datagrams that carried a media type but not a media chunk.
  int get refusedDatagrams => _refused;

  int get completedPayloads => _completedCount;

  int _evictedTransfers = 0;

  /// Transfers dropped to make room for newer ones. A surface that shows an
  /// inbound picture reads this: a transfer that stopped arriving because
  /// another one started is not the same as a lost packet.
  int get evictedTransfers => _evictedTransfers;

  bool get listening => _subscription != null;

  /// Starts reading the radio's datagrams. Idempotent, so a rebuild cannot
  /// subscribe twice and reassemble every chunk twice with it.
  void start() {
    _subscription ??= _datagrams.listen(_onDatagram);
  }

  /// Registers interest in one payload. The handler runs once, with the whole
  /// payload, and is dropped afterwards.
  void claim(int payloadId, void Function(MediaInboxPayload payload) handler) {
    _claims[payloadId] = handler;
  }

  void release(int payloadId) => _claims.remove(payloadId);

  MediaDownloadProgress? progressFor(int payloadId) =>
      download.progressFor(payloadId);

  /// The datagram that asks the sender for exactly what is missing, or null
  /// when nothing is.
  Uint8List? requestBytesFor(int payloadId) =>
      download.requestBytesFor(payloadId);

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _claims.clear();
    if (!_completed.isClosed) await _completed.close();
  }

  void _onDatagram(ChannelDatagram datagram) {
    if (datagram.dataType != dataType) {
      _foreignType++;
      _lastOutcome = MediaInboxOutcome.foreignType;
      return;
    }
    final int? slot = channelIndex;
    if (slot != null && datagram.channelIndex != slot) {
      _lastOutcome = MediaInboxOutcome.foreignChannel;
      return;
    }
    final int evictionsBefore = download.reassembler.evictions;
    final MediaIntake intake = download.accept(datagram.blob, now: _clock());
    if (download.reassembler.evictions > evictionsBefore) {
      _evictedTransfers++;
      _lastOutcome = MediaInboxOutcome.evicted;
      return;
    }
    switch (intake) {
      case MediaIntake.chunk:
        _lastOutcome = MediaInboxOutcome.chunk;
      case MediaIntake.duplicate:
        _lastOutcome = MediaInboxOutcome.duplicate;
      case MediaIntake.request:
        _lastOutcome = MediaInboxOutcome.request;
      case MediaIntake.refused:
        _refused++;
        _lastOutcome = MediaInboxOutcome.refused;
      case MediaIntake.complete:
        _lastOutcome = MediaInboxOutcome.completed;
        _handOff(datagram);
    }
  }

  /// Hands a completed payload to whoever claimed it.
  ///
  /// The payload id is read back out of the datagram's own header: the header
  /// is the only field that names the payload the radio delivered, and the
  /// download's transfer list says nothing about which one just completed.
  void _handOff(ChannelDatagram datagram) {
    final MediaChunk? chunk = MediaChunkCodec.parse(datagram.blob).chunk;
    if (chunk == null) return;
    final Uint8List? bytes = download.payloadFor(chunk.payloadId);
    if (bytes == null) return;
    final MediaInboxPayload payload = MediaInboxPayload(
      payloadId: chunk.payloadId,
      kind: chunk.kind,
      channelIndex: datagram.channelIndex,
      receivedAt: datagram.receivedAt,
      bytes: bytes,
    );
    _completedCount++;
    final void Function(MediaInboxPayload)? handler =
        _claims.remove(chunk.payloadId);
    if (!_completed.isClosed) _completed.add(payload);
    onCompleted?.call(payload);
    handler?.call(payload);
    // The bytes are handed on, so the reassembler stops holding them. The
    // completion memory keeps the id, so a replayed chunk cannot rebuild the
    // payload and hand it on a second time.
    download.forget(chunk.payloadId);
  }
}
