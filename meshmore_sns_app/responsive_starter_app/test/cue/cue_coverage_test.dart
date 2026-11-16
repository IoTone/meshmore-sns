// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/cue/cue_service.dart';

/// A cue that exists in all eleven packs and is played by nothing is a sound the
/// theme promised and never made. Two were in that state: `send` (the "that went"
/// tick) and `scanStart` (the scanning drone).
///
/// This is a source-level audit, which is unusual, but the alternative is a widget
/// test per cue per screen and the property being guarded is exactly "something
/// calls this".
void main() {
  final Map<CueKind, int> used = <CueKind, int>{};

  setUpAll(() {
    final Iterable<File> files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .where((File f) => !f.path.contains('lib/gen/'));
    for (final File f in files) {
      final String src = f.readAsStringSync();
      for (final CueKind k in CueKind.values) {
        final int hits =
            RegExp('CueKind\\.${k.name}\\b').allMatches(src).length;
        used[k] = (used[k] ?? 0) + hits;
      }
      // A signature is played through `playSignature(slot)`, which resolves the
      // slot to `sigN` inside the service: counting the literal `CueKind.sigN`
      // would call a used cue unused.
      final int sig = RegExp('playSignature\\(').allMatches(src).length;
      if (sig > 0) {
        for (final CueKind k in CueKind.values) {
          if (k.name.startsWith('sig')) used[k] = (used[k] ?? 0) + sig;
        }
      }
    }
  });

  test('every cue kind is reachable from something the app does', () {
    final List<String> silent = <String>[
      for (final CueKind k in CueKind.values)
        if ((used[k] ?? 0) == 0) k.name,
    ];
    expect(
      silent,
      isEmpty,
      reason: 'these cues ship in every audio pack and nothing plays them: '
          '${silent.join(', ')}',
    );
  });

  test('the send tick is played where a message actually leaves', () {
    // The one that was silent for the life of the feature.
    expect(used[CueKind.send], greaterThan(0),
        reason: 'a pack full of "that went" sounds and no sender hears one');
  });

  test('the scanning drone is started and stopped, not only started', () {
    final String pair =
        File('lib/screens/pair_radio_screen.dart').readAsStringSync();
    expect(pair.contains('startScanHum'), isTrue);
    expect(pair.contains('stopScanHum'), isTrue,
        reason: 'a drone that is started and never stopped loops for ever');
  });
}
