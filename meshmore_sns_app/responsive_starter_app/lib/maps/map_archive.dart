// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// R81 — a downloaded region: ONE PMTiles file, not thousands of tiles.
///
/// A [MapPack] is a box and a zoom range fetched tile by tile. An archive
/// is what the owner (or any host that permits it) already cut with
/// `pmtiles extract --bbox ... --maxzoom 14` and put on a static URL: it
/// downloads as one resumable file, is verified by size and SHA-256, and is
/// read in place with seeks. Updating it is replacing the file.
/// R84 — region files are a live feature. R83 hid the entry because a pack is
/// useless until a host publishes one; the answer is a catalogue that can be
/// empty and says so, not a hidden section. See `pack_catalog.dart`: the app
/// ships a list, can be pointed at a published one at build time, and installs
/// from a link in either case.

enum ArchiveState {
  downloading,

  /// Parked because the Wi-Fi-only preference is on and the link is metered.
  /// Resumes by itself when the pump next runs on an unmetered link.
  waitingForWifi,
  waitingForNetwork,
  overBudget,
  paused,
  complete,

  /// Refused on arrival: wrong hash, wrong size, not PMTiles, wrong schema.
  /// The file is deleted; [MapArchive.failure] says why.
  failed,
}

enum ArchiveFailure { badHash, badSize, notPmTiles, wrongSchema, notFound }

/// Why an archive was not added — one sentence each in the UI.
enum ArchiveRefusal {
  noName,
  badUrl,
  duplicate,
  overBudget,

  /// The platform says the download plus the reserve does not fit.
  notEnoughSpace,
}

class MapArchive {
  MapArchive({
    required this.id,
    required this.name,
    required this.url,
    required this.createdMs,
    this.expectedBytes,
    this.sha256,
    this.keepDays = 0,
    this.state = ArchiveState.downloading,
    this.failure,
    this.etag,
    int? updatedMs,
    this.minZoom,
    this.maxZoom,
    this.west,
    this.south,
    this.east,
    this.north,
  }) : updatedMs = updatedMs ?? createdMs;

  final String id;
  String name;
  final String url;
  final int createdMs;

  /// What the catalog says the file is; null = trust the server's length.
  final int? expectedBytes;

  /// Lower-case hex SHA-256, or null when the host publishes none.
  final String? sha256;
  int keepDays;
  ArchiveState state;
  ArchiveFailure? failure;

  /// Validator for resume (`If-Range`): a file replaced on the server
  /// restarts from zero instead of being stitched from two versions.
  String? etag;
  int updatedMs;

  // Filled from the PMTiles header once the file is accepted.
  int? minZoom;
  int? maxZoom;
  double? west, south, east, north;

  int? get expiresAtMs =>
      keepDays == 0 ? null : updatedMs + keepDays * Duration.millisecondsPerDay;

  bool get complete => state == ArchiveState.complete;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'url': url,
        'created': createdMs,
        'bytes': expectedBytes,
        'sha': sha256,
        'keep': keepDays,
        'state': state.name,
        'failure': failure?.name,
        'etag': etag,
        'updated': updatedMs,
        'minZ': minZoom,
        'maxZ': maxZoom,
        'w': west,
        's': south,
        'e': east,
        'n': north,
      };

  static MapArchive fromJson(Map<String, Object?> j) {
    ArchiveState st = ArchiveState.values.firstWhere(
        (ArchiveState s) => s.name == j['state'],
        orElse: () => ArchiveState.paused);
    // A download interrupted by an app restart resumes on its own.
    if (st == ArchiveState.downloading) st = ArchiveState.waitingForNetwork;
    return MapArchive(
      id: j['id']! as String,
      name: j['name']! as String,
      url: j['url']! as String,
      createdMs: (j['created'] as num).toInt(),
      expectedBytes: (j['bytes'] as num?)?.toInt(),
      sha256: j['sha'] as String?,
      keepDays: (j['keep'] as num?)?.toInt() ?? 0,
      state: st,
      failure: ArchiveFailure.values
          .where((ArchiveFailure f) => f.name == j['failure'])
          .firstOrNull,
      etag: j['etag'] as String?,
      updatedMs: (j['updated'] as num?)?.toInt(),
      minZoom: (j['minZ'] as num?)?.toInt(),
      maxZoom: (j['maxZ'] as num?)?.toInt(),
      west: (j['w'] as num?)?.toDouble(),
      south: (j['s'] as num?)?.toDouble(),
      east: (j['e'] as num?)?.toDouble(),
      north: (j['n'] as num?)?.toDouble(),
    );
  }
}

// ---- transport -----------------------------------------------------

/// A response whose body is streamed, so a 100 MB file never sits in
/// memory. [close] releases the connection; always call it.
class ArchiveResponse {
  ArchiveResponse({
    required this.status,
    required this.body,
    this.contentLength,
    this.rangeStart,
    this.rangeTotal,
    this.etag,
    this.close,
  });

  final int status;
  final Stream<List<int>> body;

  /// Bytes in this body, when the server said.
  final int? contentLength;

  /// From `Content-Range: bytes S-E/T` on a 206.
  final int? rangeStart;
  final int? rangeTotal;
  final String? etag;
  final void Function()? close;
}

/// Test seam, like [MapFetcher]. [rangeStart] asks to resume; [ifRange]
/// makes the server ignore the range if the file changed.
typedef ArchiveFetcher = Future<ArchiveResponse> Function(Uri url,
    {int? rangeStart, String? ifRange});

ArchiveFetcher httpArchiveFetcher(String Function() userAgent) {
  return (Uri url, {int? rangeStart, String? ifRange}) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = userAgent();
    try {
      final HttpClientRequest req = await client.getUrl(url);
      if (rangeStart != null && rangeStart > 0) {
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$rangeStart-');
        if (ifRange != null) req.headers.set(HttpHeaders.ifRangeHeader, ifRange);
      }
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 30));
      int? start, total;
      final String? cr = resp.headers.value(HttpHeaders.contentRangeHeader);
      // `bytes S-E/T` on a 206, `bytes */T` on a 416.
      final RegExpMatch? m = cr == null
          ? null
          : RegExp(r'bytes (?:(\d+)-\d+|\*)/(\d+|\*)').firstMatch(cr);
      if (m != null) {
        start = m.group(1) == null ? null : int.parse(m.group(1)!);
        total = m.group(2) == '*' ? null : int.parse(m.group(2)!);
      }
      final int len = resp.contentLength;
      return ArchiveResponse(
        status: resp.statusCode,
        body: resp,
        contentLength: len < 0 ? null : len,
        rangeStart: start,
        rangeTotal: total,
        etag: resp.headers.value(HttpHeaders.etagHeader),
        close: () => client.close(force: true),
      );
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  };
}

// ---- resumable download --------------------------------------------

enum DownloadEnd {
  /// The whole file is in [DownloadResult.bytes] on disk.
  complete,

  /// The caller asked to stop (pause/delete). The partial file is kept.
  stopped,

  /// The next chunk would break the storage budget. Partial file kept.
  overBudget,

  /// Connection lost or stream ended early. Partial file kept.
  networkLost,

  /// 404/410: the URL is dead; retrying will not help.
  notFound,
}

class DownloadResult {
  const DownloadResult(this.end, this.bytes, {this.etag, this.total});
  final DownloadEnd end;

  /// Size of the file on disk after this attempt.
  final int bytes;
  final String? etag;

  /// Full size when the server said.
  final int? total;
}

/// Fetch [url] into [part], resuming from whatever [part] already holds.
///
/// * Resume sends `Range: bytes=N-` (+ `If-Range` with [etag]). A `206`
///   whose `Content-Range` start is exactly N continues the file; a `200`
///   means the server ignored the range or the file changed, so the part
///   file restarts from zero rather than being corrupted.
/// * [allowedBytes] is asked for before each chunk so a budget that
///   shrinks mid-download stops it.
/// * Nothing here decides success: the caller verifies size and hash.
Future<DownloadResult> downloadResumable({
  required ArchiveFetcher fetch,
  required Uri url,
  required File part,
  required bool Function() shouldStop,
  required int Function() allowedBytes,
  String? etag,
  void Function(int bytesOnDisk, int? total)? onProgress,
}) async {
  int have = await part.exists() ? await part.length() : 0;
  ArchiveResponse resp;
  try {
    resp = await fetch(url, rangeStart: have, ifRange: etag);
  } catch (_) {
    return DownloadResult(DownloadEnd.networkLost, have, etag: etag);
  }
  try {
    if (resp.status == 404 || resp.status == 410) {
      return DownloadResult(DownloadEnd.notFound, have, etag: etag);
    }
    if (resp.status == 416) {
      // Asked to resume at or past the end. If the file is exactly as long
      // as the part, the part IS the file (a crash after the last byte,
      // before verification). Otherwise it was replaced by a shorter one:
      // start again; the caller will call once more.
      if (resp.rangeTotal == have && have > 0) {
        return DownloadResult(DownloadEnd.complete, have,
            etag: etag, total: have);
      }
      await part.writeAsBytes(const <int>[]);
      return DownloadResult(DownloadEnd.networkLost, 0, etag: null);
    }
    final bool resumed = resp.status == 206 && resp.rangeStart == have;
    if (resp.status != 200 && !resumed) {
      return DownloadResult(DownloadEnd.networkLost, have, etag: etag);
    }
    final int? total = resumed
        ? resp.rangeTotal
        : resp.contentLength;
    if (!resumed) have = 0; // the whole file is coming from byte zero
    final RandomAccessFile out = await part.open(
        mode: resumed ? FileMode.append : FileMode.write);
    try {
      await for (final List<int> chunk in resp.body) {
        if (shouldStop()) {
          return DownloadResult(DownloadEnd.stopped, have,
              etag: resp.etag ?? etag, total: total);
        }
        if (have + chunk.length > allowedBytes()) {
          return DownloadResult(DownloadEnd.overBudget, have,
              etag: resp.etag ?? etag, total: total);
        }
        await out.writeFrom(chunk);
        have += chunk.length;
        onProgress?.call(have, total);
      }
    } catch (_) {
      return DownloadResult(DownloadEnd.networkLost, have,
          etag: resp.etag ?? etag, total: total);
    } finally {
      await out.close();
    }
    if (total != null && have < total) {
      return DownloadResult(DownloadEnd.networkLost, have,
          etag: resp.etag ?? etag, total: total);
    }
    return DownloadResult(DownloadEnd.complete, have,
        etag: resp.etag ?? etag, total: total ?? have);
  } finally {
    resp.close?.call();
  }
}

/// Lower-case hex SHA-256 of a file, streamed.
Future<String> sha256OfFile(File f) async =>
    (await crypto.sha256.bind(f.openRead()).first).toString();
