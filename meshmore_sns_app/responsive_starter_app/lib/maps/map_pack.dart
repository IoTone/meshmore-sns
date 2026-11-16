// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'tile_math.dart';

/// Where a pack's download stands.
enum PackState {
  /// Fetching tiles now, or next in line.
  downloading,

  /// Re-asking the server about every tile (conditional requests).
  updating,

  /// Wants the network; resumes on its own when a fetch succeeds.
  waitingForNetwork,

  /// Stopped because the next tile would break the storage budget.
  overBudget,

  /// Stopped by the user.
  paused,

  complete,
}

/// R61 — a downloaded region: one source, one box, a zoom range.
/// Tiles live in the shared [TileStore], tagged with the pack id, so
/// two packs that overlap share bytes and deleting one leaves the
/// other whole.
class MapPack {
  MapPack({
    required this.id,
    required this.name,
    required this.sourceId,
    required this.box,
    required this.minZoom,
    required this.maxZoom,
    required this.createdMs,
    required this.total,
    this.keepDays = 0,
    this.state = PackState.downloading,
    this.done = 0,
    this.missing = 0,
    int? updatedMs,
    this.updateStartedMs,
    this.passStartedMs,
    this.passStartDone = 0,
  }) : updatedMs = updatedMs ?? createdMs;

  final String id;
  String name;
  final String sourceId;
  final GeoBox box;
  final int minZoom;
  final int maxZoom;
  final int createdMs;

  /// Last time a download or update finished (or started, for a pack
  /// that has never finished). Expiry counts from here.
  int updatedMs;

  /// Set while [PackState.updating]: tiles fetched before this get
  /// asked about again.
  int? updateStartedMs;

  final int total;
  PackState state;

  /// Tiles held (or confirmed absent) so far in this pass.
  int done;

  /// Tiles the server has nothing for (outside its coverage).
  int missing;

  /// When the current pass began, and how many tiles were already held then.
  ///
  /// Together they are what makes a rate measurable: `(done - passStartDone)`
  /// over `now - passStartedMs`. Without them the only progress a reader saw was
  /// a fraction, and "1234 of 2000" says nothing about how long is left.
  int? passStartedMs;
  int passStartDone;

  /// Delete this many days after [updatedMs]; 0 = keep.
  int keepDays;

  int? get expiresAtMs => keepDays == 0
      ? null
      : updatedMs + Duration(days: keepDays).inMilliseconds;

  bool get wantsWork =>
      state == PackState.downloading ||
      state == PackState.updating ||
      state == PackState.waitingForNetwork;

  double get progress => total == 0 ? 1 : (done / total).clamp(0, 1);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'src': sourceId,
        'box': box.toJson(),
        'minZ': minZoom,
        'maxZ': maxZoom,
        'created': createdMs,
        'updated': updatedMs,
        'updStart': updateStartedMs,
        'total': total,
        'state': state.name,
        'done': done,
        'missing': missing,
        'keep': keepDays,
        'passStart': passStartedMs,
        'passDone': passStartDone,
      };

  static MapPack fromJson(Map<String, Object?> j) => MapPack(
        id: j['id']! as String,
        name: j['name']! as String,
        sourceId: j['src']! as String,
        box: GeoBox.fromJson(j['box']! as Map<String, Object?>),
        minZoom: (j['minZ']! as num).toInt(),
        maxZoom: (j['maxZ']! as num).toInt(),
        createdMs: (j['created']! as num).toInt(),
        updatedMs: (j['updated'] as num?)?.toInt(),
        updateStartedMs: (j['updStart'] as num?)?.toInt(),
        total: (j['total']! as num).toInt(),
        state: PackState.values.firstWhere(
            (PackState s) => s.name == j['state'],
            orElse: () => PackState.paused),
        done: (j['done'] as num?)?.toInt() ?? 0,
        missing: (j['missing'] as num?)?.toInt() ?? 0,
        keepDays: (j['keep'] as num?)?.toInt() ?? 0,
        // A pass that was running when the app closed is not still running, so
        // the timing is dropped rather than resumed against a wall clock that
        // moved. The rate starts again from the next pass.
        passStartedMs: null,
        passStartDone: 0,
      );
}
