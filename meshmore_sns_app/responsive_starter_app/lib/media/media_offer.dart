// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

/// A picture that has been announced but not sent.
///
/// The rule this exists for: a full picture is **never broadcast**. A channel
/// datagram is flooded to every radio in range, and a photo is five to twenty of
/// them, so a channel photo spends the airtime of everyone who can hear it on a
/// picture most of them did not ask for. The three clients that got this right
/// all do the same thing: announce cheaply, then send the pixels to one person
/// who asked.
///
/// - MeshPix puts a 24x24 palette preview in one channel datagram and sends the
///   upgrade as a direct message only after a tap (`lib/transfer/protocol.dart`).
/// - meshcore-sar puts an `IE4:` envelope in the chat and fetches the pixels
///   with an explicit `IR4` request (`docs/image-mode-technical.md`).
/// - The firmware makes the rule enforceable: `CMD_SEND_RAW_DATA` (0x19)
///   requires a path and refuses a flood (`MyMesh.cpp:1519-1533`), so a direct
///   record cannot be broadcast even by mistake.
///
/// This class is the sender's side of that: the payload it is willing to serve,
/// for how long, and to whom.
final class MediaOffer {
  MediaOffer({
    required this.id,
    required this.payload,
    required this.chunkCount,
    required this.createdAt,
    this.ttl = const Duration(minutes: 15),
  });

  /// The id that travels in the preview and comes back in a request.
  final int id;

  /// The encoded picture, exactly as it would be chunked.
  final Uint8List payload;

  /// How many datagrams the payload needs, which is what the preview states so
  /// a reader can decide before spending anything.
  final int chunkCount;

  final DateTime createdAt;

  /// How long the sender keeps serving this picture.
  ///
  /// Fifteen minutes is meshcore-sar's default and it is the right shape: long
  /// enough for a reader who saw the preview to tap it, short enough that a
  /// phone is not holding a photo it will never send again.
  final Duration ttl;

  bool isExpired(DateTime now) => now.difference(createdAt) > ttl;
}

/// The offers this session is willing to serve, newest last.
///
/// Bounded and expiring on purpose: an offer is a promise to spend airtime, and
/// a promise nobody can keep is worse than a refusal.
final class MediaOfferStore {
  MediaOfferStore({this.capacity = 8, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final int capacity;
  final DateTime Function() _clock;
  final List<MediaOffer> _offers = <MediaOffer>[];

  List<MediaOffer> get offers => List<MediaOffer>.unmodifiable(_offers);

  /// Keeps [offer] and returns it, dropping the oldest and anything expired.
  MediaOffer add(MediaOffer offer) {
    _prune();
    _offers.add(offer);
    while (_offers.length > capacity) {
      _offers.removeAt(0);
    }
    return offer;
  }

  /// The offer with [id], or null when it expired or was never held.
  MediaOffer? find(int id) {
    _prune();
    for (final MediaOffer o in _offers) {
      if (o.id == id) return o;
    }
    return null;
  }

  void remove(int id) => _offers.removeWhere((MediaOffer o) => o.id == id);

  void clear() => _offers.clear();

  void _prune() {
    final DateTime now = _clock();
    _offers.removeWhere((MediaOffer o) => o.isExpired(now));
  }
}

/// The request a reader sends to ask for the pixels.
///
/// It is a **direct message**, not a channel line, because the answer is a
/// direct record and the request should travel the same way. The grammar is
/// deliberately tiny: a reader who is not running this app sees a short text
/// message and nothing else, and a reader who is sees a request.
///
/// `[IMG1:<id>]` — the id is the one the preview carried, in decimal.
abstract final class MediaRequestCodec {
  static const String _prefix = '[IMG1:';
  static const String _suffix = ']';

  static String encode(int id) => '$_prefix$id$_suffix';

  /// The id in [text], or null when the line is not a request.
  static int? decode(String text) {
    final String t = text.trim();
    if (!t.startsWith(_prefix) || !t.endsWith(_suffix)) return null;
    final String body = t.substring(_prefix.length, t.length - _suffix.length);
    final int? id = int.tryParse(body);
    if (id == null || id < 0 || id > 0xFFFF) return null;
    return id;
  }

  /// Whether [text] is a request at all, without parsing the id.
  static bool looksLikeRequest(String text) =>
      text.trim().startsWith(_prefix);
}
