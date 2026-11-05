// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../places/place.dart';
import '../telemetry/coverage_model.dart';
import 'position_history.dart';

/// One file for an after-action read: where we went, what we reported, which
/// pings were answered, and what the check-in said
/// (`meshmore-feature-register.md` §5, "Operational export").
///
/// A bundle is a *window*, not a dump: it is cut to the interval the user
/// names, and its manifest states what the window contained and what it did
/// not, so a reader cannot mistake an empty section for a quiet period when it
/// was really a period the app was closed.
abstract final class OperationalExport {
  static const int formatVersion = 1;

  static Map<String, Object?> build({
    required List<PositionSample> trail,
    required List<Place> places,
    required List<CoverageSample> coverage,
    required List<CoverageEdge> edges,
    required DateTime from,
    required DateTime to,
    required DateTime now,
    Map<String, Object?>? checkin,
  }) {
    final List<PositionSample> trailInWindow = <PositionSample>[
      for (final PositionSample s in trail)
        if (!s.at.isBefore(from) && !s.at.isAfter(to)) s,
    ];
    final List<CoverageSample> coverageInWindow = <CoverageSample>[
      for (final CoverageSample s in coverage)
        if (!s.at.isBefore(from) && !s.at.isAfter(to)) s,
    ];
    final int answeredPings =
        coverageInWindow.where((CoverageSample s) => s.answered).length;
    final int unansweredPings =
        coverageInWindow.where((CoverageSample s) => !s.answered).length;

    return <String, Object?>{
      'format': 'meshmore.field',
      'version': formatVersion,
      'createdAtMs': now.millisecondsSinceEpoch,
      'window': <String, Object?>{
        'fromMs': from.millisecondsSinceEpoch,
        'toMs': to.millisecondsSinceEpoch,
      },
      // The manifest is the part a reader reads first: what is inside, how
      // many of each, and the one caveat that makes the numbers honest.
      'manifest': <String, Object?>{
        'trailPoints': trailInWindow.length,
        'places': places.length,
        'coverageSamples': coverageInWindow.length,
        'coverageAnsweredPings': answeredPings,
        'coverageUnansweredPings': unansweredPings,
        'observedEdges': edges.length,
        'checkins': checkin == null ? 0 : 1,
        'caveat': 'Sections are cut to the window. An empty trail or an empty '
            'coverage list means nothing was recorded in the window by this '
            'device, not that nothing happened on the mesh.',
      },
      'trail': <Object?>[
        for (final PositionSample s in trailInWindow)
          <String, Object?>{
            'atMs': s.at.millisecondsSinceEpoch,
            'lat': s.latitude,
            'lon': s.longitude,
            if (s.altitudeMeters != null) 'altM': s.altitudeMeters,
            'source': s.source.name,
          },
      ],
      'places': <Object?>[
        for (final Place p in places)
          <String, Object?>{
            'id': p.id,
            'label': p.label,
            'type': p.typeToken,
            'lat': p.latE6 / 1e6,
            'lon': p.lonE6 / 1e6,
            'reporter': p.reporterName,
            'provenance': p.provenance.name,
            'sentAtMs': p.sentAt.millisecondsSinceEpoch,
            'expiresAtMs': p.expiresAt.millisecondsSinceEpoch,
            'expired': p.expiresAt.isBefore(now),
          },
      ],
      'coverage': <String, Object?>{
        'samples': <Object?>[
          for (final CoverageSample s in coverageInWindow)
            <String, Object?>{
              'atMs': s.at.millisecondsSinceEpoch,
              'cell': s.cell,
              'answered': s.answered,
              if (s.snr != null) 'snr': s.snr,
              if (s.rssi != null) 'rssi': s.rssi,
              if (s.hops != null) 'hops': s.hops,
            },
        ],
        'observedEdges': <Object?>[
          for (final CoverageEdge e in edges)
            <String, Object?>{
              'keyHex': e.responderKey
                  .map((int b) => b.toRadixString(16).padLeft(2, '0'))
                  .join(),
              'responses': e.responses,
            },
        ],
      },
      'checkins': <Object?>[
        if (checkin != null) checkin,
      ],
    };
  }

  /// Writes the bundle to a temporary file. The file is plain JSON and the
  /// screen says so: a field record is meant to be handed on, and encrypting
  /// it would defeat that, unlike the message history which is sealed by
  /// default.
  static Future<File> write(
    Map<String, Object?> bundle, {
    Directory? directory,
    DateTime Function()? clock,
  }) async {
    final Directory dir = directory ?? await getTemporaryDirectory();
    final int stamp = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final File file = File('${dir.path}/meshmore-field-$stamp.json');
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(bundle));
    return file;
  }
}
