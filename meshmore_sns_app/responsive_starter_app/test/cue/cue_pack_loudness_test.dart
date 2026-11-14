// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/cue/cue_service.dart';
import 'package:meshmore_sns_app/theme/mm_tokens.dart';

/// A cue nobody can hear is a cue that does not exist.
///
/// Measured on the handset 2026-11-14: the packs held 30-150 ms files peaking
/// at -10 to -15 dBFS, so at a media volume of 3/15 (about -14 dB) the audible
/// peak was near -24 dBFS and the owner reported "the themes have no sound".
/// The wiring was never the problem — every cue fires — so this test holds the
/// *files* to the two floors that make a cue perceptible, and it holds every
/// theme and every cue, because a pack that is quiet is a theme that is quiet.
///
/// The floors mirror `brand/_audio_pack.py` (`TARGET_PEAK_DB`, `MIN_DUR`); the
/// generator is the only thing that should ever move them.
const Map<String, double> _minSeconds = <String, double>{
  'navNext': 0.10,
  'navPrev': 0.10,
  'send': 0.13,
  'advert': 0.30,
  'linkUp': 0.32,
  'linkDown': 0.32,
  'taskError': 0.35,
  'messageIn': 0.40,
  'taskOk': 0.40,
  'dmIn': 0.45,
  'discovery': 0.45,
  'sig1': 0.45,
  'sig2': 0.45,
  'sig3': 0.45,
  'sig4': 0.45,
  'sig5': 0.45,
  'boot': 0.55,
  'alert': 0.90,
  'scanStart': 1.00,
};

/// -4.4 dBFS: a peak quieter than this is a peak a phone speaker rounds off.
const double kPeakFloor = 0.6;

/// -22 dBFS: the average level below which a cue reads as a click, not a tone.
const double kRmsFloor = 0.08;

/// The drone loops, so it is normalised lower on purpose (-6 dBFS peak).
const double kDronePeakCeiling = 0.62;

class _Wav {
  _Wav(this.seconds, this.peak, this.rms);
  final double seconds;
  final double peak;
  final double rms;
}

_Wav _read(String path) {
  final Uint8List bytes = File(path).readAsBytesSync();
  final ByteData d = ByteData.sublistView(bytes);
  // Minimal RIFF walk: find `fmt ` for the rate and `data` for the samples.
  int sampleRate = 0;
  int dataOffset = -1;
  int dataLength = 0;
  int i = 12;
  while (i + 8 <= bytes.length) {
    final String id = String.fromCharCodes(bytes.sublist(i, i + 4));
    final int size = d.getUint32(i + 4, Endian.little);
    if (id == 'fmt ') {
      sampleRate = d.getUint32(i + 12, Endian.little);
    } else if (id == 'data') {
      dataOffset = i + 8;
      dataLength = size;
    }
    i += 8 + size + (size.isOdd ? 1 : 0);
  }
  expect(sampleRate, greaterThan(0), reason: '$path has no fmt chunk');
  expect(dataOffset, greaterThan(0), reason: '$path has no data chunk');

  final int count = dataLength ~/ 2;
  double peak = 0;
  double sumSq = 0;
  for (int s = 0; s < count; s++) {
    final int v = d.getInt16(dataOffset + s * 2, Endian.little);
    final double a = (v.abs()) / 32768.0;
    if (a > peak) peak = a;
    sumSq += a * a;
  }
  return _Wav(count / sampleRate, peak, math.sqrt(sumSq / math.max(1, count)));
}

void main() {
  const String root = 'assets/audio';

  test('every theme ships its own folder for every cue', () {
    final List<String> themes = MmThemePreset.values
        .map((MmThemePreset p) => p.audioPackKey)
        .toList();
    for (final String theme in themes) {
      for (final CueKind kind in CueKind.values) {
        final File f = File('$root/$theme/${kind.name}.wav');
        expect(f.existsSync(), isTrue,
            reason: '$theme is missing ${kind.name}.wav');
      }
    }
  });

  test('no cue is too quiet or too short to hear', () {
    final Map<String, List<String>> failures = <String, List<String>>{};
    for (final MmThemePreset preset in MmThemePreset.values) {
      for (final CueKind kind in CueKind.values) {
        final String path = '$root/${preset.audioPackKey}/${kind.name}.wav';
        final _Wav w = _read(path);
        final List<String> why = failures.putIfAbsent(kind.name, () => <String>[]);
        final double min = _minSeconds[kind.name]!;
        if (w.seconds + 1e-3 < min) {
          why.add('${preset.name} ${w.seconds.toStringAsFixed(2)}s < '
              '${min.toStringAsFixed(2)}s');
        }
        if (kind == CueKind.scanStart) {
          // The drone loops for the whole scan window, so it is held to a
          // ceiling rather than a floor: loud enough to hear, quiet enough not
          // to sit under everything for thirty seconds.
          if (w.peak > kDronePeakCeiling) {
            why.add('${preset.name} drone peak ${w.peak.toStringAsFixed(2)} > '
                '$kDronePeakCeiling');
          }
        } else if (w.peak < kPeakFloor) {
          why.add('${preset.name} peak ${w.peak.toStringAsFixed(2)} < '
              '$kPeakFloor');
        }
        if (w.rms < kRmsFloor) {
          why.add('${preset.name} rms ${w.rms.toStringAsFixed(3)} < '
              '$kRmsFloor');
        }
      }
    }
    failures.removeWhere((String _, List<String> v) => v.isEmpty);
    expect(failures, isEmpty, reason: 'inaudible cues: $failures');
  });

  test('every cue kind has a stated floor', () {
    for (final CueKind kind in CueKind.values) {
      expect(_minSeconds.containsKey(kind.name), isTrue,
          reason: 'add a perception floor for ${kind.name}');
    }
  });
}

