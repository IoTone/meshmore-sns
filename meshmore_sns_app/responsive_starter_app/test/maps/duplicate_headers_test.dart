// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/maps/map_fetch.dart';

/// R80 device run: OpenFreeMap answers a tile with **two** `cache-control`
/// headers. `HttpHeaders.value()` throws on that ("More than one value for
/// header cache-control"), the exception vanished into `catch (_)`, every
/// tile came back null, and the map was blank with no other symptom.
///
/// These tests drive a real loopback server, because the bug is in how the
/// response headers are read, and only a real response reproduces it.
void main() {
  late HttpServer server;
  late Uri base;

  // flutter_test installs an HttpOverrides that answers every request with
  // 400; this test needs a real socket to reproduce a real header shape.
  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}/');
    // Answer every request with the bytes and headers of the current case.
    server.listen((HttpRequest req) async {
      final _Reply r = _reply;
      for (final MapEntry<String, List<String>> h in r.headers.entries) {
        for (final String v in h.value) {
          req.response.headers.add(h.key, v);
        }

      }
      req.response.statusCode = r.status;
      req.response.add(r.body);
      await req.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  final MapFetcher fetcher = httpMapFetcher(() => 'MeshmoreSNS/test');

  test('a repeated cache-control header no longer fails the fetch', () async {
    _reply = _Reply.ok(<String, List<String>>{
      'cache-control': <String>['public, max-age=600', 'max-age=600'],
    });
    final FetchResult r = await fetcher(base);
    expect(r.status, FetchStatus.ok, reason: 'this used to throw');
    expect(r.bytes, isNotNull);
    expect(r.maxAge, const Duration(seconds: 600));
  });

  test('a repeated last-modified header no longer fails the fetch', () async {
    _reply = _Reply.ok(<String, List<String>>{
      'last-modified': <String>[
        'Wed, 21 Oct 2026 07:28:00 GMT',
        'Wed, 21 Oct 2026 07:28:00 GMT',
      ],
    });
    final FetchResult r = await fetcher(base);
    expect(r.status, FetchStatus.ok, reason: 'this used to throw');
    expect(r.lastModified, startsWith('Wed, 21 Oct 2026'));
  });

  test('a single value behaves exactly as before', () async {
    _reply = _Reply.ok(<String, List<String>>{
      'cache-control': <String>['public, max-age=60'],
      'etag': <String>['"b"'],
    });
    final FetchResult r = await fetcher(base);
    expect(r.maxAge, const Duration(seconds: 60));
    expect(r.etag, '"b"');
  });
}

class _Reply {
  const _Reply(this.status, this.headers) : body = _kB;
  const _Reply.ok(this.headers) : status = 200, body = _kB;

  static const List<int> _kB = <int>[1, 2, 3];
  final int status;
  final Map<String, List<String>> headers;
  final List<int> body;
}

late _Reply _reply;
