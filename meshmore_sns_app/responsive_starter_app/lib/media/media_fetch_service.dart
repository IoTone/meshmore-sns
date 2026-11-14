// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:typed_data';

import '../meshcore/channel_datagram.dart';
import '../meshcore/chat_message.dart';
import '../meshcore/discovered_node.dart';
import '../meshcore/meshcore_controller.dart';
import 'media_fetch.dart';
import 'media_offer.dart';
import 'mp1.dart';

/// One preview that arrived on a channel, with what it takes to ask for more.
final class PhotoAnnouncement {
  const PhotoAnnouncement({
    required this.image,
    required this.channelIdx,
    required this.at,
    required this.upgradeChunks,
  });

  final Mp1Image image;
  final int channelIdx;
  final DateTime at;

  /// How many records the full picture needs. Zero means the sender has
  /// nothing more to offer.
  final int upgradeChunks;

  int get id => image.transferId;
}

/// Both halves of "a picture is fetched, never broadcast".
///
/// The receiving half listens on the channel for two things: an MP1 preview
/// (`0xFF50`) and a request line (`[IMG1:<id>:<key>]`). The sending half sees a
/// request for an offer it is still holding and answers it with raw records
/// addressed to the requester's path.
///
/// Nothing here can flood a picture. The announcement is one datagram the caller
/// sent, and the pixels go out as `CMD_SEND_RAW_DATA`, which the firmware
/// refuses to flood (`MyMesh.cpp:1519-1533`). A requester the radio has no path
/// for cannot be served, and is told so rather than being flooded at.
final class MediaFetchService {
  MediaFetchService({
    required this.mc,
    required this.offers,
  });

  final MeshcoreController mc;
  final MediaOfferStore offers;

  final StreamController<PhotoAnnouncement> _announcements =
      StreamController<PhotoAnnouncement>.broadcast();
  final List<PhotoAnnouncement> _held = <PhotoAnnouncement>[];
  final Map<int, MediaFetchInbox> _inbox = <int, MediaFetchInbox>{};
  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];

  /// Previews heard this session, newest last, bounded to sixteen.
  List<PhotoAnnouncement> get announcements =>
      List<PhotoAnnouncement>.unmodifiable(_held);

  Stream<PhotoAnnouncement> get announcementsStream => _announcements.stream;

  /// One broadcast per picture, not per datagram.
  void attach() {
    _subs.add(mc.channelDatagramStream.listen(_onDatagram));
    _subs.add(mc.incomingChannelMessages.listen(_onChannelMessage));
  }

  Future<void> dispose() async {
    for (final StreamSubscription<Object?> s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _announcements.close();
  }

  void _onDatagram(ChannelDatagram d) {
    if (d.dataType != kMp1DataType) return;
    final Mp1DecodeResult out = decodeMp1Preview(d.blob);
    final Mp1Image? image = out.image;
    if (image == null) return;
    final PhotoAnnouncement a = PhotoAnnouncement(
      image: image,
      channelIdx: d.channelIndex,
      at: d.receivedAt,
      upgradeChunks: image.upgradeChunks,
    );
    // A sender that retried the preview must not appear twice.
    _held.removeWhere((PhotoAnnouncement x) => x.id == a.id);
    _held.add(a);
    while (_held.length > 16) {
      _held.removeAt(0);
    }
    if (!_announcements.isClosed) _announcements.add(a);
  }

  /// A request for a picture this session is holding.
  Future<void> _onChannelMessage(ChatMessage m) async {
    if (m.outgoing) return;
    final ({int id, String requesterHex})? req =
        MediaFetchRequest.decode(m.text);
    if (req == null) return;
    final MediaOffer? offer = offers.find(req.id);
    if (offer == null) return;
    await serve(offer, requesterHex: req.requesterHex);
  }

  /// Sends [offer]'s pixels to one contact, over the path the radio knows.
  ///
  /// Returns the number of records the radio accepted. Zero means the peer has
  /// no known path, which is the honest refusal: the firmware will not flood a
  /// raw record, so a picture to a stranger is not sendable.
  Future<int> serve(MediaOffer offer, {required String requesterHex}) async {
    final List<int>? path = _pathFor(requesterHex);
    if (path == null || path.isEmpty) return 0;
    final List<Uint8List> records =
        MediaFetchCodec.split(id: offer.id, payload: offer.payload);
    int accepted = 0;
    for (final Uint8List record in records) {
      final ChannelDataSendResult r =
          await mc.sendRawData(path: path, payload: record);
      if (!r.accepted) break;
      accepted++;
    }
    return accepted;
  }

  /// Asks the mesh for [id]'s pixels, naming this device.
  ///
  /// A channel text line, because a channel datagram carries no sender: the
  /// requester names itself so the sender can address the answer.
  Future<bool> request({
    required int id,
    required int channelIdx,
  }) async {
    final String? own = mc.ownPubKeyHex;
    if (own == null || own.length < 16) return false;
    final String line =
        MediaFetchRequest.encode(id, MediaFetchRequest.shortKey(own));
    final ChatMessage? sent = await mc.sendChannelTextTo(channelIdx, line);
    return sent != null;
  }

  /// Files one raw record. Returns the payload when the set is complete.
  Uint8List? acceptRecord(Uint8List record) {
    final ({int id, int index, int total, Uint8List slice})? f =
        MediaFetchCodec.decode(record);
    if (f == null) return null;
    final MediaFetchInbox inbox =
        _inbox.putIfAbsent(f.id, () => MediaFetchInbox(id: f.id, total: f.total));
    if (inbox.total != f.total) return null;
    inbox.take(f.index, f.slice);
    if (!inbox.complete) return null;
    final Uint8List payload = inbox.assemble();
    _inbox.remove(f.id);
    return payload;
  }

  /// Indices still missing for [id], so a re-request asks for gaps only.
  List<int> missingFor(int id) => _inbox[id]?.missing ?? const <int>[];

  /// The radio's out-path bytes for a peer, or null when it has none.
  ///
  /// `outPathHashes` is `null` for a contact the radio has never routed a
  /// direct packet to, and for an advert-only node. That is exactly the case
  /// the firmware refuses, so it is a refusal here rather than a guess.
  List<int>? _pathFor(String requesterHex) {
    for (final DiscoveredNode n in mc.nodes) {
      final String key = n.pubKeyHex.toLowerCase();
      if (key.startsWith(requesterHex) || requesterHex.startsWith(key)) {
        final List<int>? p = n.outPathHashes;
        if (p == null || p.isEmpty) return null;
        return p;
      }
    }
    return null;
  }
}
