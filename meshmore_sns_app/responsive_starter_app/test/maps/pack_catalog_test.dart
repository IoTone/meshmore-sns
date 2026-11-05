// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshmore_sns_app/maps/pack_catalog.dart';

const String _validSha = 'abababababababababababababababababababababababababababababababab';

const String _valid = '''
{
  "packs": [
    {
      "id": "austin",
      "name": "Austin",
      "url": "https://packs.example/austin.pmtiles",
      "bbox": [-97.9, 30.1, -97.6, 30.5],
      "minZoom": 6,
      "maxZoom": 14,
      "bytes": 320000000,
      "sha256": "$_validSha",
      "licence": "ODbL 1.0",
      "attribution": "© OpenStreetMap contributors",
      "publisher": "example",
      "description": "Central Texas"
    }
  ]
}
''';

Future<String> _bundleOne() async => jsonEncode(<Object>[
      <String, Object>{
        'id': 'bundle',
        'name': 'Bundled',
        'url': 'https://packs.example/bundled.pmtiles',
        'bbox': <double>[-1, -1, 1, 1],
        'minZoom': 6,
        'maxZoom': 12,
        'licence': 'ODbL 1.0',
        'attribution': '© OpenStreetMap contributors',
      }
    ]);

Map<String, Object?> _row({
  String name = 'Ridge',
  String url = 'https://packs.example/r.pmtiles',
  int minZoom = 8,
  int maxZoom = 12,
  String? sha,
  String? licence = 'ODbL 1.0',
  String? attribution = '© OpenStreetMap contributors',
}) =>
    <String, Object?>{
      'name': name,
      'url': url,
      'bbox': <double>[-1, -1, 1, 1],
      'minZoom': minZoom,
      'maxZoom': maxZoom,
      if (sha != null) 'sha256': sha,
      if (licence != null) 'licence': licence,
      if (attribution != null) 'attribution': attribution,
    };

Matcher _formatError(String needle) => throwsA(
      isA<FormatException>().having(
          (FormatException e) => e.message, 'message', contains(needle)),
    );

void main() {
  group('catalogue parsing', () {
    test('a published entry keeps its terms and its size', () {
      final List<CatalogPack> packs = PackCatalog.parse(_valid);
      expect(packs, hasLength(1));
      final CatalogPack p = packs.single;
      expect(p.id, 'austin');
      expect(p.name, 'Austin');
      expect(p.minZoom, 6);
      expect(p.maxZoom, 14);
      expect(p.bytes, 320000000);
      expect(p.sha256, _validSha);
      expect(p.licence, 'ODbL 1.0');
      expect(p.attribution, '© OpenStreetMap contributors');
      expect(p.summary, contains('Austin'));
      expect(p.summary, contains('z6–z14'));
      expect(p.summary, contains('320 MB'));
    });

    test('a bare array is accepted, and a missing size is honest', () {
      final List<CatalogPack> packs = PackCatalog.parse(jsonEncode(<Object>[
        _row(),
      ]));
      expect(packs.single.bytes, 0);
      expect(packs.single.sha256, isNull);
      expect(packs.single.summary, isNot(contains('MB')));
    });

    test('an unlabelled pack is refused, because the data requires both', () {
      expect(
        () => PackCatalog.parse(
            jsonEncode(<Object>[_row(licence: null)])),
        _formatError('licence'),
      );
    });

    test('a plain-http url is refused', () {
      expect(
        () => PackCatalog.parse(jsonEncode(<Object>[
          _row(url: 'http://packs.example/c.pmtiles'),
        ])),
        _formatError('https'),
      );
    });

    test('an unusable zoom range is refused', () {
      expect(
        () => PackCatalog.parse(jsonEncode(<Object>[
          _row(minZoom: 14, maxZoom: 8),
        ])),
        _formatError('zoom'),
      );
    });

    test('a malformed digest is refused rather than compared to nothing', () {
      expect(
        () => PackCatalog.parse(jsonEncode(<Object>[
          _row(sha: 'not-a-digest'),
        ])),
        _formatError('sha256'),
      );
    });
  });

  group('loader', () {
    test('no published list: the bundle is the list', () async {
      final PackCatalog c =
          await const PackCatalogLoader(bundled: _bundleOne).load();
      expect(c.fromBundle, isTrue);
      expect(c.remoteProblem, isNull);
      expect(c.packs, hasLength(1));
    });

    test('a published list wins when it parses', () async {
      final PackCatalog c = await PackCatalogLoader(
        bundled: _bundleOne,
        url: 'https://packs.example/packs.json',
        remote: (Uri u) async => _valid,
      ).load();
      expect(c.fromBundle, isFalse);
      expect(c.remoteUrl, 'https://packs.example/packs.json');
      expect(c.packs.single.id, 'austin');
    });

    test('a list that will not answer keeps the bundle and says why', () async {
      final PackCatalog c = await PackCatalogLoader(
        bundled: _bundleOne,
        url: 'https://packs.example/packs.json',
        remote: (Uri u) async => throw const FormatException('offline'),
      ).load();
      expect(c.fromBundle, isTrue);
      expect(c.remoteProblem, CatalogProblem.remoteUnreachable);
      expect(c.packs, hasLength(1));
    });

    test('a list that is not https is reported, not fetched', () async {
      bool called = false;
      final PackCatalog c = await PackCatalogLoader(
        bundled: _bundleOne,
        url: 'http://packs.example/packs.json',
        remote: (Uri u) async {
          called = true;
          return _valid;
        },
      ).load();
      expect(called, isFalse);
      expect(c.remoteProblem, CatalogProblem.remoteMalformed);
      expect(c.packs, hasLength(1));
    });

    test('a bundle that is unreadable leaves an empty list, not a crash',
        () async {
      final PackCatalog c = await PackCatalogLoader(
        bundled: () async => 'not json at all',
      ).load();
      expect(c.isEmpty, isTrue);
      expect(c.fromBundle, isTrue);
    });
  });
}
