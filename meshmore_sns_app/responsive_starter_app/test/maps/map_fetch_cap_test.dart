// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/maps/map_fetch.dart';

/// The body cap, tested against a real socket.
///
/// This is the one path where a fake cannot stand in: the defect was that the
/// body was read to the end and only then compared to the limit, so the test has
/// to serve a body bigger than the limit and show that the read stopped.
void main() {
  late HttpServer server;
  late Uint8List big;
  HttpOverrides? saved;

  setUp(() async {
    // The widget-test binding installs an HTTP override that answers every
    // request with 400, which is right for widget tests and wrong for the one
    // test that has to prove a socket read stops early.
    saved = HttpOverrides.current;
    HttpOverrides.global = null;
    big = Uint8List(64 * 1024);
    for (int i = 0; i < big.length; i++) {
      big[i] = 0x41;
    }
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest req) async {
      // Only announce a length for the first path, so both branches are covered:
      // refused on the header, and refused while streaming.
      if (req.uri.path == '/length') {
        req.response.contentLength = big.length;
      } else {
        req.response.bufferOutput = false;
      }
      req.response.add(big);
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    HttpOverrides.global = saved;
  });

  final MapFetcher fetch = httpMapFetcher(() => 'MeshmoreSNS/test');

  test('a body longer than the cap is refused, not read and then refused', () async {
    final FetchResult r = await fetch(
        Uri.parse('http://${server.address.host}:${server.port}/chunked'),
        maxBytes: 1024);
    expect(r.tooLarge, isTrue);
    expect(r.bytes, isNull,
        reason: 'the point of the cap is that the bytes are never held');
  });

  test('an announced length over the cap is refused before the body', () async {
    final FetchResult r = await fetch(
        Uri.parse('http://${server.address.host}:${server.port}/length'),
        maxBytes: 1024);
    expect(r.tooLarge, isTrue);
    expect(r.bytes, isNull);
  });

  test('a body inside the cap is returned whole', () async {
    final FetchResult r = await fetch(
        Uri.parse('http://${server.address.host}:${server.port}/chunked'),
        maxBytes: 1024 * 1024);
    expect(r.tooLarge, isFalse);
    expect(r.status, FetchStatus.ok);
    expect(r.bytes, hasLength(big.length));
  });

  test('no cap means no limit, which is what a tile asks for', () async {
    final FetchResult r = await fetch(
        Uri.parse('http://${server.address.host}:${server.port}/chunked'));
    expect(r.bytes, hasLength(big.length));
    expect(r.tooLarge, isFalse);
  });
}
