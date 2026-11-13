// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'dart:typed_data';

/// R61 — outcome of one HTTP fetch.
enum FetchStatus {
  ok,

  /// 304: what we hold is still good.
  notModified,

  /// The server answered but has nothing here (404/204/410) — outside
  /// its coverage. Not a network failure; the downloader skips it.
  missing,

  /// No answer, or a 5xx/429: treat the phone as offline for a while.
  failed,
}

class FetchResult {
  const FetchResult(this.status,
      {this.bytes, this.maxAge, this.etag, this.lastModified, this.tooLarge = false});
  final FetchStatus status;
  final Uint8List? bytes;

  /// The body was longer than the caller's cap, so it was abandoned part way
  /// through rather than read to the end and rejected afterwards.
  ///
  /// Carried as a flag rather than as its own [FetchStatus] because every
  /// existing switch over that enum is about the network's answer, and this is
  /// the same answer with a body the caller refuses to hold.
  final bool tooLarge;

  /// From Cache-Control max-age / Expires, if the server said.
  final Duration? maxAge;
  final String? etag;
  final String? lastModified;
}

/// The network seam: tests swap in a fake.
///
/// [maxBytes] is a cap on the body. The tile path passes none because a tile is
/// small and bounded by its own format; the event-layer path passes the layer
/// budget, because a publisher's GeoJSON has no bound at all. Without it the
/// whole document was buffered in memory before `_downloadLayer` compared its
/// length to the cap, so a 400 MB FeatureCollection was read in full and then
/// discarded — the cap protected the disk and nothing else.
typedef MapFetcher = Future<FetchResult> Function(Uri url,
    {String? etag, int? ifModifiedSinceMs, int? maxBytes});

/// A stable app identity, as the OSM tile policy requires; only the
/// version moves between releases.
String mapUserAgent(String version) =>
    'MeshmoreSNS/$version (+https://github.com/IoTone/meshmore-sns)';

/// Read the server's freshness. Cache-Control wins over Expires.
Duration? parseMaxAge(String? cacheControl, String? expires, DateTime now) {
  if (cacheControl != null) {
    final RegExpMatch? m =
        RegExp(r'max-age\s*=\s*(\d+)').firstMatch(cacheControl);
    if (m != null) return Duration(seconds: int.parse(m.group(1)!));
  }
  if (expires != null) {
    try {
      final DateTime e = HttpDate.parse(expires);
      final Duration d = e.difference(now);
      return d.isNegative ? Duration.zero : d;
    } catch (_) {}
  }
  return null;
}

/// Read a header that may legitimately appear more than once.
///
/// `HttpHeaders.value(name)` throws `HttpException: More than one value for
/// header [name]` when a response repeats a header, which kills the whole
/// fetch. One tile server sent two `cache-control` headers, so every vector
/// tile failed with a blank map and no other symptom (R80 device run).
/// List-valued headers are joined per RFC 9110; single-valued ones take the
/// first, which is what a proxy chain means to convey.
String? headerValue(HttpHeaders headers, String name, {bool join = false}) {
  final List<String>? values = headers[name];
  if (values == null || values.isEmpty) return null;
  return join ? values.join(', ') : values.first;
}

/// Default fetcher over dart:io. Never sends no-cache headers; sends
/// If-None-Match / If-Modified-Since when it has them.
MapFetcher httpMapFetcher(String Function() userAgent) {
  return (Uri url, {String? etag, int? ifModifiedSinceMs, int? maxBytes}) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = userAgent();
    try {
      final HttpClientRequest req = await client.getUrl(url);
      if (etag != null) req.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      if (ifModifiedSinceMs != null) {
        req.headers.ifModifiedSince =
            DateTime.fromMillisecondsSinceEpoch(ifModifiedSinceMs, isUtc: true);
      }
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 30));
      final Duration? maxAge = parseMaxAge(
          headerValue(resp.headers, HttpHeaders.cacheControlHeader, join: true),
          headerValue(resp.headers, HttpHeaders.expiresHeader),
          DateTime.now());
      final String? newTag = headerValue(resp.headers, HttpHeaders.etagHeader);
      final int code = resp.statusCode;
      if (code == 304) {
        await resp.drain<void>();
        return FetchResult(FetchStatus.notModified,
            maxAge: maxAge, etag: newTag ?? etag);
      }
      if (code == 404 || code == 410 || code == 204) {
        await resp.drain<void>();
        return const FetchResult(FetchStatus.missing);
      }
      if (code != 200) {
        await resp.drain<void>();
        return const FetchResult(FetchStatus.failed);
      }
      // Refuse on the announced length before reading a byte, and then guard
      // every chunk as well, because a chunked response announces nothing.
      if (maxBytes != null &&
          resp.contentLength > 0 &&
          resp.contentLength > maxBytes) {
        return const FetchResult(FetchStatus.ok, tooLarge: true);
      }
      final BytesBuilder bb = BytesBuilder(copy: false);
      await for (final List<int> chunk
          in resp.timeout(const Duration(seconds: 60))) {
        if (maxBytes != null && bb.length + chunk.length > maxBytes) {
          return const FetchResult(FetchStatus.ok, tooLarge: true);
        }
        bb.add(chunk);
      }
      return FetchResult(FetchStatus.ok,
          bytes: bb.takeBytes(),
          maxAge: maxAge,
          etag: newTag,
          lastModified:
              headerValue(resp.headers, HttpHeaders.lastModifiedHeader));
    } catch (e) {
      // R80 — a silent catch turned a real, repeatable failure into an
      // invisible one: every tile came back null and the map was blank
      // with nothing in the log. Debug builds now say what went wrong.
      if (kDebugMode) debugPrint('map fetch failed: $url ($e)');
      return const FetchResult(FetchStatus.failed);
    } finally {
      client.close(force: true);
    }
  };
}
