// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';

import '../meshcore/chat_message.dart';
import '../meshcore/meshcore_controller.dart';
import '../sns/city_gazetteer.dart';
import '../sns/place_inference.dart';
import 'place.dart';
import 'place_store.dart';

/// Wires inbound mesh traffic into the place store
/// (`meshmore-places-spec.md` §6, §11).
///
/// App-scoped, like the cue and bot bridges and for the same reason: a report
/// that only landed while the user happened to be looking at the map would
/// disappear from the layer, and a confirmation would not count. The decisions
/// live in [PlaceStore]; this class is the plumbing that feeds it.
///
/// A channel line and a direct message arrive on different streams and carry
/// different identity — a channel line has a name, a DM is authenticated by
/// the packet's key — so both are offered to the store and it decides.
final class PlaceBridge {
  PlaceBridge(this._mc, this._store) {
    _channelSub = _mc.incomingChannelMessages.listen(_onChannel);
    _dmSub = _mc.incomingDirectMessages.listen(_onDm);
  }

  final MeshcoreController _mc;
  final PlaceStore _store;
  StreamSubscription<ChatMessage>? _channelSub;
  StreamSubscription<ChatMessage>? _dmSub;

  /// Ignoring our own echo is not politeness: an outgoing report is stored by
  /// the composer, so ingesting it again would renew the row with a second
  /// reporter identity and change its id.
  void _onChannel(ChatMessage m) {
    if (m.outgoing) return;
    final Place? place = _store.ingestMessage(m);
    if (place != null) return;
    if (_ingestBarePosition(m, senderName: _senderName(m.text))) return;
    _store.ingestReply(m.text, senderName: _senderName(m.text));
  }

  void _onDm(ChatMessage m) {
    if (m.outgoing) return;
    final String? key = m.peerPubKeyHex;
    final Place? place = _store.ingestMessage(m);
    if (place != null) return;
    if (_ingestBarePosition(m, reporterKeyHex: key)) return;
    _store.ingestReply(m.text,
        senderName: _senderName(m.text), reporterKeyHex: key);
  }

  /// A message that carries a coordinate pair and nothing else is a position.
  ///
  /// The tagged form is the protocol and stays the protocol. This is the other
  /// thing people actually send: a bare `38.91993,-104.77313` from a radio whose
  /// owner has no client that speaks the tag. It is not a guess, so it goes on
  /// the map without asking, and the pin's own sheet is where a reader takes it
  /// off again.
  bool _ingestBarePosition(
    ChatMessage m, {
    String senderName = '',
    String? reporterKeyHex,
  }) {
    final List<InferredPlace> hits = _engine.coordinatesIn(m.text);
    if (hits.isEmpty) return false;
    final InferredPlace hit = hits.first;
    // A grid locator is a position too, but it is a coarser claim and the
    // tagged form is the way to make one deliberately.
    if (hit.cue != PlaceCueKind.coordinate) return false;
    final Place? place = _store.ingestBarePosition(
      latitude: hit.latitude,
      longitude: hit.longitude,
      receivedAt: m.at,
      reporterName: senderName,
      reporterKeyHex: reporterKeyHex,
      channelIdx: m.channelIdx,
    );
    return place != null;
  }

  final PlaceInferenceEngine _engine =
      PlaceInferenceEngine(gazetteer: const CityGazetteer());

  static String _senderName(String text) {
    final int i = text.indexOf(': ');
    if (i <= 0) return '';
    final String name = text.substring(0, i);
    return name.contains('[') ? '' : name;
  }

  void dispose() {
    _channelSub?.cancel();
    _dmSub?.cancel();
  }
}
