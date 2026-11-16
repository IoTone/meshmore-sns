// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/chat_message.dart';
import '../meshcore/secure/encrypted_store.dart';
import '../meshcore/secure/record_cipher.dart';
import 'place.dart';
import 'place_codec.dart';
import 'place_confirmation.dart';
import 'place_id.dart';
import '../util/prefs.dart';
import '../util/safe_notifier.dart';

/// What a report did to the store: a new row, a later report of the same row,
/// or a second row that shares an id but not a point (spec §5).
enum PlaceUpsert {
  /// First row for this id at this point.
  added,

  /// The same id at the same point, re-reported. The row moves forward; no
  /// second pin appears, and nothing re-notifies.
  renewed,

  /// Same eight-hex id, a point further apart than the row's own precision.
  /// Both are kept and the display name is suffixed — merging two different
  /// places is worse than showing two (spec §5).
  collided,
}

/// The places this device has seen, live and expired
/// (`meshmore-places-spec.md` §6, §8, §10).
///
/// **Expiry is the feature, so the store never hides a dead row behind a
/// filter a caller forgets:** [live] answers the map, [history] answers the
/// after-action list, and a row whose [Place.expiresAt] has passed is simply
/// absent from [live] while staying visible in [history] with its final state.
///
/// Persistence is the app's sealed store, the same AES-256-GCM key and the
/// same named-record shape as the chat history: a place says where someone
/// was, which is not a public report to leave in a world-readable preferences
/// file. The pre-migration document (`mm.places.v1`) is moved with
/// write-then-read-back-then-delete, so a crash between the steps leaves a
/// duplicate rather than a loss, and a lost Keystore key keeps the ciphertext
/// and says so instead of sealing new rows under a new key.
final class PlaceStore extends ChangeNotifier with SafeNotifier {
  PlaceStore({
    DateTime Function()? clock,
    bool Function(String reporterKeyHex)? isBlocked,
  })  : _clock = clock ?? DateTime.now,
        _isBlocked = isBlocked;

  /// The pre-migration preferences key. Read once, moved into the sealed store,
  /// then deleted: a place is where someone was, so it does not belong in a
  /// world-readable preferences file while the history next to it is sealed.
  static const String _kKey = 'mm.places.v1';

  /// Record name in the app's sealed store.
  static const String recordName = 'places';

  /// Set when the sealed store could not be opened at all, so the rows are
  /// session-only. Distinct from [writeFailed], which is a write that did not
  /// land, and from the corrupt-file case which keeps the bytes.
  static final ValueNotifier<bool> sealedUnreadable = ValueNotifier<bool>(false);

  /// Test seams, as in `ChatStore`: the app leaves both null and the real store
  /// seals through the Android Keystore in the app-support directory.
  @visibleForTesting
  static RecordCipher? cipherOverride;
  @visibleForTesting
  static Directory? directoryOverride;

  /// The sealed store, for a test that has to read a record the store keeps
  /// aside rather than through the store's own API.
  @visibleForTesting
  static EncryptedStore sealedStoreForTest() => _sealedStore();

  static EncryptedStore _sealedStore() {
    final Directory? dir = directoryOverride;
    return EncryptedStore(
      cipher: cipherOverride,
      directory: dir == null ? null : () async => dir,
    );
  }

  /// Rows kept. A busy channel produces a handful an hour and each lives at
  /// most a week, so this is a backstop against a corrupt or hostile stream,
  /// not a working limit. Eviction: expired rows first, oldest [Place.lastSeen]
  /// earliest; a live row is only dropped when the document is all-live and
  /// over the limit, and then also oldest-first — dropping a live pin is the
  /// only failure here a user would notice, so it happens last.
  static const int capacity = 500;

  final DateTime Function() _clock;

  /// Set when the last write to preferences did not land (a full disk, a
  /// quota, a platform failure). The rows live in memory either way, so the
  /// failure is about surviving a restart, and Diagnostics says so rather
  /// than leaving "my pins vanished" unexplained.
  static final ValueNotifier<bool> writeFailed = ValueNotifier<bool>(false);

  /// Set when a load found a document it could not parse and kept the bytes
  /// aside. Diagnostics says so, because "my pins are gone" and "your pins
  /// were unreadable, and here is the file" are different answers.
  static final ValueNotifier<bool> corruptDocumentKept =
      ValueNotifier<bool>(false);

  /// Injected by the block store when it arrives; a blocked reporter's places
  /// are absent everywhere and its stored rows are deleted (spec §10).
  bool Function(String reporterKeyHex)? _isBlocked;

  final List<Place> _rows = <Place>[];
  final Set<String> _seen = <String>{};

  /// Votes replayed into [_tally]. Kept as data as well as in the tally
  /// because [PlaceConfirmationTally] is write-only: it can record a vote but
  /// cannot enumerate one, so persistence needs its own copy.
  final Map<String, List<_StoredVote>> _votes = <String, List<_StoredVote>>{};
  final PlaceConfirmationTally _tally = PlaceConfirmationTally();

  bool _loaded = false;
  bool _dirty = false;

  /// Fires at the moment the next live place stops being live.
  ///
  /// A place leaves the map on its own clock, and nothing was watching that
  /// clock: the layer, the badge and the list all read "live" against `now`,
  /// and a reader who left the screen open kept seeing a pin whose life had
  /// ended until some unrelated write happened to notify. One timer, armed for
  /// the soonest expiry and re-armed after it fires, is enough — and it is only
  /// armed while something is live.
  Timer? _expiry;

  void _armExpiry() {
    _expiry?.cancel();
    _expiry = null;
    // Only while something is watching. A store with no listeners is a store
    // whose owner is gone, and a timer kept alive for it would outlive the
    // screen it was meant to repaint.
    if (!hasListeners) return;
    final DateTime at = now;
    DateTime? soonest;
    for (final Place p in _rows) {
      if (!p.isLiveAt(at)) continue;
      if (soonest == null || p.expiresAt.isBefore(soonest)) {
        soonest = p.expiresAt;
      }
    }
    if (soonest == null) return;
    final Duration wait = soonest.difference(at);
    _expiry = Timer(wait.isNegative ? Duration.zero : wait, () {
      _armExpiry();
      notifyListeners();
    });
  }

  /// Releases the expiry timer. A store that outlives its screen would
  /// otherwise hold a timer open for as long as the process lives.
  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _armExpiry();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _expiry?.cancel();
      _expiry = null;
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _expiry = null;
    super.dispose();
  }

  bool get loaded => _loaded;

  /// Every row, newest report first — live and expired.
  List<Place> get all => List<Place>.unmodifiable(_rows);

  /// The stored row for [id], or null when this device has never kept one.
  /// A display that parsed the message itself prefers this, so the pin and
  /// the thread cannot disagree about a renewal or a kept row.
  Place? byId(String id) {
    for (final Place p in _rows) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Rows whose life has not ended, newest report first: what the layer draws.
  List<Place> live([DateTime? now]) {
    final DateTime at = now ?? this.now;
    return <Place>[
      for (final Place p in _rows)
        if (p.isLiveAt(at)) p,
    ];
  }

  /// The after-action list: every row this device saw, most recent first.
  List<Place> history() {
    final List<Place> rows = <Place>[..._rows];
    rows.sort((Place a, Place b) => b.lastSeen.compareTo(a.lastSeen));
    return rows;
  }

  /// Whether the row has been opened. An unread place is a report the user has
  /// not seen, which is why the layer colours it until it is tapped (§10).
  bool isSeen(String id) => _seen.contains(id);

  void markSeen(String id) {
    if (_seen.add(id)) _save();
  }

  /// The block hook. Called by the shield when a key is blocked; deleting the
  /// stored rows is part of the rule, not a tidy-up (§10).
  void deleteByReporterKey(String reporterKeyHex) {
    final String wanted = reporterKeyHex.toLowerCase();
    final int before = _rows.length;
    _rows.removeWhere((Place p) {
      final Uint8List? key = p.reporterKey;
      if (key == null) return false;
      return _hexOf(key) == wanted;
    });
    if (_rows.length != before) {
      _seen.removeWhere((String id) => !_rows.any((Place p) => p.id == id));
      _votes.forEach((String id, List<_StoredVote> list) =>
          list.removeWhere((_StoredVote v) => v.keyHex?.toLowerCase() == wanted));
      _rebuildTally();
      _save();
      notifyListeners();
    }
  }

  /// Take one place off the map, whoever reported it.
  ///
  /// A place is a claim about the world, and a claim the reader does not want
  /// on their map is theirs to drop: the row, its votes and its seen mark go
  /// together, so a re-delivery of the same report does not bring it back as
  /// new. Blocking a reporter is a different decision and stays separate.
  bool remove(String id) {
    final int before = _rows.length;
    _rows.removeWhere((Place p) => p.id == id);
    if (_rows.length == before) return false;
    _seen.remove(id);
    _votes.remove(id);
    _rebuildTally();
    _save();
    notifyListeners();
    return true;
  }

  void setBlockFilter(bool Function(String reporterKeyHex)? isBlocked) {
    _isBlocked = isBlocked;
  }

  bool isBlockedReporter(Place place) {
    final Uint8List? key = place.reporterKey;
    if (key == null || _isBlocked == null) return false;
    return _isBlocked!(_hexOf(key));
  }

  /// A report arrived. [upsert] is idempotent per id and point, so a duplicate
  /// delivery changes nothing but [Place.lastSeen].
  PlaceUpsert upsert(Place place, {PlaceProvenance? provenance}) {
    if (isBlockedReporter(place)) return PlaceUpsert.added;
    final Place incoming = provenance == null
        ? place
        : place.copyWith(provenance: provenance);
    for (int i = 0; i < _rows.length; i++) {
      final Place row = _rows[i];
      if (row.id != incoming.id) continue;
      if (!_samePoint(row, incoming)) continue;
      if (!incoming.lastSeen.isAfter(row.lastSeen)) return PlaceUpsert.renewed;
      _rows[i] = row.copyWith(
        label: incoming.label,
        typeToken: incoming.typeToken,
        type: incoming.type,
        sentAt: incoming.sentAt,
        sentAtFromSender: incoming.sentAtFromSender,
        expiresAt: incoming.expiresAt,
        ttl: incoming.ttl,
        lastSeen: incoming.lastSeen,
        decimals: incoming.decimals,
        kept: row.kept || incoming.kept,
      );
      _pruneAndSave();
      _armExpiry();
      notifyListeners();
      return PlaceUpsert.renewed;
    }
    _rows.insert(0, incoming);
    _pruneAndSave();
    _armExpiry();
    notifyListeners();
    return _rows.where((Place p) => p.id == incoming.id).length > 1
        ? PlaceUpsert.collided
        : PlaceUpsert.added;
  }

  /// Store a position a message carried as a bare coordinate pair.
  ///
  /// The tagged form is the protocol. This is the other thing people send, and
  /// it is a fact rather than a guess, so it goes on the map without asking.
  /// The label is the coordinate itself, which is what the sender wrote, and the
  /// type is [PlaceType.other] because a bare pair says nothing about what is
  /// there. The id is derived the same way a report's is, so the same sender
  /// repeating the same position renews one pin instead of stacking them.
  Place? ingestBarePosition({
    required double latitude,
    required double longitude,
    required DateTime receivedAt,
    String reporterName = '',
    String? reporterKeyHex,
    int? channelIdx,
  }) {
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;
    if ((reporterKeyHex == null || reporterKeyHex.isEmpty) &&
        reporterName.isEmpty) {
      return null;
    }
    final int latE6 = (latitude * 1e6).round();
    final int lonE6 = (longitude * 1e6).round();
    final List<int>? key = reporterKeyHex == null
        ? null
        : _bytesOf(reporterKeyHex);
    final String label =
        '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
    final PlaceTtl ttl = PlaceType.other.defaultTtl;
    final Place place = Place(
      id: placeIdFor(
        reporterKey: key,
        reporterName: reporterName,
        latE6: latE6,
        lonE6: lonE6,
        typeToken: PlaceType.other.token,
      ),
      type: PlaceType.other,
      typeToken: PlaceType.other.token,
      label: label,
      latE6: latE6,
      lonE6: lonE6,
      decimals: 5,
      reporterName: reporterName,
      reporterKey: key == null ? null : Uint8List.fromList(key),
      provenance: PlaceProvenance.received,
      ttl: ttl,
      sentAt: receivedAt,
      expiresAt: receivedAt.add(ttl.life),
      lastSeen: receivedAt,
      channelIdx: channelIdx,
    );
    upsert(place);
    return place;
  }

  /// Reads a received message as a place report and stores it when it is one.
  ///
  /// [reporterKey] is passed for a direct message (the packet authenticates the
  /// sender) and left null for channel text, where the display name is all the
  /// text carries and the row is marked unkeyed.
  Place? ingestMessage(ChatMessage message) {
    final ({String? sender, String body}) split = _splitSender(message);
    final List<int>? key = message.peerPubKeyHex == null
        ? null
        : _bytesOf(message.peerPubKeyHex!);
    final PlaceParseOutcome outcome = parsePlace(
      split.body,
      receivedAt: message.at,
      reporterName: split.sender ?? '',
      reporterKey: key,
      provenance: PlaceProvenance.received,
    );
    final Place? place = outcome.place;
    if (place == null) return null;
    // The slot the line arrived on is the only channel fact a receiver has, so
    // it is recorded here rather than guessed later from whichever channel is
    // active when the sheet opens.
    upsert(place.copyWith(channelIdx: message.channelIdx));
    return place;
  }

  /// Reads a received message as a confirmation or a refutation.
  ///
  /// One count per identity per id; a repeat moves its time. A blocked key's
  /// reply neither counts nor appears; a key-bound refutation hides the pin on
  /// this device and a claimed one only adds weight (§11).
  bool ingestReply(String text, {String senderName = '', String? reporterKeyHex}) {
    final PlaceReplyOutcome outcome =
        parsePlaceReply(text, senderName: senderName, reporterKeyHex: reporterKeyHex);
    final PlaceReply? reply = outcome.reply;
    if (reply == null) return false;
    final String? key = reporterKeyHex?.toLowerCase();
    if (key != null && _isBlocked != null && _isBlocked!(key)) return false;
    final bool changed = _tally.record(reply, at: _clock(), isBlocked: _isBlocked);
    if (changed) {
      _votes.putIfAbsent(reply.id8, () => <_StoredVote>[]).add(_StoredVote(
            keyHex: key,
            callsign: reply.callsign,
            kind: reply.kind,
            at: _clock(),
          ));
      _save();
      notifyListeners();
    }
    return changed;
  }

  /// The counts a row shows: confirmations from keys, from names, refutations,
  /// and whether a key-bound refutation hid it.
  PlaceConfirmationSummary confirmationsFor(String id) => _tally.summaryFor(id);

  /// Rows after the spec's filters (§10): type, "expires within", label or
  /// reporter search, and optionally keyed-only. A blocked reporter never
  /// appears; an unkeyed place never matches [keyedOnly].
  ///
  /// [expiresWithin] is the "expires within" filter: it asks for a place that
  /// is still live and runs out inside the window. [Place.remainingAt] clamps
  /// an expired row to zero, so without the liveness test the window would
  /// match every row in the history instead of the ones running out soon.
  List<Place> filtered({
    required bool liveOnly,
    Set<PlaceType> types = const <PlaceType>{},
    Duration? expiresWithin,
    String query = '',
    bool keyedOnly = false,
    DateTime? now,
  }) {
    final DateTime at = now ?? this.now;
    final String needle = query.trim().toLowerCase();
    return <Place>[
      for (final Place p in liveOnly ? live(at) : history())
        if (p.reporterKey != null || !keyedOnly)
          if (types.isEmpty || types.contains(p.type))
          if (expiresWithin == null ||
              (p.isLiveAt(at) && p.remainingAt(at) <= expiresWithin))
            if (needle.isEmpty ||
                p.label.toLowerCase().contains(needle) ||
                p.reporterName.toLowerCase().contains(needle))
              if (!isBlockedReporter(p)) p,
    ];
  }

  /// The latest wall time this store has seen, in a preference.
  ///
  /// A phone's clock can be wrong, set back by hand, or jump when the network
  /// time arrives. Place expiry compares wall stamps, so a backwards jump would
  /// resurrect a hazard that already expired. Remembering the highest time ever
  /// observed and never comparing against anything below it makes expiry
  /// monotonic: time can be wrong, but it cannot go backwards.
  static const String _kWaterMark = 'mm.places.highWater';

  DateTime _highWater = DateTime.fromMillisecondsSinceEpoch(0);

  /// Writes [document] to the sealed store and retires the preferences copy.
  ///
  /// The order matters: write, read back, compare, and only then delete. A
  /// crash between the write and the verify leaves both copies, and the next
  /// load prefers the sealed one — the failure mode is a duplicate, not a loss.
  Future<void> _seal(String document, SharedPreferences p) async {
    final Uint8List bytes = Uint8List.fromList(utf8.encode(document));
    try {
      await _sealedStore().write(recordName, bytes);
      final Uint8List? back = await _sealedStore().read(recordName);
      if (back == null || utf8.decode(back) != document) {
        writeFailed.value = true;
        return;
      }
      writeFailed.value = false;
      sealedUnreadable.value = false;
      if (p.containsKey(_kKey)) await p.remove(_kKey);
    } on EncryptedStoreKeyLost {
      // The key is gone: writing would seal under a new one while the old file
      // stays unreadable. Keep everything where it is and say so.
      sealedUnreadable.value = true;
      writeFailed.value = true;
    } on EncryptedStoreUnavailable {
      sealedUnreadable.value = true;
    } on EncryptedStoreCorrupt {
      sealedUnreadable.value = true;
      writeFailed.value = true;
    } on FileSystemException {
      // A directory that vanished, a full disk, a permission the platform took
      // away: the rows are in memory, the file is not, and that is what
      // [writeFailed] is for. Throwing here would surface as an unhandled
      // async error with no screen to show it.
      writeFailed.value = true;
    }
  }

  /// Now, never earlier than a time this store has already seen.
  DateTime get now {
    final DateTime wall = _clock();
    return wall.isAfter(_highWater) ? wall : _highWater;
  }

  /// Called after a successful load: a document stamped in the future means
  /// the clock moved back since it was written, so its stamp becomes the floor.
  void _observeWallClock() {
    final DateTime wall = _clock();
    if (wall.isAfter(_highWater)) _highWater = wall;
    _persistHighWater();
  }

  Future<void> _persistHighWater() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final int stored = Prefs.readInt(p, _kWaterMark, fallback: 0);
    final int mark = _highWater.millisecondsSinceEpoch;
    if (mark > stored) await Prefs.setInt(p, _kWaterMark, mark);
  }

  Future<void> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    corruptDocumentKept.value = false;
    sealedUnreadable.value = false;
    final int storedMark = Prefs.readInt(p, _kWaterMark, fallback: 0);
    if (storedMark > 0) {
      _highWater =
          DateTime.fromMillisecondsSinceEpoch(storedMark, isUtc: false);
    }
    _observeWallClock();
    // Sealed first. The preferences copy is the pre-2026-11-05 format: read it
    // once, move it into the sealed store, verify the move, and only then
    // delete it.
    String? raw;
    try {
      final Uint8List? sealed = await _sealedStore().read(recordName);
      if (sealed != null) raw = utf8.decode(sealed);
    } on EncryptedStoreKeyLost {
      sealedUnreadable.value = true;
    } on EncryptedStoreCorrupt {
      sealedUnreadable.value = true;
    } on EncryptedStoreUnavailable {
      sealedUnreadable.value = true;
    }
    if (raw == null) {
      final String? legacy = p.getString(_kKey);
      if (legacy != null && legacy.isNotEmpty) {
        raw = legacy;
        await _seal(raw, p);
      }
    }
    _rows.clear();
    _seen.clear();
    _votes.clear();
    _tally.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) {
          final Object? rows = decoded['rows'];
          if (rows is List) {
            for (final Object? e in rows) {
              final Place? place = _placeFromJson(e);
              if (place != null) _rows.add(place);
            }
          }
          final Object? seen = decoded['seen'];
          if (seen is List) {
            _seen.addAll(seen.whereType<String>());
          }
          final Object? votes = decoded['votes'];
          if (votes is Map) {
            votes.forEach((Object? id, Object? list) {
              if (id is! String || list is! List) return;
              _votes[id] = <_StoredVote>[
                for (final Object? v in list)
                  if (_StoredVote.fromJson(v) case final _StoredVote vote) vote,
              ];
            });
          }
        }
      } catch (_) {
        // A corrupt document starts clean rather than losing the screen, but
        // the bytes are kept aside first: a parse failure is evidence, and
        // overwriting it with an empty document destroys the only copy that
        // could have been recovered by hand.
        //
        // Kept inside the sealed store, not in preferences. `raw` is the
        // decrypted document, so the preferences copy was a plaintext list of
        // every saved place with its coordinates, in a file the terms text says
        // is encrypted, and nothing ever read it or removed it.
        try {
          await _sealedStore().write(
              '$recordName.bad', Uint8List.fromList(utf8.encode(raw)));
        } on EncryptedStoreUnavailable {
          // No key: there is nowhere sealed to put it, and a plaintext copy is
          // the thing this is avoiding.
        } on EncryptedStoreKeyLost {
          // Same: the store cannot be opened, so the evidence cannot be kept.
        }
        _rows.clear();
        _seen.clear();
        _votes.clear();
      }
    }
    _rebuildTally();
    _pruneAndSave();
    _loaded = true;
    _armExpiry();
    notifyListeners();
  }

  Future<void> clear() async {
    _expiry?.cancel();
    _expiry = null;
    _rows.clear();
    _seen.clear();
    _votes.clear();
    _tally.clear();
    notifyListeners();
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
    // The pre-2026-11-05 plaintext copy and the quarantine copy an older build
    // wrote beside it. Neither is read any more, and both are location data.
    await p.remove('$_kKey.bad');
    try {
      await _sealedStore().write(recordName, Uint8List(0));
      await _sealedStore().remove('$recordName.bad');
    } on EncryptedStoreUnavailable {
      // No key: nothing was sealed, so there is nothing to clear.
    }
  }

  // --- internals -----------------------------------------------------------

  void _rebuildTally() {
    _tally.clear();
    final List<String> ids = _votes.keys.toList()..sort();
    for (final String id in ids) {
      for (final _StoredVote v in _votes[id]!) {
        _tally.record(
          PlaceReply(
            kind: v.kind,
            id8: id,
            callsign: v.callsign,
            attribution: v.keyHex == null
                ? PlaceReplyAttribution.claimed
                : PlaceReplyAttribution.keyBound,
            reporterKeyHex: v.keyHex,
          ),
          at: v.at,
          isBlocked: _isBlocked,
        );
      }
    }
  }

  /// Evicts to [capacity] and persists. Expired rows go first, oldest
  /// [Place.lastSeen] earliest; a live row is dropped only when the document
  /// is all-live and still over the limit.
  void _pruneAndSave() {
    if (_rows.length > capacity) {
      final DateTime now = this.now;
      final List<Place> ordered = <Place>[..._rows];
      ordered.sort((Place a, Place b) {
        final bool aLive = a.isLiveAt(now);
        final bool bLive = b.isLiveAt(now);
        if (aLive != bLive) return aLive ? 1 : -1;
        return a.lastSeen.compareTo(b.lastSeen);
      });
      final Set<Place> drop = <Place>{};
      for (final Place p in ordered) {
        if (_rows.length - drop.length <= capacity) break;
        drop.add(p);
      }
      _rows.removeWhere(drop.contains);
    }
    _save();
  }

  void _save() {
    _dirty = true;
    _pending ??= _drainSaves();
  }

  Future<void>? _pending;

  /// Waits for the queued write, for a caller that needs the file to be on disk
  /// before it does something else — a test tearing its temporary directory
  /// down, or the app finishing a write before it closes.
  @visibleForTesting
  Future<void> flush() async {
    await _pending;
  }

  /// One write at a time, coalescing every change made while it runs: the
  /// store is written on every arrival, and a burst of reports must not queue
  /// a write each.
  Future<void> _drainSaves() async {
    try {
      while (_dirty) {
        _dirty = false;
        final SharedPreferences p = await SharedPreferences.getInstance();
        await _seal(_encode(), p);
        await _persistHighWater();
      }
    } finally {
      _pending = null;
    }
  }

  /// Waits for the pending write. A caller that has to be sure the document is
  /// on disk (a test, or a screen that is closing) awaits this.
  @visibleForTesting
  Future<void> get settled => _pending ?? Future<void>.value();

  String _encode() => jsonEncode(<String, Object?>{
        'v': 1,
        'rows': <Map<String, Object?>>[
          for (final Place p in _rows) _placeToJson(p),
        ],
        'seen': _seen.toList()..sort(),
        'votes': <String, Object?>{
          for (final MapEntry<String, List<_StoredVote>> e in _votes.entries)
            e.key: <Map<String, Object?>>[
              for (final _StoredVote v in e.value) v.toJson(),
            ],
        },
      });

  /// Two reports are the same place when they agree at the coarser of their
  /// two precisions. A receiver never re-snaps (§9): this only decides whether
  /// two *arrivals* are one row, and the wire digits are never changed.
  static bool _samePoint(Place a, Place b) {
    final int decimals = a.decimals < b.decimals ? a.decimals : b.decimals;
    return _snapDegrees(a.latitude, decimals) == _snapDegrees(b.latitude, decimals) &&
        _snapDegrees(a.longitude, decimals) == _snapDegrees(b.longitude, decimals);
  }

  static double _snapDegrees(double degrees, int decimals) {
    final double scale = _pow10(decimals);
    return (degrees * scale).round() / scale;
  }

  static double _pow10(int n) {
    double v = 1;
    for (int i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }

  static ({String? sender, String body}) _splitSender(ChatMessage m) {
    if (m.outgoing) return (sender: null, body: m.text);
    final int i = m.text.indexOf(': ');
    if (i <= 0) return (sender: null, body: m.text);
    final String name = m.text.substring(0, i);
    // A channel line is `name: text`; a name never contains a bracket, so a
    // text that opens with the tag is not a prefixed line.
    if (name.contains('[')) return (sender: null, body: m.text);
    return (sender: name, body: m.text.substring(i + 2));
  }

  static String _hexOf(List<int> bytes) {
    final StringBuffer b = StringBuffer();
    for (final int byte in bytes) {
      b.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  static Uint8List? _bytesOf(String hex) {
    if (hex.isEmpty || hex.length.isOdd) return null;
    final Uint8List out = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      final int? byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) return null;
      out[i] = byte;
    }
    return out;
  }

  static Map<String, Object?> _placeToJson(Place p) => <String, Object?>{
        'id': p.id,
        'key': p.reporterKey == null ? null : _hexOf(p.reporterKey!),
        'name': p.reporterName,
        'type': p.typeToken,
        'label': p.label,
        'description': p.description,
        'lat': p.latE6,
        'lon': p.lonE6,
        'dp': p.decimals,
        'prov': p.provenance.name,
        'ttl': p.ttl.token,
        'sent': p.sentAt.toUtc().toIso8601String(),
        'sentFromSender': p.sentAtFromSender,
        'expires': p.expiresAt.toUtc().toIso8601String(),
        'seen': p.lastSeen.toUtc().toIso8601String(),
        'kept': p.kept,
        // The channel the report was sent on or seen on. Local only: the wire
        // grammar carries no channel, so this is written here and never
        // encoded into a message.
        'ch': p.channelIdx,
      };

  static Place? _placeFromJson(Object? raw) {
    if (raw is! Map) return null;
    String? str(String k) {
      final Object? v = raw[k];
      return v is String ? v : null;
    }

    int? num_(String k) {
      final Object? v = raw[k];
      return v is num ? v.toInt() : null;
    }

    final String? id = str('id');
    final String? name = str('name');
    final String? typeToken = str('type');
    final String? label = str('label');
    final int? lat = num_('lat');
    final int? lon = num_('lon');
    final int? dp = num_('dp');
    final String? ttlToken = str('ttl');
    final DateTime? sent = DateTime.tryParse(str('sent') ?? '');
    final DateTime? expires = DateTime.tryParse(str('expires') ?? '');
    final DateTime? seen = DateTime.tryParse(str('seen') ?? '');
    if (id == null ||
        name == null ||
        typeToken == null ||
        label == null ||
        lat == null ||
        lon == null ||
        dp == null ||
        sent == null ||
        expires == null ||
        seen == null) {
      return null;
    }
    final PlaceTtl? ttl = PlaceTtl.byToken(ttlToken ?? '');
    if (ttl == null) return null;
    final PlaceProvenance provenance = PlaceProvenance.values.firstWhere(
      (PlaceProvenance v) => v.name == str('prov'),
      orElse: () => PlaceProvenance.received,
    );
    return Place(
      id: id,
      reporterKey: _bytesOf(str('key') ?? ''),
      reporterName: name,
      type: PlaceType.byToken(typeToken),
      typeToken: typeToken,
      label: label,
      description: str('description'),
      latE6: lat,
      lonE6: lon,
      decimals: dp,
      provenance: provenance,
      ttl: ttl,
      sentAt: sent.toLocal(),
      sentAtFromSender: raw['sentFromSender'] == true,
      expiresAt: expires.toLocal(),
      lastSeen: seen.toLocal(),
      kept: raw['kept'] == true,
      channelIdx: num_('ch'),
    );
  }

  /// The row's id re-derived from the digits that arrived, which is what a
  /// renewal from a second reporter has to match (spec §5). Exposed for tests.
  @visibleForTesting
  static String idOf(Place place) => placeIdOf(place);
}

/// One stored reply. Kept beside the tally so the counts survive a restart.
@immutable
final class _StoredVote {
  const _StoredVote({
    required this.keyHex,
    required this.callsign,
    required this.kind,
    required this.at,
  });

  final String? keyHex;
  final String callsign;
  final PlaceReplyKind kind;
  final DateTime at;

  Map<String, Object?> toJson() => <String, Object?>{
        'k': keyHex,
        'n': callsign,
        'c': kind == PlaceReplyKind.confirm,
        'at': at.toUtc().toIso8601String(),
      };

  static _StoredVote? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? key = raw['k'];
    final Object? name = raw['n'];
    final Object? at = raw['at'];
    if (name is! String || at is! String) return null;
    final DateTime? when = DateTime.tryParse(at);
    if (when == null) return null;
    return _StoredVote(
      keyHex: key is String ? key : null,
      callsign: name,
      kind: raw['c'] == true ? PlaceReplyKind.confirm : PlaceReplyKind.refute,
      at: when.toLocal(),
    );
  }
}
