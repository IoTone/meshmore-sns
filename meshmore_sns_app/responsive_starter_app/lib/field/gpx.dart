// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'position_history.dart';

/// A trail as a GPX 1.1 track.
///
/// GPX is the interchange format every mapping tool reads, so the file is
/// written in the clear: encrypting it would defeat the only reason to export
/// one. That is why the screen says so before the share sheet opens — the
/// message store is sealed, an exported track is not
/// (`lib/meshcore/history_export.dart` is the encrypted counterpart).
abstract final class GpxTrack {
  /// GPX 1.1 with a single track and one segment, in time order.
  ///
  /// A sample with no altitude writes no `<ele>`: a zero would be read as sea
  /// level by every consumer, which is a worse lie than a missing element.
  static String encode(
    List<PositionSample> samples, {
    String name = 'MeshMore trail',
    DateTime? at,
  }) {
    final List<PositionSample> ordered = List<PositionSample>.of(samples)
      ..sort((PositionSample a, PositionSample b) => a.at.compareTo(b.at));
    final StringBuffer b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
          '<gpx version="1.1" creator="MeshMore" xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('  <metadata>')
      ..writeln('    <name>${_escape(name)}</name>')
      ..writeln('    <time>${_iso((at ?? DateTime.now()).toUtc())}</time>')
      ..writeln('  </metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>${_escape(name)}</name>')
      ..writeln('    <trkseg>');
    for (final PositionSample s in ordered) {
      b.writeln('      <trkpt lat="${_coord(s.latitude)}" '
          'lon="${_coord(s.longitude)}">');
      final double? alt = s.altitudeMeters;
      if (alt != null && alt.isFinite) {
        b.writeln('        <ele>${alt.toStringAsFixed(1)}</ele>');
      }
      b.writeln('        <time>${_iso(s.at.toUtc())}</time>');
      b.writeln('      </trkpt>');
    }
    b
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return b.toString();
  }

  /// Writes the track to a temporary file for a share sheet.
  static Future<File> write(
    List<PositionSample> samples, {
    String name = 'MeshMore trail',
    Directory? directory,
    DateTime Function()? clock,
  }) async {
    final Directory dir = directory ?? await getTemporaryDirectory();
    final int stamp = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    final File file = File('${dir.path}/meshmore-trail-$stamp.gpx');
    await file.writeAsString(encode(samples, name: name, at: clock?.call()));
    return file;
  }

  /// Six decimals is ~11 cm, past any GPS's accuracy, and is the precision
  /// the place convention already uses.
  static String _coord(double v) => v.toStringAsFixed(6);

  /// [DateTime.toIso8601String] already ends in `Z` for a UTC value; appending
  /// another would produce `...ZZ`, which no GPX reader accepts.
  static String _iso(DateTime utc) =>
      utc.isUtc ? utc.toIso8601String() : utc.toUtc().toIso8601String();

  /// XML character escaping for the name only; coordinates are numeric.
  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
