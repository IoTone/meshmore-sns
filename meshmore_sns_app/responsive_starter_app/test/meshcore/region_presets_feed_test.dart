// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/region_presets.dart';

/// The preset table against a snapshot of the MeshCore project's own feed.
///
/// Refresh the snapshot with:
///   curl -s https://api.meshcore.nz/api/v1/config
/// and keep `config.suggested_radio_settings.entries` (title, frequency,
/// bandwidth, spreading_factor, coding_rate, network_settings.path_hash_size).
/// A failure here means the table and the feed disagree, which is the exact
/// failure that shipped four wrong coding rates.
void main() {
  final Map<String, dynamic> snap = jsonDecode(
    File('test/meshcore/fixtures/meshcore_api_presets.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final List<Map<String, dynamic>> entries =
      (snap['entries'] as List<dynamic>).cast<Map<String, dynamic>>();

  bool sameTuple(RegionPreset p, Map<String, dynamic> e) =>
      (p.frequencyMhz - double.parse(e['frequency'] as String)).abs() < 0.0005 &&
      (p.bandwidthKhz - double.parse(e['bandwidth'] as String)).abs() < 0.0005 &&
      p.spreadingFactor == int.parse(e['spreading_factor'] as String) &&
      p.codingRate == int.parse(e['coding_rate'] as String);

  test('the snapshot is the 26-entry feed', () {
    expect(entries, hasLength(26));
  });

  test('every feed entry is in the table with the same four numbers', () {
    for (final Map<String, dynamic> e in entries) {
      final List<RegionPreset> hits =
          kRegionPresets.where((RegionPreset p) => sameTuple(p, e)).toList();
      expect(hits, isNotEmpty, reason: '${e['title']} is missing');
      expect(hits.any((RegionPreset p) => p.source == PresetSource.meshcoreApi),
          isTrue,
          reason: '${e['title']} exists but is not marked as feed-sourced');
    }
  });

  test('path hash size from the feed is carried, except Canada vs USA', () {
    for (final Map<String, dynamic> e in entries) {
      final int? ph = e['path_hash_size'] as int?;
      if (ph == null) continue;
      final Iterable<RegionPreset> hits =
          kRegionPresets.where((RegionPreset p) => sameTuple(p, e));
      if (e['title'] == 'Canada') {
        // Same radio tuple as "USA", which lists no hash size. Applying 3
        // would change a US user's setting (and shrink their directed
        // payload budget) on the strength of a Canada-only entry.
        expect(presetById('us_canada')!.pathHashSize, isNull);
        continue;
      }
      expect(hits.any((RegionPreset p) => p.pathHashSize == ph), isTrue,
          reason: '${e['title']} should carry path hash $ph');
    }
  });

  test('a feed-sourced preset that is not in the feed does not exist', () {
    for (final RegionPreset p in kRegionPresets) {
      if (p.source != PresetSource.meshcoreApi) continue;
      expect(entries.any((Map<String, dynamic> e) => sameTuple(p, e)), isTrue,
          reason: '${p.id} claims the feed but the feed has no such tuple');
    }
  });

  test('presets the feed lacks are labelled third-party', () {
    for (final String id in <String>['us_arizona', 'jp_arib_t108', 'jp_meshcore', 'eu_uk_medium']) {
      expect(presetById(id)!.source, PresetSource.thirdParty, reason: id);
    }
  });

  test('ids are unique, and every preset has a family and a label', () {
    final Set<String> ids = kRegionPresets.map((RegionPreset p) => p.id).toSet();
    expect(ids, hasLength(kRegionPresets.length));
    for (final RegionPreset p in kRegionPresets) {
      expect(regionFamilyOf(p.id), isNot(RegionFamily.other), reason: p.id);
      expect(p.label, isNotEmpty);
    }
  });
}
