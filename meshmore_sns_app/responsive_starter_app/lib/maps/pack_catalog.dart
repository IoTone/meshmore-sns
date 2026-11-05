// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:convert';

import 'tile_math.dart';

/// Where the published pack list comes from at build time.
///
/// Empty means "the bundle only": the app ships `assets/maps/packs.json` and
/// never asks the network for a list. A host that publishes packs points this
/// at its own JSON with
/// `flutter build apk --dart-define=MESHMORE_PACK_CATALOG=https://…/packs.json`.
/// The app does not host packs and this constant does not invent a service: an
/// empty value is the honest default until someone publishes a list.
const String kPackCatalogUrl =
    String.fromEnvironment('MESHMORE_PACK_CATALOG', defaultValue: '');

/// One region a host has published as a single PMTiles file.
///
/// [bytes] and [sha256] are the host's own published figures: with them the
/// download is verified before it is used, and without them only the structure
/// is checked. [licence] and [attribution] are not optional in practice — a
/// pack carries OpenStreetMap-derived data, whose ODbL terms require both — so
/// a catalogue entry that omits them is refused rather than shown unlabelled.
class CatalogPack {
  const CatalogPack({
    required this.id,
    required this.name,
    required this.url,
    required this.minZoom,
    required this.maxZoom,
    required this.box,
    required this.bytes,
    required this.sha256,
    required this.licence,
    required this.attribution,
    this.publisher = '',
    this.description = '',
  });

  final String id;
  final String name;
  final String url;
  final int minZoom;
  final int maxZoom;
  final GeoBox box;

  /// Published file size, or 0 when the host does not say.
  final int bytes;

  /// Lower-case hex SHA-256, or null when the host does not publish one.
  final String? sha256;
  final String licence;
  final String attribution;
  final String publisher;
  final String description;

  /// What a user is told before the download starts, e.g. "Austin · z6–z14 ·
  /// 320 MB".
  String get summary {
    final String size = bytes <= 0
        ? ''
        : ' · ${(bytes / 1000000).toStringAsFixed(bytes >= 100000000 ? 0 : 1)} MB';
    return '$name · z$minZoom–z$maxZoom$size';
  }
}

/// Why a catalogue could not be read, in the order the loader tries.
enum CatalogProblem {
  /// The built-in list is missing or unreadable: a packaging bug.
  bundledMissing,

  /// The remote list did not answer.
  remoteUnreachable,

  /// The remote list answered with something that is not a pack list.
  remoteMalformed,
}

/// The list of packs a user may install, plus where it came from.
class PackCatalog {
  const PackCatalog({
    required this.packs,
    required this.fromBundle,
    this.remoteProblem,
    this.remoteUrl,
  });

  static const PackCatalog empty = PackCatalog(
    packs: <CatalogPack>[],
    fromBundle: true,
  );

  final List<CatalogPack> packs;

  /// True when this is the bundled list (no remote list was configured, or
  /// the remote one failed and the bundle stood in).
  final bool fromBundle;

  /// Set when a remote list was configured and could not be used.
  final CatalogProblem? remoteProblem;
  final String? remoteUrl;

  /// True when nothing has been published yet, which is a state the screen
  /// says out loud rather than showing an empty list.
  bool get isEmpty => packs.isEmpty;

  /// Parses a catalogue document. Accepts `{"packs": [...]}` or a bare array.
  /// Throws [FormatException] with a line that names the offending entry.
  static List<CatalogPack> parse(String text) {
    final Object? root = jsonDecode(text);
    final List<Object?> rows = switch (root) {
      List<Object?> l => l,
      Map<String, Object?> m => (m['packs'] as List<Object?>?) ?? <Object?>[],
      _ => throw const FormatException('catalogue is not a list or object'),
    };
    final List<CatalogPack> out = <CatalogPack>[];
    for (int i = 0; i < rows.length; i++) {
      final Object? row = rows[i];
      if (row is! Map<String, Object?>) {
        throw FormatException('entry $i is not an object');
      }
      out.add(_entry(row, i));
    }
    return out;
  }

  static CatalogPack _entry(Map<String, Object?> j, int i) {
    String str(String key, {bool required = true}) {
      final Object? v = j[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (!required) return '';
      throw FormatException('entry $i: "$key" is missing');
    }

    int num0(String key, {bool required = true, int fallback = 0}) {
      final Object? v = j[key];
      if (v is num) return v.toInt();
      if (!required) return fallback;
      throw FormatException('entry $i: "$key" is missing');
    }

    final String url = str('url');
    final Uri? u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) {
      throw FormatException('entry $i: "url" must be https');
    }
    final String licence = str('licence', required: false);
    final String attribution = str('attribution', required: false);
    if (licence.isEmpty || attribution.isEmpty) {
      // An unlabelled pack is a licence problem, not a cosmetic one: the data
      // under it is ODbL, which requires attribution wherever it is shown.
      throw FormatException('entry $i: "licence" and "attribution" are required');
    }
    final Object? box = j['bbox'];
    if (box is! List<Object?> || box.length != 4) {
      throw FormatException('entry $i: "bbox" must be [west, south, east, north]');
    }
    final List<double> b = <double>[
      for (final Object? v in box)
        if (v is num) v.toDouble() else double.nan,
    ];
    if (b.any((double v) => v.isNaN)) {
      throw FormatException('entry $i: "bbox" must be four numbers');
    }
    final int minZoom = num0('minZoom');
    final int maxZoom = num0('maxZoom');
    if (minZoom < 0 || maxZoom < minZoom || maxZoom > 16) {
      throw FormatException('entry $i: zoom range $minZoom–$maxZoom is not usable');
    }
    final String? sha = j['sha256'] is String && (j['sha256']! as String).isNotEmpty
        ? (j['sha256']! as String).toLowerCase()
        : null;
    if (sha != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw FormatException('entry $i: "sha256" is not a hex digest');
    }
    return CatalogPack(
      id: str('id', required: false).isEmpty ? 'p$i' : str('id'),
      name: str('name'),
      url: url,
      minZoom: minZoom,
      maxZoom: maxZoom,
      box: GeoBox(west: b[0], south: b[1], east: b[2], north: b[3]),
      bytes: num0('bytes', required: false),
      sha256: sha,
      licence: licence,
      attribution: attribution,
      publisher: str('publisher', required: false),
      description: str('description', required: false),
    );
  }
}

/// Reads the bundle, then the remote list when one is configured.
///
/// The bundle is the fallback in both directions: a missing remote list keeps
/// the bundled one, and a remote list that will not parse is reported rather
/// than replacing what already worked.
class PackCatalogLoader {
  const PackCatalogLoader({required this.bundled, this.remote, this.url});

  /// Returns the packaged JSON.
  final Future<String> Function() bundled;

  /// Fetches a URL and returns its body. Null = no remote list configured.
  final Future<String> Function(Uri url)? remote;
  final String? url;

  Future<PackCatalog> load() async {
    List<CatalogPack> local;
    try {
      local = PackCatalog.parse(await bundled());
    } on Object {
      local = const <CatalogPack>[];
    }
    final String? u = url;
    if (u == null || u.isEmpty || remote == null) {
      return PackCatalog(packs: local, fromBundle: true);
    }
    final Uri? parsed = Uri.tryParse(u);
    if (parsed == null || parsed.scheme != 'https') {
      return PackCatalog(
        packs: local,
        fromBundle: true,
        remoteProblem: CatalogProblem.remoteMalformed,
        remoteUrl: u,
      );
    }
    try {
      final List<CatalogPack> remotePacks =
          PackCatalog.parse(await remote!(parsed));
      return PackCatalog(packs: remotePacks, fromBundle: false, remoteUrl: u);
    } on Object {
      return PackCatalog(
        packs: local,
        fromBundle: true,
        remoteProblem: CatalogProblem.remoteUnreachable,
        remoteUrl: u,
      );
    }
  }
}
