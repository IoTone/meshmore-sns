// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:io';
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
      {this.bytes, this.maxAge, this.etag, this.lastModified});
  final FetchStatus status;
  final Uint8List? bytes;

  /// From Cache-Control max-age / Expires, if the server said.
  final Duration? maxAge;
  final String? etag;
  final String? lastModified;
}

/// The network seam: tests swap in a fake.
typedef MapFetcher = Future<FetchResult> Function(Uri url,
    {String? etag, int? ifModifiedSinceMs});

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

/// Default fetcher over dart:io. Never sends no-cache headers; sends
/// If-None-Match / If-Modified-Since when it has them.
MapFetcher httpMapFetcher(String Function() userAgent) {
  return (Uri url, {String? etag, int? ifModifiedSinceMs}) async {
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
          resp.headers.value(HttpHeaders.cacheControlHeader),
          resp.headers.value(HttpHeaders.expiresHeader),
          DateTime.now());
      final String? newTag = resp.headers.value(HttpHeaders.etagHeader);
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
      final BytesBuilder bb = BytesBuilder(copy: false);
      await for (final List<int> chunk
          in resp.timeout(const Duration(seconds: 60))) {
        bb.add(chunk);
      }
      return FetchResult(FetchStatus.ok,
          bytes: bb.takeBytes(),
          maxAge: maxAge,
          etag: newTag,
          lastModified: resp.headers.value(HttpHeaders.lastModifiedHeader));
    } catch (_) {
      return const FetchResult(FetchStatus.failed);
    } finally {
      client.close(force: true);
    }
  };
}
